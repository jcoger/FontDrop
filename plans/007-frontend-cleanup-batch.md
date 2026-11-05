# 007 — Frontend cleanup batch: dedupe filter memos, memoize hot paths, add lint/format

**Status:** DONE
**Effort:** S–M (three independent sub-tasks; can land together or separately)
**Risk of the change:** Low
**Depends on:** none (frontend-only; independent of all other plans)
**Written against commit:** `abf6b72`

---

## Why this matters

Three small, independent quality items batched into one plan. None is urgent on its own; together they remove duplication, two cheap re-render costs, and the absence of any automated style/lint gate. Each sub-task is self-contained — an executor may do all three or any subset, marking partial progress in the index.

---

## Sub-task A — Consolidate the duplicate `gridFonts` / `explorerFonts` filter memos

### Current state
`src/App.tsx:413` and `src/App.tsx:425` define two memos with **byte-for-byte identical** filter chains:

```ts
  const gridFonts = useMemo(() => {
    let result = starred.showStarred
      ? searchedFonts.filter((f) => starred.starred.has(f.file_path))
      : searchedFonts;
    if (categoryFilter) result = result.filter((f) => f.classification.category === categoryFilter);
    if (styleFilters.has("italic")) result = result.filter((f) => f.classification.style === "italic");
    if (styleFilters.has("condensed")) result = result.filter((f) => f.classification.width === "condensed");
    if (styleFilters.has("extended")) result = result.filter((f) => f.classification.width === "extended");
    return result;
  }, [searchedFonts, starred.showStarred, starred.starred, categoryFilter, styleFilters]);

  const explorerFonts = useMemo(() => {
    // ...identical body...
  }, [searchedFonts, starred.showStarred, starred.starred, categoryFilter, styleFilters]);
```

They are consumed in different render branches (grid mode vs explorer mode) but compute the same thing. Any change to filtering must be made twice.

### Fix
Collapse to one memo and reference it in both places.

1. Replace the two memos with a single one:
   ```ts
   const filteredFonts = useMemo(() => {
     let result = starred.showStarred
       ? searchedFonts.filter((f) => starred.starred.has(f.file_path))
       : searchedFonts;
     if (categoryFilter) result = result.filter((f) => f.classification.category === categoryFilter);
     if (styleFilters.has("italic")) result = result.filter((f) => f.classification.style === "italic");
     if (styleFilters.has("condensed")) result = result.filter((f) => f.classification.width === "condensed");
     if (styleFilters.has("extended")) result = result.filter((f) => f.classification.width === "extended");
     return result;
   }, [searchedFonts, starred.showStarred, starred.starred, categoryFilter, styleFilters]);
   ```
2. Find every use of `gridFonts` and `explorerFonts` in `App.tsx` (grep them — there are several, e.g. counts in the top bar around lines 849–850, the `quickViewFonts` selection ~line 501, the render branches, the empty-state checks ~913, the FontGrid props ~958). Replace both identifiers with `filteredFonts`.

   > **Caution:** confirm grid and explorer truly use the *same* filtered set everywhere before collapsing. Re-read each `gridFonts`/`explorerFonts` use. If you find even one place where they legitimately differ, do **not** merge — instead extract a shared helper `applyGridFilters(searchedFonts, ...)` and call it in both memos, keeping two named outputs. Report which you chose.

### Verify
```
npx tsc --noEmit && echo TSC_OK
grep -n "gridFonts\|explorerFonts" src/App.tsx   # zero if fully merged, or only the helper if you kept two
```
Run the app; switch between grid and explorer modes with a category filter active — both show the same filtered set as before.

---

## Sub-task B — Memoize two hot paths

### B1 — `FontFamilyList` rebuilds its `rows` array every render
**Current state:** in `src/components/FontFamilyList.tsx`, the `rows` array (the flattened family/variant list react-window renders) is constructed inline in the component body, so it's rebuilt on every render and forces react-window to re-measure. Find the `const rows = ...` (or equivalent array build) that depends on the families list and the expanded-families set.

**Fix:** wrap it in `useMemo` keyed on its real inputs:
```ts
const rows = useMemo(() => {
  /* ...existing construction... */
}, [families, expandedFamilies /* + any other inputs the body reads */]);
```
> Read the existing construction first and list **every** value it closes over in the dep array — missing one causes a stale list (a correctness bug worse than the perf cost). If the body reads many values, that's a signal to keep the logic but be careful with deps; do not guess.

### B2 — `QuickView` recomputes `findIndex` every render
**Current state:** `src/components/QuickView.tsx:44`:
```ts
const currentIndex = allFonts.findIndex((f) => f.file_path === font.file_path);
```
runs an O(n) scan on every render.

**Fix:**
```ts
const currentIndex = useMemo(
  () => (font ? allFonts.findIndex((f) => f.file_path === font.file_path) : -1),
  [allFonts, font],
);
```
Confirm `useMemo` is imported in the file (add to the React import if not).

### Verify
```
npx tsc --noEmit && echo TSC_OK
```
Run the app; expand/collapse families and open QuickView + arrow through fonts — behavior identical, no regressions. (These are perf-only; correctness is unchanged as long as the dep arrays are complete.)

---

## Sub-task C — Add ESLint + Prettier and lint/format scripts

### Current state
No `.eslintrc*`, no `.prettierrc*`, no `lint`/`format` scripts in `package.json`. CI exists (`.github/workflows/release.yml`) but only builds releases — nothing guards correctness or style on change. The project already typechecks clean (`tsc --noEmit` passes).

### Fix (keep it minimal and non-disruptive)
1. Add dev dependencies (the executor MAY run the install since this is the one plan whose job is tooling setup — but if the environment forbids installs, instead **list** the exact deps to add and stop, reporting that install is needed):
   - `eslint`, `@typescript-eslint/parser`, `@typescript-eslint/eslint-plugin`, `eslint-plugin-react-hooks`, `eslint-plugin-react-refresh`, `prettier`.
2. Create a minimal flat config `eslint.config.js` (ESLint 9 flat-config style; match whatever ESLint major the install resolves) covering `src/**/*.{ts,tsx}` with the TypeScript + react-hooks recommended rule sets. **Set `react-hooks/exhaustive-deps` to `warn`, not `error`** — the codebase has intentional `// eslint-disable-next-line react-hooks/exhaustive-deps` sites (e.g. `App.tsx:303`, `:357`) and several effects that deliberately omit deps; a hard error would fail the whole project on day one.
3. Create `.prettierrc` with conservative defaults (e.g. `{ "semi": true, "singleQuote": false }` — match the existing code style; the codebase uses double quotes and semicolons).
4. Add scripts to `package.json`:
   ```json
   "lint": "eslint src",
   "format": "prettier --write \"src/**/*.{ts,tsx,css}\"",
   "format:check": "prettier --check \"src/**/*.{ts,tsx,css}\""
   ```
5. **Do not auto-run `prettier --write` across the whole tree in this plan** — a mass reformat would bury the real diffs of plans 001–006 and this one. Add the tooling and scripts only; leave a one-line note in the plan output that a formatting pass can be run separately once other plans land.

### Verify
```
npm run lint 2>&1 | tail -30
```
**Expected:** runs and reports (warnings are fine; the goal is that `lint` *works*, not that the codebase is warning-free on day one). If `lint` reports a flood of *errors* (not warnings), the config is too strict — dial rules down to `warn` until errors reflect only genuine breakage.
```
npx tsc --noEmit && echo TSC_OK
```
**Expected:** `TSC_OK` (config files don't affect the type build).

> Optionally, wire `npm run lint` and `npx tsc --noEmit` into a CI check in `.github/workflows/` as a follow-up — note it, but a new CI job is out of scope for this plan unless trivially added alongside the existing workflow.

---

## Scope summary

**In scope:** `src/App.tsx` (A), `src/components/FontFamilyList.tsx` + `src/components/QuickView.tsx` (B), `package.json` + `eslint.config.js` + `.prettierrc` (C), and `plans/README.md` status.
**Out of scope:** any behavior change beyond memoization/dedup; a repo-wide prettier reformat; new CI jobs (beyond an optional trivial lint step); the CSP/security item (#15) and other deferred notes — those stay in the index's deferred list.

---

## Done criteria (whole plan)

```
npx tsc --noEmit && echo TSC_OK     # A + B
npm run lint 2>&1 | tail -5         # C: command exists and runs
grep -n "gridFonts\|explorerFonts" src/App.tsx   # A: merged (or only the shared helper)
```
Plus the manual app checks in A and B. Update `plans/README.md`: mark 007 `DONE`, or `PARTIAL (A,B done; C pending install)` if the environment blocked the dependency install.

---

## Maintenance note

- Sub-task A: the single `filteredFonts` memo is now the one place to change grid/explorer filtering. If grid and explorer ever need to diverge, reintroduce a second memo deliberately rather than copy-pasting.
- Sub-task C: `exhaustive-deps` is intentionally `warn`. Several effects in this codebase omit deps on purpose; treat new warnings as prompts to think, not mandates to "fix" by adding deps (which can introduce re-subscribe bugs — see the analysis behind plan-set finding #1).

---

## Escape hatches — STOP and report instead of improvising if:

- In Sub-task A, `gridFonts` and `explorerFonts` turn out **not** to be identical at some use site — keep them separate (shared helper) and report.
- In Sub-task B, you cannot enumerate the full dependency set of the `rows` construction with confidence — leave it unmemoized and report, rather than shipping an incomplete dep array (a stale list is a real bug).
- In Sub-task C, the environment forbids installing dev dependencies — add the config files + scripts, list the exact packages to install, and report `PARTIAL`; do not fake the tooling.
