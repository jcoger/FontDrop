# 005 — Debounce color extraction so the cluster slider doesn't re-run k-means per tick

**Status:** DONE
**Effort:** S
**Risk of the change:** Low (localized to one effect; behavior-preserving except timing)
**Depends on:** none (independent, frontend-only)
**Written against commit:** `abf6b72`

---

## Why this matters

In the Color Explorer's Extract method, the extraction effect re-runs the **entire** synchronous pipeline — canvas readback + per-pixel oklch conversion + 20 iterations of k-means — every time `exClusterCount` changes:

`src/components/ColorExplorer/useColorExplorerState.ts:125`:
```rust
  useEffect(() => {
    if (!exImage) { setExRawClusters([]); return; }
    const clusters = extractFromImage(exImage, exClusterCount);   // ~100ms, synchronous, blocks the main thread
    setExRawClusters(clusters);
    lsSet(LS_KEYS.extract.cachedClusters, clusters);
    if (exThumbnail) lsSet(LS_KEYS.extract.cachedThumb, exThumbnail);
  }, [exImage, exClusterCount]);
```

`extractFromImage` (`src/components/ColorExplorer/methods/extractColors.ts:117`) is fully synchronous. The work is bounded (the canvas is hardcoded to 200×200 ≈ 40k pixels), so a single run is ~100–150ms — but the **cluster-count control is a slider/stepper**, so dragging it fires `exClusterCount` updates rapidly, and each one blocks the UI thread for a full extraction. Result: visible jank while adjusting cluster count, and a `localStorage` write per tick.

The fix: debounce the **cluster-count → extraction** path so extraction runs once after the user settles, while keeping the immediate re-extraction when a **new image** is loaded (that should feel instant).

---

## Current state

- `exImage` and `exClusterCount` are state in `useColorExplorerState.ts`. The single effect above keys on both.
- `extractFromImage(img, k)` is pure and synchronous; not the thing to change.
- There is a separate one-time "session restore" effect right below (guarded by `exInitialized` ref) — **do not touch it.**

---

## The fix (chosen approach)

Split the effect's two triggers:
- **Image change** → extract immediately (load should feel instant).
- **Cluster-count change** → extract after a short debounce (e.g. 200ms) so dragging the slider only triggers one extraction when it settles.

Implement with a debounced value derived from `exClusterCount`, or a `setTimeout` cleanup inside the effect. The `setTimeout`-with-cleanup form is the smallest change and needs no new hook.

---

## Scope

**In scope — modify ONLY:**
- `src/components/ColorExplorer/useColorExplorerState.ts` — the extraction effect (the one at ~line 125). Optionally add a tiny local debounce helper in the same file.
- `plans/README.md` — set plan 005 status to `DONE`.

**Out of scope:**
- `extractColors.ts` (the algorithm) — unchanged.
- The session-restore effect (`exInitialized` ref) — unchanged.
- Any UI/slider component — the debounce lives in the state hook, so the control stays fully responsive (the *number* updates instantly; only the *extraction* is debounced).

---

## Implementation steps

### Step 1 — Replace the single effect with image-immediate / count-debounced logic

Change the effect at `src/components/ColorExplorer/useColorExplorerState.ts:125` to:

```ts
  // Run extraction + persist cache.
  // New image -> extract immediately. Cluster-count change -> debounce so
  // dragging the slider doesn't re-run k-means (a ~100ms blocking pass) per tick.
  const exFirstRunRef = useRef(true);
  useEffect(() => {
    if (!exImage) { setExRawClusters([]); return; }

    const run = () => {
      const clusters = extractFromImage(exImage, exClusterCount);
      setExRawClusters(clusters);
      lsSet(LS_KEYS.extract.cachedClusters, clusters);
      if (exThumbnail) lsSet(LS_KEYS.extract.cachedThumb, exThumbnail);
    };

    // First run after an image loads should feel instant; subsequent
    // cluster-count changes are debounced.
    if (exFirstRunRef.current) {
      exFirstRunRef.current = false;
      run();
      return;
    }

    const t = setTimeout(run, 200);
    return () => clearTimeout(t);
  }, [exImage, exClusterCount, exThumbnail]);
```

> Two details to get right:
> 1. `exFirstRunRef` must reset to `true` whenever a **new** image is loaded, so the new image extracts immediately. The simplest correct approach: reset it in whatever handler sets `exImage` (search the file for `setExImage(` — there should be an image-load handler like `handleExImageLoad`). Set `exFirstRunRef.current = true` there, right before/after `setExImage(...)`. If you cannot cleanly reset it there, fall back to keying the "immediate vs debounced" decision on whether `exImage` *identity* changed this run versus only `exClusterCount` — but the ref-reset-in-handler approach is preferred and simpler.
> 2. Adding `exThumbnail` to the dep array (it was read but not listed before) keeps the cache write correct. Confirm `exThumbnail` is stable enough not to cause surprise re-runs; if it changes on every render, do **not** add it — instead read it via a ref. Check how `exThumbnail` is set before deciding.

### Step 2 — Confirm `useRef` is imported

`useColorExplorerState.ts` already uses `useRef` (for `exInitialized`), so no new import is needed. Verify.

### Step 3 — Manual behavior check

Run the app (`npm run tauri dev`), open Color Explorer → Extract:
- Load an image → clusters appear **immediately** (no 200ms lag).
- Drag the cluster-count slider across several values quickly → the UI stays responsive and extraction runs **once** when you stop, not on every intermediate value.

### Step 4 — Update the plan index

Set plan 005 status to `DONE` in `plans/README.md`.

---

## Verification / done criteria

```
npx tsc --noEmit && echo TSC_OK
```
**Expected:** `TSC_OK`.

Behavioral (manual, Step 3): new-image extraction is immediate; cluster-slider dragging no longer janks and fires a single extraction on settle. There is no automated test harness for the color subsystem (see plan 001 scope — it covers Rust only), so this is verified by inspection + the manual check.

---

## Test plan

No unit-test harness exists for the frontend. Verification is the manual check in Step 3 plus `tsc`. If a frontend test runner is added later (a candidate is noted in plan 007's tooling item), a debounce test would assert `extractFromImage` is called once across rapid `exClusterCount` updates — note this as a follow-up, don't build the harness here.

---

## Maintenance note

- If `extractFromImage` is ever moved off the main thread (a Web Worker), this debounce still helps (fewer worker round-trips) — keep it.
- The 200ms constant is a feel value; if cluster changes should feel snappier, lower it, but don't drop below ~120ms or you reintroduce per-tick extraction during a drag.

---

## Escape hatches — STOP and report instead of improvising if:

- The effect at line ~125 has been refactored and no longer matches the excerpt — report the new shape rather than guessing where to add the debounce.
- `exThumbnail` turns out to change on every render (would make the new dep array thrash) — use a ref for it and note the deviation.
- There is no clean place to reset `exFirstRunRef` on image load (no discrete `setExImage` handler) — report it; do not scatter the reset across multiple call sites.
