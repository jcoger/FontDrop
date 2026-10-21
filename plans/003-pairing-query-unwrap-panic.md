# 003 — Replace `.unwrap()` in the pairing query path with error propagation

**Status:** DONE
**Effort:** S
**Risk of the change:** Low (turns a panic into a handled error the UI already expects)
**Depends on:** 001 (recommended — keeps the test suite green around the change)
**Written against commit:** `abf6b72` (pairing feature is uncommitted working-tree changes on top of this commit)

---

## Why this matters

`load_all_fonts` in `src-tauri/src/pairing.rs` uses `.unwrap()` on the SQLite `prepare` and `query_map` calls:

```rust
fn load_all_fonts(conn: &Connection) -> Vec<FontData> {
    let mut stmt = conn
        .prepare(
            "SELECT font_id, font_family, skeleton, ... FROM fonts",
        )
        .unwrap();                       // <-- panics on any prepare error

    stmt.query_map([], |row| { ... })
    .unwrap()                            // <-- panics on any query error
    .filter_map(|r| r.ok())
    .collect()
}
```

This function is called by the `#[tauri::command] get_font_pairs`, which otherwise returns `Result<Vec<PairBucket>, String>` and is consumed by the frontend with a `.catch()` that already degrades gracefully:

`src/hooks/useFontPairs.ts`:
```ts
invoke<PairBucket[]>("get_font_pairs", { fontId })
  .then(setBuckets)
  .catch(() => setBuckets([]))   // UI is ready to handle an Err
  .finally(() => setLoading(false));
```

If a schema column is ever missing or renamed (exactly the kind of drift that the ad-hoc `ALTER TABLE ... ADD COLUMN` migrations in `db.rs` make possible), `prepare`/`query_map` returns `Err`, and `.unwrap()` **panics the command's worker thread** instead of returning an `Err(String)` that the UI's `.catch` would turn into a clean "no pairs" state. A panic in a Tauri command is a much worse failure mode (poisoned mutex, lost responsiveness) than a returned error.

The rest of `pairing.rs` and the sibling `db.rs::get_font_db` already use the `.map_err(|e| e.to_string())?` pattern — this `.unwrap()` is the inconsistent outlier.

---

## Current state

- `load_all_fonts(conn: &Connection) -> Vec<FontData>` — infallible signature, panics internally.
- Its only caller, `get_font_pairs`, is `Result`-returning:
  ```rust
  #[tauri::command]
  pub fn get_font_pairs(
      state: tauri::State<'_, DbState>,
      font_id: String,
  ) -> Result<Vec<PairBucket>, String> {
      let conn = state.0.lock().map_err(|e| e.to_string())?;
      let all = load_all_fonts(&conn);
      let primary = all.iter().find(|f| f.font_id == font_id)
          .ok_or_else(|| format!("Font {} not found", font_id))?;
      ...
  }
  ```
- Reference pattern already in the codebase — `db.rs::get_font_db`:
  ```rust
  let mut stmt = conn.prepare("SELECT ...").map_err(|e| e.to_string())?;
  let rows = stmt.query_map([], |row| { ... }).map_err(|e| e.to_string())?;
  ```

---

## The fix (chosen approach)

Change `load_all_fonts` to return `Result<Vec<FontData>, String>`, propagate the two errors with `.map_err(|e| e.to_string())?`, and have `get_font_pairs` use `?` on the call. This matches the established `get_font_db` pattern exactly. The per-row `.filter_map(|r| r.ok())` (which silently drops individual malformed rows) is preserved — only the *query-level* failures change from panic to propagated error.

---

## Scope

**In scope — modify ONLY:**
- `src-tauri/src/pairing.rs` — change `load_all_fonts` signature + body; update the one call site in `get_font_pairs`.
- `src-tauri/src/pairing.rs` test module (from plan 001) — optional: add a smoke test that builds an in-memory DB and confirms `Ok`. See Step 4 (only if `Connection` construction is feasible without extra deps — it is, via rusqlite's bundled feature).
- `plans/README.md` — set plan 003 status to `DONE`.

**Out of scope — do NOT touch:**
- The per-row `filter_map(|r| r.ok())` behavior.
- Any other `.unwrap()` in the codebase (e.g. `google_fonts.rs` `unwrap_or_else(|| panic!(...))` — a separate, deferred robustness item).
- The SQL string itself, frontend, other modules.

---

## Implementation steps

### Step 1 — Change the `load_all_fonts` signature and error handling

In `src-tauri/src/pairing.rs`, change:

```rust
fn load_all_fonts(conn: &Connection) -> Vec<FontData> {
    let mut stmt = conn
        .prepare(
            "SELECT font_id, font_family, skeleton, flesh_contrast, flesh_serif,
                    weight, x_height_ratio, cap_height_ratio, ascender_descender_ratio,
                    foundry, designer, file_name,
                    optical_role, superfamily_group, superfamily_role,
                    weight_range_min, weight_range_max, spacing_personality, width_class
             FROM fonts",
        )
        .unwrap();

    stmt.query_map([], |row| {
        Ok(FontData { ... })
    })
    .unwrap()
    .filter_map(|r| r.ok())
    .collect()
}
```

to:

```rust
fn load_all_fonts(conn: &Connection) -> Result<Vec<FontData>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT font_id, font_family, skeleton, flesh_contrast, flesh_serif,
                    weight, x_height_ratio, cap_height_ratio, ascender_descender_ratio,
                    foundry, designer, file_name,
                    optical_role, superfamily_group, superfamily_role,
                    weight_range_min, weight_range_max, spacing_personality, width_class
             FROM fonts",
        )
        .map_err(|e| e.to_string())?;

    let rows = stmt
        .query_map([], |row| {
            Ok(FontData { ... })   // keep the existing closure body unchanged
        })
        .map_err(|e| e.to_string())?
        .filter_map(|r| r.ok())
        .collect();

    Ok(rows)
}
```

> Leave the `Ok(FontData { ... })` row-mapping closure body exactly as it is — only the surrounding `.unwrap()`→`.map_err(...)?` and the function signature/return change.

### Step 2 — Update the call site in `get_font_pairs`

Change:
```rust
    let all = load_all_fonts(&conn);
```
to:
```rust
    let all = load_all_fonts(&conn)?;
```

(`get_font_pairs` already returns `Result<_, String>`, so `?` works directly.)

### Step 3 — Build and verify the type change compiles

```
cd src-tauri && cargo build 2>&1 | tail -15
```

**Expected:** clean build. If you see `error[E0308]: mismatched types` at the `find(...)` line after `let all = ...?`, it means the `?` wasn't applied or the signature wasn't updated — re-check Steps 1–2.

### Step 4 — (Optional but recommended) add a smoke test

If plan 001's test module exists, add a test that constructs an in-memory DB, creates the minimal `fonts` table, and confirms `get_font_pairs`-style loading returns `Ok`. Because `load_all_fonts` is private and takes a `&Connection`, test it directly:

```rust
    #[test]
    fn load_all_fonts_returns_ok_on_valid_schema() {
        use rusqlite::Connection;
        let conn = Connection::open_in_memory().expect("in-memory db");
        // Minimal schema with every column load_all_fonts SELECTs.
        conn.execute_batch(
            "CREATE TABLE fonts (
                font_id TEXT, font_family TEXT, skeleton TEXT, flesh_contrast TEXT,
                flesh_serif INTEGER, weight INTEGER, x_height_ratio REAL,
                cap_height_ratio REAL, ascender_descender_ratio REAL, foundry TEXT,
                designer TEXT, file_name TEXT, optical_role TEXT, superfamily_group TEXT,
                superfamily_role TEXT, weight_range_min INTEGER, weight_range_max INTEGER,
                spacing_personality TEXT, width_class TEXT
            );
            INSERT INTO fonts (font_id, font_family, skeleton, flesh_contrast, flesh_serif, weight, file_name)
            VALUES ('a','Alpha','geometric','linear',0,400,'Alpha.ttf');",
        ).expect("create+insert");

        let result = load_all_fonts(&conn);
        assert!(result.is_ok());
        assert_eq!(result.unwrap().len(), 1);
    }

    #[test]
    fn load_all_fonts_returns_err_on_missing_table() {
        use rusqlite::Connection;
        let conn = Connection::open_in_memory().expect("in-memory db");
        // No `fonts` table -> prepare should fail -> Err, not panic.
        let result = load_all_fonts(&conn);
        assert!(result.is_err(), "missing table must yield Err, not panic");
    }
```

> `rusqlite` is already a dependency with the `bundled` feature (`Cargo.toml:28`), so `Connection::open_in_memory()` works in tests with no new deps. If for some reason it doesn't link in the test target, skip these two tests and note it — the production change in Steps 1–2 is the core deliverable.

### Step 5 — Update the plan index

Set plan 003 status to `DONE` in `plans/README.md`.

---

## Verification / done criteria

```
cd src-tauri && cargo build 2>&1 | tail -5
```
**Expected:** clean build (the `.unwrap()` panics are gone).

```
cd src-tauri && grep -n "load_all_fonts" src/pairing.rs
```
**Expected:** signature reads `-> Result<Vec<FontData>, String>` and the call site reads `load_all_fonts(&conn)?`.

```
cd src-tauri && grep -c "\.unwrap()" src/pairing.rs
```
**Expected:** the two query-path `.unwrap()`s are gone. (Other `.unwrap()`s outside `load_all_fonts`, if any exist, are out of scope — but at the time of writing these two were the only ones in the file.)

```
cd src-tauri && cargo test --lib 2>&1 | tail -15
```
**Expected (if Step 4 done):** the two new `load_all_fonts_*` tests pass; all plan-001 tests still pass; zero failures.

---

## Test plan

Step 4's two tests cover both branches: valid schema → `Ok` with the expected row count; missing table → `Err` (the exact regression this plan prevents — a panic becomes a handled error). If plan 001 isn't present, the production change still stands and is verified by the build + grep criteria.

---

## Maintenance note

- This aligns `pairing.rs` with the `map_err(|e| e.to_string())?` convention used throughout `db.rs`. Any new query-running code added to `pairing.rs` should follow the same pattern — no `.unwrap()` on `prepare`/`query_map` in command-reachable paths.
- The per-row `.filter_map(|r| r.ok())` still silently drops individual malformed rows. That's an intentional, separate behavior (a single corrupt row shouldn't blank the whole pairing panel). If you ever want to surface per-row errors, that's a distinct change — don't fold it in here.

---

## Escape hatches — STOP and report instead of improvising if:

- `load_all_fonts` or `get_font_pairs` no longer matches the excerpts above (signature or call site refactored) — report the divergence; do not guess.
- The build fails after Step 2 with an error other than the expected `?`/signature mismatch — capture the error and report.
- `Connection::open_in_memory()` fails to compile/link in the test target — skip Step 4's tests, note it, and ship the production change (Steps 1–2), which is the actual fix.
