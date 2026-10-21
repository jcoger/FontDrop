# 006 — Add SQLite schema versioning (`PRAGMA user_version`) to replace ad-hoc `ALTER TABLE`

**Status:** DONE
**Effort:** M
**Risk of the change:** Med (touches DB init that runs at every startup; test against a real DB copy)
**Depends on:** none strictly; **pairs with plan 003** (003 makes the panic graceful; 006 removes the drift that triggers it). Do plan 001 first if you want the engine tests green around DB changes.
**Written against commit:** `abf6b72`

---

## Why this matters

The schema is created once, then extended by **nine sequential `ALTER TABLE … ADD COLUMN`** statements whose errors are swallowed:

`src/db.rs:124` (`open_db`):
```rust
    conn.execute_batch(CREATE_TABLE).expect("failed to create fonts table");
    // Migrations: add columns if missing (ignore "duplicate column" errors)
    conn.execute_batch("ALTER TABLE fonts ADD COLUMN classification_reason TEXT;").ok();
    conn.execute_batch("ALTER TABLE fonts ADD COLUMN optical_role TEXT;").ok();
    conn.execute_batch("ALTER TABLE fonts ADD COLUMN superfamily_group TEXT;").ok();
    conn.execute_batch("ALTER TABLE fonts ADD COLUMN superfamily_role TEXT;").ok();
    conn.execute_batch("ALTER TABLE fonts ADD COLUMN ascender_descender_ratio REAL;").ok();
    conn.execute_batch("ALTER TABLE fonts ADD COLUMN weight_range_min INTEGER;").ok();
    conn.execute_batch("ALTER TABLE fonts ADD COLUMN weight_range_max INTEGER;").ok();
    conn.execute_batch("ALTER TABLE fonts ADD COLUMN spacing_personality TEXT;").ok();
    conn.execute_batch("ALTER TABLE fonts ADD COLUMN width_class TEXT;").ok();
    conn
```

Problems:
- **`.ok()` swallows every error**, not just "duplicate column" — a genuinely failed migration is silent. The DB then has a column-set the query code assumes exists, and a `SELECT` of a missing column blows up downstream (this is exactly the panic plan 003 hardens — see `pairing.rs::load_all_fonts`).
- **No version record**, so there's no way to know what state an installed DB is in, and every future column requires appending another always-runs `ALTER … .ok()`.

This plan introduces an explicit, ordered, idempotent migration runner keyed on SQLite's `PRAGMA user_version`, so the schema state is known and migration failures surface instead of hiding.

---

## Current state

- `open_db(app_data_dir) -> Connection` in `db.rs` opens the file, sets pragmas (`journal_mode=WAL`, `foreign_keys=ON`), runs `CREATE_TABLE` (the base columns), then the nine `ALTER`s.
- `CREATE_TABLE` (`db.rs:73`) defines the base table **without** the nine added columns. The full current schema = base + the nine.
- Existing installed databases already have all nine columns (the idempotent `ALTER`s have been running). Their `user_version` is currently `0` (never set).
- `rusqlite` is the DB layer (`Cargo.toml:28`, `bundled` feature). `PRAGMA user_version` is read via `conn.pragma_query_value` / written via `conn.pragma_update` (or plain `execute`/`query_row` on `PRAGMA user_version`).

---

## The fix (chosen approach)

Define migrations as an **ordered list of SQL steps**. Read `PRAGMA user_version`; apply every migration whose index is `>= user_version`; set `user_version` to the new count. Make each `ADD COLUMN` tolerant of "duplicate column" **specifically** (so existing DBs that already have the columns converge to the right version without erroring), but surface any *other* error.

Target end state: `user_version = N` where `N` = number of migrations. The nine existing `ALTER`s become migration steps; existing DBs (which already have the columns) get their `user_version` bumped to `N` after the duplicate-tolerant re-apply is a no-op.

Keep it dependency-free — no `refinery`/`sqlx`; a small hand-rolled runner is appropriate for an embedded single-table app.

---

## Scope

**In scope — modify ONLY:**
- `src-tauri/src/db.rs` — `open_db` and a new private `run_migrations(&Connection)` helper (plus optional `#[cfg(test)]` tests if plan 001's harness pattern is in place).
- `plans/README.md` — set plan 006 status to `DONE`.

**Out of scope:**
- The `CREATE_TABLE` base string — leave it as the v0 baseline (the migration runner layers on top). Do **not** fold the nine columns into `CREATE_TABLE`; that would diverge from existing-DB reality.
- Query code in `db.rs`/`pairing.rs` — unchanged (the column set is identical; only *how* it's created changes).
- `classify_all` / `enrich_metrics` / `populate_db` — unchanged.

---

## Implementation steps

### Step 1 — Add a migrations list and runner

In `src-tauri/src/db.rs`, add near `CREATE_TABLE`:

```rust
/// Ordered schema migrations applied on top of CREATE_TABLE (the v0 baseline).
/// Append-only: never reorder or edit an existing entry once shipped, or
/// installed databases will skip or double-apply it. To change the schema,
/// add a new entry at the end.
const MIGRATIONS: &[&str] = &[
    "ALTER TABLE fonts ADD COLUMN classification_reason TEXT;",
    "ALTER TABLE fonts ADD COLUMN optical_role TEXT;",
    "ALTER TABLE fonts ADD COLUMN superfamily_group TEXT;",
    "ALTER TABLE fonts ADD COLUMN superfamily_role TEXT;",
    "ALTER TABLE fonts ADD COLUMN ascender_descender_ratio REAL;",
    "ALTER TABLE fonts ADD COLUMN weight_range_min INTEGER;",
    "ALTER TABLE fonts ADD COLUMN weight_range_max INTEGER;",
    "ALTER TABLE fonts ADD COLUMN spacing_personality TEXT;",
    "ALTER TABLE fonts ADD COLUMN width_class TEXT;",
];

/// Apply any migrations with index >= the DB's current user_version, then
/// stamp user_version to MIGRATIONS.len(). Tolerates "duplicate column"
/// (existing DBs already have these columns) but surfaces any other error.
fn run_migrations(conn: &Connection) {
    let current: i64 = conn
        .query_row("PRAGMA user_version;", [], |r| r.get(0))
        .unwrap_or(0);

    for (i, stmt) in MIGRATIONS.iter().enumerate() {
        if (i as i64) < current {
            continue; // already applied on this DB
        }
        if let Err(e) = conn.execute_batch(stmt) {
            let msg = e.to_string().to_lowercase();
            // Existing installs already have these columns: a duplicate-column
            // error here is expected and safe to ignore. Anything else is a
            // real failure we must not hide.
            if !msg.contains("duplicate column") {
                panic!("schema migration {} failed: {}", i, e);
            }
        }
    }

    // Stamp the new version. PRAGMA doesn't accept bound params, so format it.
    let target = MIGRATIONS.len();
    conn.execute_batch(&format!("PRAGMA user_version = {};", target))
        .expect("failed to set user_version");
}
```

> Notes:
> - Panicking on a *non*-duplicate migration error at startup is acceptable and intentional — a corrupt/failed schema is unrecoverable and should fail loudly rather than silently producing a DB the query code can't read. This is the **opposite** trade-off from plan 003 (which is about a *runtime command*); here it's one-time startup init, where a hard failure is the correct signal.
> - `PRAGMA user_version = N` cannot use a bound parameter — string-formatting the integer `MIGRATIONS.len()` is safe (it's not user input).

### Step 2 — Call the runner from `open_db` and delete the inline `ALTER`s

In `open_db`, replace the nine `.ok()` lines:

```rust
    conn.execute_batch(CREATE_TABLE)
        .expect("failed to create fonts table");
    run_migrations(&conn);
    conn
```

Delete the nine `conn.execute_batch("ALTER TABLE ... ").ok();` lines and their `// Migrations:` comment.

### Step 3 — Build

```
cd src-tauri && cargo build 2>&1 | tail -8
```
**Expected:** clean build.

### Step 4 — (Recommended) add an in-memory migration test

If plan 001's `#[cfg(test)]` pattern exists, add to a test module in `db.rs`:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::Connection;

    #[test]
    fn migrations_apply_from_scratch_and_set_version() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(CREATE_TABLE).unwrap();
        run_migrations(&conn);
        let v: i64 = conn.query_row("PRAGMA user_version;", [], |r| r.get(0)).unwrap();
        assert_eq!(v as usize, MIGRATIONS.len());
        // every added column should now be selectable
        conn.execute_batch("SELECT width_class, spacing_personality, optical_role FROM fonts;").unwrap();
    }

    #[test]
    fn migrations_are_idempotent_on_existing_db() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(CREATE_TABLE).unwrap();
        run_migrations(&conn);
        run_migrations(&conn); // second run must be a no-op, not a panic
        let v: i64 = conn.query_row("PRAGMA user_version;", [], |r| r.get(0)).unwrap();
        assert_eq!(v as usize, MIGRATIONS.len());
    }

    #[test]
    fn legacy_db_with_columns_but_version_zero_converges() {
        // Simulate an installed DB: columns already added by the OLD ad-hoc
        // ALTERs, but user_version still 0.
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(CREATE_TABLE).unwrap();
        for stmt in MIGRATIONS { conn.execute_batch(stmt).unwrap(); } // pre-add columns
        // user_version is still 0 here.
        run_migrations(&conn); // must tolerate the duplicate-column errors and stamp version
        let v: i64 = conn.query_row("PRAGMA user_version;", [], |r| r.get(0)).unwrap();
        assert_eq!(v as usize, MIGRATIONS.len());
    }
}
```

The third test is the important one — it proves a real upgraded install (columns present, `user_version = 0`) converges without panicking.

### Step 5 — Update the plan index

Set plan 006 status to `DONE` in `plans/README.md`.

---

## Verification / done criteria

```
cd src-tauri && cargo build 2>&1 | tail -5
```
**Expected:** clean build.

```
cd src-tauri && cargo test --lib 2>&1 | tail -15
```
**Expected (if Step 4 done):** the three migration tests pass; any plan-001 tests still pass.

**Real-DB smoke test (manual, important — this touches startup init):** Before running, back up your dev DB so you can restore it:
```
cp "$HOME/Library/Application Support/<app-bundle-id>/fontdrop.db" /tmp/fontdrop.db.bak   # adjust path to the actual app data dir
```
Then run the app (`npm run tauri dev`) against your **existing** DB and confirm: the app launches, the font grid populates, and Pair mode still returns matches (proves the upgraded-in-place DB reads correctly and `user_version` got stamped). If anything looks wrong, restore from the backup.

```
# After launching once, confirm the version stamped:
sqlite3 "$HOME/Library/Application Support/<app-bundle-id>/fontdrop.db" "PRAGMA user_version;"
```
**Expected:** prints `9` (the migration count at time of writing — equals `MIGRATIONS.len()`).

---

## Test plan

The three `#[cfg(test)]` tests in Step 4 cover: fresh DB, idempotent re-run, and the legacy-upgrade path. The real-DB smoke test covers the one thing unit tests can't — that an actual installed database upgrades cleanly. Do not skip the smoke test; this is the higher-risk plan in the set precisely because it runs at every startup against real user data.

---

## Maintenance note

- **`MIGRATIONS` is append-only.** Future schema changes add a new `&str` at the end — never edit or reorder existing entries, or installed DBs will mis-apply. Document this where the const is defined (the doc comment above does).
- This is the mechanism plan 003's panic-hardening assumes. With both in place: schema drift is prevented at the source (006) *and* survived gracefully if it ever happens anyway (003).
- If migrations ever need to do data backfills (not just `ADD COLUMN`), the same runner works — each entry is arbitrary SQL — but a failed data migration should likely **not** be "duplicate column"-tolerated; consider a richer migration type at that point.

---

## Escape hatches — STOP and report instead of improvising if:

- `open_db` or the `ALTER` block has been refactored away from the excerpt — report the new shape.
- The real-DB smoke test shows the app failing to read fonts after the change — restore the backup and report; do not push forward.
- You discover `PRAGMA user_version` is already being used for something else in the codebase (grep `user_version` first) — reconcile before proceeding.
