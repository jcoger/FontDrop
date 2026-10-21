# 004 — Remove the dead `useFonts` hook and `get_system_fonts` command (collapse to one font source)

**Status:** DONE
**Effort:** S–M
**Risk of the change:** Low (removes unreferenced code; type relocation is mechanical)
**Depends on:** none (independent; do after the pairing feature is committed so the diff is clean)
**Written against commit:** `abf6b72` (pairing feature is uncommitted working-tree changes on top of this commit)

---

## Why this matters

There are two parallel font-loading paths in the app:

- `useFonts()` → invokes the **`get_system_fonts`** Tauri command → in-memory scan, returns `FontInfo[]`.
- `useFontDB()` → invokes **`get_font_db`** → SQLite-backed rows (`FontDBRow[]`), the source the whole app actually uses.

**`useFonts()` is never called.** Verified by grep: every reference to the `useFonts` module is a **type-only import** of `FontInfo` / `Classification` (~13 files); the `useFonts()` function and the `get_system_fonts` command behind it are dead. They survive only because the shared `FontInfo` TypeScript type happens to live in that file.

The cost is real: a new reader sees two font sources and can't tell which is authoritative; the Rust backend carries an entire unused scan path (`get_system_fonts` + its private `scan_dir` + the Rust `FontInfo` struct); and `App.tsx` imports the `FontInfo` *type* from a module whose *runtime* export is dead, which obscures the dead code.

This plan deletes the dead runtime code on both sides and relocates the still-needed shared types to a neutral home.

---

## Current state (verified)

**TypeScript — who imports from `src/hooks/useFonts.ts`:** all are `import type` of `FontInfo` (and in some cases `Classification`):

```
src/App.tsx
src/components/FontFamilyList.tsx
src/components/TypeExplorer.tsx
src/components/PairMode.tsx
src/components/QuickView.tsx
src/components/FontCard.tsx
src/components/FontGrid.tsx
src/components/ColorExplorer/index.tsx
src/components/ColorExplorer/components/ColorCard.tsx
src/components/ColorExplorer/components/BrandKitView.tsx
src/lib/fontFamilies.ts
src/lib/fontFace.ts
src/hooks/useExclusions.ts
```

`src/hooks/useFonts.ts` exports the `FontInfo` and `Classification` TS interfaces **and** the dead `useFonts()` function. `useFontDB.ts` already does `import type { FontInfo, Classification } from "./useFonts"` and `FontDBRow extends FontInfo`.

**Rust — `src-tauri/src/lib.rs`:**
- `pub struct Classification` (lib.rs:13) — **still used** by `db.rs` (`FontRow.classification: Classification`, and `parse_font_meta` returns it). KEEP.
- `pub struct FontInfo` (lib.rs:20) — used **only** by `scan_dir` + `get_system_fonts`. Remove.
- `fn scan_dir` (lib.rs:172) — used **only** by `get_system_fonts`. Remove.
- `fn get_system_fonts` (lib.rs:220) — registered in the `invoke_handler!` macro (lib.rs:260). Remove both the fn and the handler entry.
- `parse_family` / `parse_font_meta` / `default_meta` / `FontMeta` — used by `db.rs` too. KEEP.

---

## Scope

**In scope:**
- Create `src/types/font.ts` (or reuse an existing `src/types/` file — check first) holding the `FontInfo` and `Classification` TS interfaces.
- Update the ~13 `import type ... from ".../useFonts"` sites to import from the new location.
- Delete `src/hooks/useFonts.ts`.
- `src-tauri/src/lib.rs`: remove `struct FontInfo`, `fn scan_dir`, `fn get_system_fonts`, and the `get_system_fonts,` line in `invoke_handler!`.
- `plans/README.md` — set plan 004 status to `DONE`.

**Out of scope — do NOT touch:**
- `Classification` (Rust struct), `parse_family`, `parse_font_meta`, `FontMeta`, `default_meta` in `lib.rs` — all still used by `db.rs`.
- `useFontDB.ts` runtime logic (only its `import type` line for `FontInfo`/`Classification` changes).
- Any pairing file, any color file beyond the type-import line.

---

## Implementation steps

### Step 1 — Re-verify `useFonts()` is dead before deleting

```
cd /Users/jcoger/fontdrop
grep -rn "useFonts(" src/        # call sites — expect ZERO (only the definition line in useFonts.ts)
grep -rn "get_system_fonts" src/ # frontend invokes — expect ZERO
```

If either shows a real call site (not the definition, not a comment), **STOP and report** — the premise is wrong.

### Step 2 — Create the shared types module

Open `src/hooks/useFonts.ts` and copy the **exact** `FontInfo` and `Classification` interface definitions out of it. Create `src/types/font.ts` (if `src/types/` already has a fonts file, add them there instead and adjust paths):

```ts
// src/types/font.ts
// Shared font-shape types. The runtime font source is useFontDB (SQLite);
// FontDBRow extends FontInfo.

export interface Classification {
  category: string; // matches the Rust Classification.category values
  style: string;
  width: string;
}

export interface FontInfo {
  // ... copy the exact fields from the old useFonts.ts FontInfo ...
}
```

> Copy field-for-field from the current `useFonts.ts`. Do not redesign the types. If `Classification` has a stricter union type in the original (e.g. `category: "serif" | ...`), preserve it verbatim — `useFontDB.ts` casts to it.

### Step 3 — Repoint all type imports

For each file in the list under "Current state", change the import source from the `useFonts` path to the new `src/types/font` path (adjust relative depth per file). Examples:

- `src/App.tsx`: `import { type FontInfo } from "./hooks/useFonts";` → `import { type FontInfo } from "./types/font";`
- `src/hooks/useFontDB.ts`: `import type { FontInfo, Classification } from "./useFonts";` → `import type { FontInfo, Classification } from "../types/font";`
- `src/components/ColorExplorer/components/ColorCard.tsx`: `"../../../hooks/useFonts"` → `"../../../types/font"`

Do this for all ~13 sites. Use the grep from Step 1 of the audit list to find them all; re-grep after to confirm none remain:

```
grep -rn "hooks/useFonts\|./useFonts\b" src/   # expect ZERO after repointing
```

### Step 4 — Delete the dead hook

```
rm src/hooks/useFonts.ts
```

### Step 5 — Remove the dead Rust command and its helpers

In `src-tauri/src/lib.rs`:
1. Delete `pub struct FontInfo { ... }` (around lib.rs:19–27 — the **Rust** struct, not the TS one).
2. Delete `fn scan_dir(dir: &PathBuf, source: &str, results: &mut Vec<FontInfo>) { ... }` (around lib.rs:172–217).
3. Delete `#[tauri::command] fn get_system_fonts() -> Vec<FontInfo> { ... }` (around lib.rs:219–239).
4. In the `tauri::generate_handler![ ... ]` block, remove the `get_system_fonts,` line (lib.rs:260).
5. If `use ttf_parser::...` or other imports become unused after this, the compiler will warn — remove only the now-unused imports it flags. Do **not** remove imports still used by `parse_font_meta`.

### Step 6 — Update the plan index

Set plan 004 status to `DONE` in `plans/README.md`.

---

## Verification / done criteria

```
npx tsc --noEmit && echo TSC_OK
```
**Expected:** `TSC_OK` (all type imports resolve from the new location).

```
cd src-tauri && cargo build 2>&1 | tail -8
```
**Expected:** clean build with **no `unused` warnings** for `FontInfo`/`scan_dir`/`get_system_fonts` (they're gone). If the build warns that something you kept is now unused, investigate — you may have removed too much or too little.

```
cd /Users/jcoger/fontdrop
grep -rn "useFonts" src/        # expect ZERO
grep -rn "get_system_fonts" src/ src-tauri/   # expect ZERO
```

Run the app if feasible (`npm run tauri dev`) and confirm the font grid still loads — proves the surviving `useFontDB`/`get_font_db` path is untouched.

---

## Test plan

This is a deletion + type move; correctness is proven by `tsc --noEmit` (types resolve) and `cargo build` (no dangling refs). If plan 001 has landed, run `cargo test --lib` to confirm nothing in the test suite referenced the removed symbols (it shouldn't). No new tests needed.

---

## Maintenance note

After this, `useFontDB` / `get_font_db` is the **single** font source — say so in a one-line comment at the top of `useFontDB.ts` if there isn't one. The shared types now live in `src/types/font.ts`; new font-shaped types belong there, not in a hook file.

---

## Escape hatches — STOP and report instead of improvising if:

- Step 1 finds a real `useFonts()` call site or a frontend `get_system_fonts` invoke — the hook is not actually dead; report it.
- The Rust `Classification` struct turns out to be referenced only by the code you're deleting (it isn't, per `db.rs`, but verify) — if so, do **not** delete it; report the coupling.
- Removing `get_system_fonts` causes `cargo build` to flag a *used* function as unused, implying a deeper coupling than expected — report rather than chasing cascading deletions.
