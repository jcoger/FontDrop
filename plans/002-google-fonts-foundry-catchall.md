# 002 — Fix spurious `shared_foundry` bonus from the "Google Fonts" catch-all

**Status:** DONE
**Effort:** S
**Risk of the change:** Low (small, localized; covered by plan 001 tests once they exist)
**Depends on:** 001 (recommended — so the behavior change is caught and re-pinned by tests)
**Written against commit:** `abf6b72` (pairing feature is uncommitted working-tree changes on top of this commit)

---

## Why this matters

When Google Fonts enrichment runs with an API key, every installed font that matches the Google catalog but is **not** in the curated `known_designer` table is assigned a **catch-all placeholder foundry**:

`src-tauri/src/google_fonts.rs` (~line 286):
```rust
// Get designer from our curated list (API doesn't expose it)
let (foundry, designer) = known_designer(&entry.family)
    .unwrap_or(("Google Fonts", ""));   // <-- catch-all

conn.execute(
    "UPDATE fonts SET google_category = ?1, foundry = ?2, designer = ?3, ...",
    params![google_cat, foundry, designer, now, font_id],
)
```

So a large fraction of a user's library ends up with `foundry = "Google Fonts"`. The pairing scorer then treats that placeholder as a *meaningful shared foundry*:

`src-tauri/src/pairing.rs` (~line 230):
```rust
let shared_foundry = match (&primary.foundry, &candidate.foundry) {
    (Some(a), Some(b)) if !a.is_empty() && a == b => true,
    _ => false,
};
// ...
if (shared_foundry || shared_designer) && !is_superfamily && !superfamily_hint {
    base += 4;
    let who = if shared_designer {
        candidate.designer.as_deref().unwrap_or("same designer")
    } else {
        candidate.foundry.as_deref().unwrap_or("same foundry")
    };
    parts.push(format!("shared designer ({})", who));   // <-- mislabeled too
}
```

**Two problems:**
1. **Spurious +4** on nearly every pair of Google-sourced fonts, diluting the foundry signal that's supposed to indicate a *real* shared origin (e.g. both Adobe, both ParaType).
2. **Mislabeled reason** — the card reads `shared designer (Google Fonts)` even though "Google Fonts" is a foundry placeholder, not a designer, and not a real shared-origin signal.

The intent of the `shared_foundry` rule (per `docs/pairing-score.md` → "Shared foundry or designer": "+4 … subtle proportional decisions that make them work well together") is clearly about *specific* foundries, not the generic Google Fonts bucket.

---

## Current state

- `known_designer(family)` in `google_fonts.rs` returns `Option<(&str, &str)>` of `(foundry, designer)` for a curated list (Adobe, IBM, ParaType, …) and `None` otherwise.
- The catch-all `.unwrap_or(("Google Fonts", ""))` is the **only** place the literal `"Google Fonts"` foundry is written. (Verify with the grep in Step 1.)
- The scorer's `shared_foundry` check does a plain string-equality on `foundry`, with no exclusion for the placeholder.

---

## The fix (chosen approach)

**Exclude the `"Google Fonts"` placeholder from the `shared_foundry` signal in the scorer**, and fix the reason label. This is preferred over removing the placeholder write in `google_fonts.rs`, because the `foundry IS NOT NULL` value is *also* used elsewhere (e.g. `refresh_google_fonts` counts `WHERE foundry IS NOT NULL` as "enriched", and the UI shows the foundry string). Keeping the placeholder as a display/enrichment marker but treating it as "no meaningful shared foundry" for scoring is the smallest correct change.

Define the placeholder as a named constant so the two modules agree on the sentinel.

---

## Scope

**In scope — modify ONLY:**
- `src-tauri/src/pairing.rs` — exclude the placeholder in `shared_foundry`; fix the reason wording.
- `src-tauri/src/pairing.rs` test module (added in plan 001) — add a test for the new behavior.
- `plans/README.md` — set plan 002 status to `DONE`.

**Out of scope — do NOT touch:**
- `google_fonts.rs` — leave the `("Google Fonts", "")` catch-all write as-is (it remains a valid "enriched but generic" marker).
- The `superfamily_hint` / `shared_designer` logic — only `shared_foundry` is affected.
- Any frontend file, any other module.

---

## Implementation steps

### Step 1 — Confirm the placeholder string and its single writer

```
cd src-tauri && grep -rn '"Google Fonts"' src/
```

**Expected:** exactly one hit, in `google_fonts.rs`, the `.unwrap_or(("Google Fonts", ""))`. If there is more than one writer, note it but proceed — the scorer fix still holds.

### Step 2 — Add a shared placeholder constant in `pairing.rs`

Near the top of `src-tauri/src/pairing.rs`, after the `use` statements, add:

```rust
/// Placeholder foundry assigned by Google Fonts enrichment when no specific
/// foundry/designer is known (see google_fonts.rs). It marks a font as
/// "enriched" but carries no real shared-origin signal, so the pairing scorer
/// must NOT treat two fonts sharing this value as a meaningful shared foundry.
const GENERIC_FOUNDRY: &str = "Google Fonts";
```

### Step 3 — Exclude the placeholder in `shared_foundry`

Find this block (~line 230) in `score_pair`:

```rust
    let shared_foundry = match (&primary.foundry, &candidate.foundry) {
        (Some(a), Some(b)) if !a.is_empty() && a == b => true,
        _ => false,
    };
```

Replace the guard so the generic placeholder does not count:

```rust
    let shared_foundry = match (&primary.foundry, &candidate.foundry) {
        (Some(a), Some(b)) if !a.is_empty() && a == b && a != GENERIC_FOUNDRY => true,
        _ => false,
    };
```

### Step 4 — Fix the mislabeled reason

A few lines below (~line 238–246), the reason currently always says "shared designer …". Make the label honest about which signal fired:

Current:
```rust
    if (shared_foundry || shared_designer) && !is_superfamily && !superfamily_hint {
        base += 4;
        let who = if shared_designer {
            candidate.designer.as_deref().unwrap_or("same designer")
        } else {
            candidate.foundry.as_deref().unwrap_or("same foundry")
        };
        parts.push(format!("shared designer ({})", who));
    }
```

Replace the `parts.push` line so foundry matches read "shared foundry (…)" and designer matches read "shared designer (…)":

```rust
    if (shared_foundry || shared_designer) && !is_superfamily && !superfamily_hint {
        base += 4;
        if shared_designer {
            let who = candidate.designer.as_deref().unwrap_or("same designer");
            parts.push(format!("shared designer ({})", who));
        } else {
            let who = candidate.foundry.as_deref().unwrap_or("same foundry");
            parts.push(format!("shared foundry ({})", who));
        }
    }
```

### Step 5 — Add a characterization test for the new behavior

In the `#[cfg(test)] mod tests` block at the bottom of `pairing.rs` (created in plan 001), add:

```rust
    #[test]
    fn generic_google_foundry_does_not_grant_shared_foundry_bonus() {
        // Two fonts both tagged with the generic placeholder foundry must NOT
        // get the +4 shared-foundry bonus.
        let mut p = font("p", "Primary");
        let mut generic = font("g", "GenericCand");
        let mut real = font("r", "RealCand");

        // keep flesh differing so base score is identical across both candidates
        p.flesh_serif = 0;
        generic.flesh_serif = 1;
        real.flesh_serif = 1;

        p.foundry = Some("Google Fonts".into());
        generic.foundry = Some("Google Fonts".into()); // placeholder -> no bonus
        real.foundry = Some("Adobe".into());           // but primary is "Google Fonts" so this won't match either

        let s_generic = score_pair(&p, &generic).expect("scores");

        // Now test a real shared foundry: both Adobe.
        let mut p2 = font("p2", "Primary2");
        let mut real2 = font("r2", "RealCand2");
        p2.flesh_serif = 0;
        real2.flesh_serif = 1;
        p2.foundry = Some("Adobe".into());
        real2.foundry = Some("Adobe".into());          // real shared foundry -> +4
        let s_real = score_pair(&p2, &real2).expect("scores");

        // The generic-foundry pair must not include the shared-foundry reason.
        assert!(!s_generic.reason.contains("shared foundry"),
            "generic placeholder should not produce a shared-foundry reason: {}", s_generic.reason);
        // The real shared-foundry pair should score the +4 and label it correctly.
        assert!(s_real.reason.contains("shared foundry (Adobe)"),
            "real shared foundry should be labeled: {}", s_real.reason);
    }
```

### Step 6 — Re-pin any plan-001 test that changes

If plan 001 wrote any test whose pinned score depended on a "Google Fonts" foundry match (it should not have — 001's baseline `font()` builder sets `foundry: None`), re-run the full suite and update any failing pinned values, noting the delta. With `foundry: None` in the builder, no 001 test should be affected.

### Step 7 — Update the plan index

Set plan 002 status to `DONE` in `plans/README.md`.

---

## Verification / done criteria

```
cd src-tauri && cargo test --lib 2>&1 | tail -20
```
**Expected:** `test result: ok.` with the new `generic_google_foundry_does_not_grant_shared_foundry_bonus` test passing and all plan-001 tests still passing (zero failures).

```
cd src-tauri && cargo build 2>&1 | tail -5
```
**Expected:** clean build, no `unused constant` warning for `GENERIC_FOUNDRY` (it's referenced in Step 3).

```
cd src-tauri && grep -n "shared foundry\|GENERIC_FOUNDRY" src/pairing.rs
```
**Expected:** shows the constant definition, the guard using it, and the new "shared foundry (…)" reason branch.

---

## Test plan

Covered by the test in Step 5. It asserts both halves: the placeholder produces **no** shared-foundry reason, and a real foundry ("Adobe") produces the correctly-labeled "+4" reason. No new test file — extends the inline module from plan 001.

---

## Maintenance note

- If a future change introduces additional generic foundry placeholders (e.g. `"Unknown"`, `"System"`), extend the `shared_foundry` guard rather than re-introducing string literals. Consider promoting the check to a small `fn is_generic_foundry(s: &str) -> bool`.
- The `google_fonts.rs` catch-all still writes `"Google Fonts"` deliberately — do not "clean that up" as a follow-on without re-checking `refresh_google_fonts`'s `WHERE foundry IS NOT NULL` count and the UI foundry display, which depend on the value being present.

---

## Escape hatches — STOP and report instead of improvising if:

- The grep in Step 1 finds the placeholder written from more than one location, or the literal differs (e.g. capitalization) — reconcile before editing, and report.
- Plan 001 does not yet exist (no `#[cfg(test)] mod tests` in `pairing.rs`) — you can still make the production change (Steps 2–4), but **note in your report that the test (Step 5) could not be added** and recommend doing 001 first. Do not invent a separate test harness.
- The `score_pair` block has been refactored such that the `shared_foundry`/reason code no longer matches the excerpts — report the divergence rather than guessing where to apply the guard.
