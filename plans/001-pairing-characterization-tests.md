# 001 — Characterization tests for the pairing & classifier engines

**Status:** DONE
**Effort:** M
**Risk of the change:** Low (adds tests only; touches no production behavior)
**Written against commit:** `abf6b72` (pairing feature is uncommitted working-tree changes on top of this commit)

---

## Why this matters

The font-pairing feature is built on two large, pure, deterministic Rust functions:

- `score_pair(primary, candidate) -> Option<PairScore>` in `src-tauri/src/pairing.rs` — ~300 lines encoding dozens of additive scoring rules.
- `classify_font(path, family) -> ClassificationResult` in `src-tauri/src/classifier.rs` — glyph-geometry skeleton classification.

The design doc `docs/pairing-score.md` specifies the scoring rules with **exact point values and concrete worked examples** (e.g. "Futura + Helvetica (geometric linear sans + geometric linear sans) → demoted −25"). Despite this precision, **there are zero automated tests in the repository.** Any future change to scoring — a tweaked weight, a new signal — can silently change which fonts the app recommends, with no safety net.

This plan establishes the **verification baseline** for the project (a `cargo test` target that currently does not exist) and writes **characterization tests**: tests that pin down the engine's *current* behavior so future refactors are provably behavior-preserving. It deliberately does **not** try to assert "correct" typography — only "this input produces this score today."

This plan must land **before** plans 002 and 003, which change engine behavior.

---

## Current state

- The Rust crate is at `src-tauri/`. Its lib is named `fontdrop_lib` with `crate-type = ["staticlib", "cdylib", "rlib"]` (see `src-tauri/Cargo.toml:14`). The `rlib` type means `cargo test` works.
- Modules are declared private in `src-tauri/src/lib.rs`:
  ```rust
  mod db;
  mod classifier;
  mod google_fonts;
  mod metrics;
  mod pairing;
  ```
- **There is currently no `cargo test` output** — running it compiles the crate and reports `0 tests`.
- The key scoring function and its input struct (abridged from `src-tauri/src/pairing.rs`):
  ```rust
  struct FontData {
      font_id: String,
      font_family: String,
      skeleton: String,            // "dynamic" | "rational" | "geometric" | "unknown"
      flesh_contrast: String,      // "linear" | "contrasting"
      flesh_serif: i32,            // 1 = serif, 0 = sans
      weight: u16,
      x_height_ratio: Option<f64>,
      cap_height_ratio: Option<f64>,
      ascender_descender_ratio: Option<f64>,
      foundry: Option<String>,
      designer: Option<String>,
      file_name: String,
      optical_role: Option<String>,        // "display" | "text" | "caption" | "mono" | "general"
      superfamily_group: Option<String>,
      superfamily_role: Option<String>,
      weight_range_min: Option<i32>,
      weight_range_max: Option<i32>,
      spacing_personality: Option<String>, // "tight" | "normal" | "open"
      width_class: Option<String>,         // "condensed" | "normal" | "expanded"
  }

  fn score_pair(primary: &FontData, candidate: &FontData) -> Option<PairScore> { ... }
  ```
  `PairScore` has public fields `font_id: String`, `score: u8`, `pair_type: String`, `reason: String`.
- `FontData` is a **private** struct with **private** fields. `score_pair` is `pub(crate)`-visible only via being in the module (it's `fn`, i.e. private to the module). Therefore tests must live **inside `pairing.rs`** as an inline `#[cfg(test)] mod tests` block — they cannot be in a separate `tests/` integration-test file (those only see the public API, and `FontData`/`score_pair` are not public).

`classifier::classify_font` IS `pub` and takes a real file path — see "Classifier tests" below for how to handle that.

---

## Scope

**In scope — create/modify ONLY these:**
- `src-tauri/src/pairing.rs` — append an inline `#[cfg(test)] mod tests { ... }` block at the end of the file.
- `src-tauri/src/classifier.rs` — append an inline `#[cfg(test)] mod tests { ... }` block at the end of the file.
- `plans/README.md` — update the status table row for plan 001 to `DONE` when finished.

**Out of scope — do NOT touch:**
- Any production function body. This plan adds tests only. If a test reveals what looks like a bug, **do not fix it here** — record it (see "Escape hatches") and pin the current (possibly buggy) behavior in the test with a comment. Fixes happen in plans 002/003.
- `metrics.rs`, `db.rs`, `google_fonts.rs`, `lib.rs`.
- Any frontend file.
- `Cargo.toml` — **no new dependencies are needed.** Do not add `rstest`, `proptest`, etc. Use the built-in `#[test]` harness only.

---

## Conventions to follow

This repo has no existing Rust tests to copy, so follow idiomatic standard-library test style:

- Inline module at the bottom of the file:
  ```rust
  #[cfg(test)]
  mod tests {
      use super::*;

      // a helper that builds a baseline FontData, overridden per-test
      fn font(id: &str) -> FontData { ... }

      #[test]
      fn same_skeleton_is_harmonious() { ... }
  }
  ```
- Use plain `assert_eq!` / `assert!`. Keep each test focused on one rule.
- Match the file's existing comment style (`// ── Section ──` banners) for the one banner introducing the test module.

---

## Implementation steps

### Step 1 — Add the pairing test module skeleton with a `FontData` builder

Append to the **end** of `src-tauri/src/pairing.rs`:

```rust
// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    /// A neutral baseline font. Every field is set so that, paired with a
    /// clone of itself that differs only where a test changes it, no modifier
    /// signals fire unexpectedly. Tests override individual fields.
    fn font(id: &str, family: &str) -> FontData {
        FontData {
            font_id: id.to_string(),
            font_family: family.to_string(),
            skeleton: "geometric".to_string(),
            flesh_contrast: "linear".to_string(),
            flesh_serif: 0,
            weight: 400,
            x_height_ratio: None,
            cap_height_ratio: None,
            ascender_descender_ratio: None,
            foundry: None,
            designer: None,
            file_name: "Test-Regular.ttf".to_string(),
            optical_role: Some("general".to_string()),
            superfamily_group: None,
            superfamily_role: None,
            weight_range_min: None,
            weight_range_max: None,
            spacing_personality: Some("normal".to_string()),
            width_class: Some("normal".to_string()),
        }
    }
}
```

> **Important:** the field list above must match `FontData` exactly. If `cargo test` fails to compile with "missing field" or "no field", open the current `struct FontData` definition near the top of `pairing.rs` and reconcile the builder with it — the struct is the source of truth, not this plan.

Verify it compiles:

```
cd src-tauri && cargo test --lib pairing 2>&1 | tail -20
```

**Expected:** compiles, runs `0 tests` in the pairing module (the empty module is valid). If you see `error[E0063]: missing field` or `error[E0560]: no field`, fix the builder to match the struct, then re-run.

### Step 2 — Pin the base-score / pair_type matrix

These are the foundational branches from `docs/pairing-score.md` → "Base score: Font Matrix compatibility". Add these tests inside the `tests` module. **Run each assertion against the actual current output** — if a value below differs from what the code produces, trust the code and update the expected value (this is characterization, not specification). Use the worked values as your starting expectations:

```rust
    #[test]
    fn self_pair_is_skipped() {
        let a = font("x", "Alpha");
        assert!(score_pair(&a, &a).is_none());
    }

    #[test]
    fn same_family_is_skipped() {
        let mut a = font("a", "Alpha");
        let mut b = font("b", "Alpha"); // same family, different id
        a.skeleton = "geometric".into();
        b.skeleton = "rational".into();
        assert!(score_pair(&a, &b).is_none());
    }

    #[test]
    fn same_skeleton_different_flesh_is_harmonious() {
        let mut p = font("p", "Primary");
        let mut c = font("c", "Cand");
        // same skeleton, but make flesh differ so no same-flesh penalty
        p.flesh_serif = 0;
        c.flesh_serif = 1; // serif vs sans
        let s = score_pair(&p, &c).expect("should score");
        assert_eq!(s.pair_type, "harmonious");
    }

    #[test]
    fn different_skeleton_different_flesh_is_bold() {
        let mut p = font("p", "Primary");
        let mut c = font("c", "Cand");
        p.skeleton = "geometric".into();
        c.skeleton = "dynamic".into();
        p.flesh_serif = 0;
        c.flesh_serif = 1;
        let s = score_pair(&p, &c).expect("should score");
        assert_eq!(s.pair_type, "bold");
    }

    #[test]
    fn same_flesh_different_skeleton_is_conflict_with_zero_score() {
        let mut p = font("p", "Primary");
        let mut c = font("c", "Cand");
        p.skeleton = "geometric".into();
        c.skeleton = "dynamic".into();
        // identical flesh => conflict
        p.flesh_contrast = "linear".into();
        c.flesh_contrast = "linear".into();
        p.flesh_serif = 0;
        c.flesh_serif = 0;
        let s = score_pair(&p, &c).expect("conflict still returns a PairScore");
        assert_eq!(s.pair_type, "conflict");
        assert_eq!(s.score, 0);
    }

    #[test]
    fn one_unknown_is_uncertain() {
        let mut p = font("p", "Primary");
        let mut c = font("c", "Cand");
        p.skeleton = "unknown".into();
        c.skeleton = "geometric".into();
        let s = score_pair(&p, &c).expect("should score");
        assert_eq!(s.pair_type, "uncertain");
    }

    #[test]
    fn both_unknown_is_uncertain_and_lower_than_one_unknown() {
        let mut p = font("p", "Primary");
        let mut c = font("c", "Cand");
        p.skeleton = "unknown".into();
        c.skeleton = "unknown".into();
        let s = score_pair(&p, &c).expect("should score");
        assert_eq!(s.pair_type, "uncertain");
        // doc: both unknown base 30, one unknown base 40
        assert!(s.score <= 40);
    }
```

Run and **read the actual values**:

```
cd src-tauri && cargo test --lib pairing -- --nocapture 2>&1 | tail -30
```

If any `assert_eq!` fails, look at the printed actual value, confirm it's consistent with the code in `score_pair` (don't just blindly match — sanity-check it follows the documented rule), and update the expected value in the test. Add a `// characterized <DATE>` comment where the observed value differs from the doc's worked example, and note the discrepancy in the plan's escape-hatch report at the end.

### Step 3 — Pin the same-flesh penalty (the doc's headline example)

From `docs/pairing-score.md` → "Same-flesh penalty": same skeleton + same contrast + same serif/sans = **−25**, demoted. The worked example is "Futura + Helvetica → demoted". Pin the *score delta*, which is robust even if the absolute base shifts:

```rust
    #[test]
    fn same_skeleton_same_flesh_incurs_penalty_vs_differing_serif() {
        // both geometric, linear. Case A: same serif-ness (penalty). Case B: differ (no penalty).
        let p = font("p", "Primary");

        let mut same = font("c1", "Cand1");
        same.flesh_serif = p.flesh_serif; // identical flesh -> -25

        let mut diff = font("c2", "Cand2");
        diff.flesh_serif = 1 - p.flesh_serif; // serif vs sans -> no penalty

        let s_same = score_pair(&p, &same).expect("scores");
        let s_diff = score_pair(&p, &diff).expect("scores");

        // The same-flesh case must score strictly lower than the differing-flesh case.
        assert!(
            s_same.score < s_diff.score,
            "same-flesh {} should be < differing-flesh {}",
            s_same.score, s_diff.score
        );
    }
```

### Step 4 — Pin the superfamily override

From the doc → "Superfamily detection": confirmed superfamily match = `pair_type = "superfamily"`, `+20`, score floor **85**. A superfamily requires same `superfamily_group` and **different** `superfamily_role`:

```rust
    #[test]
    fn confirmed_superfamily_overrides_pair_type_and_floors_score() {
        let mut p = font("p", "Source Serif");
        let mut c = font("c", "Source Sans");
        p.superfamily_group = Some("Source".into());
        c.superfamily_group = Some("Source".into());
        p.superfamily_role = Some("serif".into());
        c.superfamily_role = Some("sans".into());
        let s = score_pair(&p, &c).expect("scores");
        assert_eq!(s.pair_type, "superfamily");
        assert!(s.score >= 85, "superfamily floor is 85, got {}", s.score);
    }

    #[test]
    fn same_superfamily_same_role_is_not_a_superfamily_pairing() {
        let mut p = font("p", "Source Sans");
        let mut c = font("c", "Source Sans Caption"); // different family name, same group+role
        p.superfamily_group = Some("Source".into());
        c.superfamily_group = Some("Source".into());
        p.superfamily_role = Some("sans".into());
        c.superfamily_role = Some("sans".into());
        let s = score_pair(&p, &c).expect("scores");
        assert_ne!(s.pair_type, "superfamily");
    }
```

### Step 5 — Pin a representative set of additive modifiers

Pick the modifiers that have the clearest, most testable rules. For each, build two candidates differing only in the field under test and assert the **direction of the score delta** (more robust than absolute values). Cover at minimum:

- **Optical role** (`docs` → "Optical role clarity"): `display`+`text` scores higher than `display`+`display`.
- **Spacing personality**: `normal`+`open` scores higher than `tight`+`tight`.
- **Width contrast**: `condensed`+`normal` scores higher than `condensed`+`condensed`.
- **x-height proximity**: closer x-height (set both `x_height_ratio`) scores ≥ far x-height.

Example for optical role:

```rust
    #[test]
    fn display_plus_text_beats_display_plus_display() {
        let mut p = font("p", "Primary");
        p.optical_role = Some("display".into());
        p.flesh_serif = 0;

        let mut text = font("t", "TextCand");
        text.optical_role = Some("text".into());
        text.flesh_serif = 1; // keep flesh differing so base is stable

        let mut disp = font("d", "DisplayCand");
        disp.optical_role = Some("display".into());
        disp.flesh_serif = 1;

        let s_text = score_pair(&p, &text).expect("scores");
        let s_disp = score_pair(&p, &disp).expect("scores");
        assert!(s_text.score > s_disp.score,
            "display+text {} should beat display+display {}", s_text.score, s_disp.score);
    }
```

Write the analogous three tests for spacing, width, and x-height. Keep flesh differing (`flesh_serif` p=0 / candidates=1) in all of them so you isolate the signal under test from the same-flesh penalty.

### Step 6 — Classifier tests (name-fallback path only, no fixture files)

`classify_font(path, family)` reads a file. To avoid committing binary font fixtures, test the **non-parseable-format fallback path**, which is deterministic and file-content-independent: when the extension is not `ttf`/`otf`, it classifies by name keyword only (see `classifier.rs` ~line 534 and `name_keyword_skeleton`).

Append to the end of `src-tauri/src/classifier.rs`:

```rust
// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    // A ".woff2" path is treated as non-parseable, so classification falls back
    // to name keywords without ever reading the file (the path need not exist).
    fn classify_by_name(family: &str) -> ClassificationResult {
        classify_font(Path::new("/nonexistent/font.woff2"), family)
    }

    #[test]
    fn name_keyword_dynamic() {
        assert_eq!(classify_by_name("Garamond").skeleton, "dynamic");
    }

    #[test]
    fn name_keyword_rational() {
        assert_eq!(classify_by_name("Helvetica Neue").skeleton, "rational");
    }

    #[test]
    fn name_keyword_geometric() {
        assert_eq!(classify_by_name("Futura").skeleton, "geometric");
    }

    #[test]
    fn unknown_name_is_unknown_skeleton() {
        assert_eq!(classify_by_name("Zzqwx Plain").skeleton, "unknown");
    }
}
```

> Confirm against `name_keyword_skeleton` in `classifier.rs` that "Garamond"→dynamic, "Helvetica"→rational, "Futura"→geometric are the actual keyword mappings (they are at the time of writing). If the keyword lists have changed, pick three families that ARE in the current lists.

### Step 7 — Update the plan index

In `plans/README.md`, change the plan 001 status cell from `TODO` to `DONE`.

---

## Verification / done criteria

Run from the repo root:

```
cd src-tauri && cargo test --lib 2>&1 | tail -20
```

**Expected output:** a line of the form `test result: ok. N passed; 0 failed; ...` where **N ≥ 16** (7 base-matrix + 1 penalty + 2 superfamily + 4 modifier + 4 classifier ≈ 18). Zero failures.

Also confirm tests are gated and don't affect the production build:

```
cd src-tauri && cargo build 2>&1 | tail -5
```

**Expected:** builds clean (tests are `#[cfg(test)]`, excluded from the normal build).

Frontend is untouched, but confirm nothing regressed:

```
npx tsc --noEmit && echo TSC_OK
```

**Expected:** `TSC_OK`.

---

## Test plan

The deliverable *is* tests. The "test of the tests" is: they must pass on the current unmodified engine, and they must be written so that a behavior change flips them. Spot-check this for one test before finishing: temporarily change one expected value to a wrong number, run `cargo test`, confirm it fails, then restore it. (Do not leave the broken value in.)

---

## Maintenance note

- These are **characterization** tests, not specifications. When plans 002/003 deliberately change scoring, the relevant tests here are *expected* to fail — the executor of those plans updates the pinned values as part of the change and notes the delta. That is the safety net working as designed, not a regression.
- If `FontData` gains a field, the `font()` builder in the test module must be updated or `cargo test` won't compile — that's a useful tripwire.
- Keep tests asserting **score deltas / orderings** rather than absolute magic numbers wherever the rule is about relative preference; reserve absolute-value asserts for the base-matrix and the superfamily floor, which are genuine contract points.

---

## Escape hatches — STOP and report instead of improvising if:

- `score_pair` or `FontData` is **not** in `pairing.rs`, or `classify_font` is not `pub` in `classifier.rs` — the file structure has diverged from this plan's assumptions; report what you found.
- Any base-matrix test (Step 2) reveals a `pair_type` or score that **contradicts the documented rule in a way you can't explain** from reading `score_pair` — that's a candidate bug, not just a stale doc value. Pin the current behavior with a `// FIXME(characterized): contradicts docs/pairing-score.md` comment and list every such case in your final report so it can be triaged. Do not fix it here.
- `cargo test` fails to compile for a reason other than a fixable field mismatch in the `font()` builder — report the error.
