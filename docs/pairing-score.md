# FontDrop Pairing Score Breakdown

How FontDrop decides which fonts work together.

---

## How scoring works

Every font in your library is scored against the selected primary font. The engine starts with a **base score** from the Font Matrix (skeleton + flesh compatibility), then applies **modifier signals** that add or subtract points based on real typographic properties extracted from the font files.

Final scores are clamped to 0-100. Fonts scoring 0 are filtered out entirely.

---

## Base score: Font Matrix compatibility

The foundation. Two fonts either share structural DNA or they don't.

| Condition | Base score | Pair type | What it means |
|---|---|---|---|
| Same skeleton (e.g. both dynamic) | 90 | Harmonious | Shared underlying structure regardless of serif/sans differences. The strongest natural pairing. |
| Different skeleton + different flesh | 75 | Bold contrast | Intentional visual tension. A dynamic serif with a geometric sans creates energy that works. |
| Confirmed superfamily | 90 | Designed to pair | The designer already solved the pairing problem. IBM Plex Serif + IBM Plex Sans, for example. |
| One font unclassified | 40 | Uncertain | Can't confirm compatibility. Might work, might not. |
| Both fonts unclassified | 30 | Uncertain | Neither font has been analyzed. Low confidence. |
| Same flesh, different skeleton | 0 | Conflict | Excluded from results. These fonts look alike on the surface but fight underneath. |

### Skeleton types

- **Dynamic** — Open apertures, diagonal stress. Garamond, Caslon, Frutiger. Warm and approachable.
- **Rational** — Closed apertures, vertical stress. Bodoni, Helvetica, Didot. Orderly and reserved.
- **Geometric** — Constructed circular forms, uniform strokes. Futura, Avenir, Montserrat. Clean and modern.

### Flesh properties

- **Contrast**: Linear (uniform stroke thickness) vs. Contrasting (thick/thin variation)
- **Form**: Serif vs. Sans

### Same-flesh penalty

The most common pairing mistake: two fonts that share the same skeleton AND the same flesh (both linear sans, or both contrasting serif). They look similar enough to feel redundant but don't create meaningful contrast.

| Condition | Effect |
|---|---|
| Same skeleton + same contrast + same serif/sans | -25 (demoted to "Worth a shot") |
| Same skeleton + same contrast + different serif/sans | No penalty (serif vs sans = good) |
| Same skeleton + different contrast | No penalty (stroke contrast = variety) |

Examples:
- Futura + Helvetica (geometric linear sans + geometric linear sans) → demoted
- Futura + Bodoni (geometric linear sans + geometric contrasting serif) → no penalty
- Garamond + Caslon (both dynamic contrasting serif) → demoted

These pairs still surface — they're moved to "Worth a shot", not excluded. Sometimes two similar fonts work in specific contexts. But the engine no longer treats them as strong matches.

---

## Modifier signals

Applied on top of the base score. Each signal reads real data from the font file — no guessing.

### Superfamily detection

The highest-confidence signal. When a type designer creates a serif and sans as part of the same system, the pairing is solved by design.

| Condition | Effect |
|---|---|
| Confirmed superfamily match (e.g. Source Serif + Source Sans) | +20, score floor 85 |
| Same designer + different flesh (likely designed to pair) | +10 |
| Same superfamily, same role (Roboto + Roboto Bold) | Skipped — that's not a pairing |

Known superfamilies in the engine: IBM Plex, Source, Roboto, Noto, DM, PT, Fira, Libre, Freight, Alegreya, Cormorant, Space, Instrument, Geist, Merriweather, Josefin, Nunito, Chivo, Ubuntu, Barlow, Archivo, and more.

### Optical role clarity

Fonts have intended reading environments. Two display fonts competing for attention doesn't work. A display font paired with a text font has built-in hierarchy.

| Condition | Effect |
|---|---|
| Display + Text | +8 |
| Display + Caption | +5 |
| Display + Display | -8 |
| Text + Text | -3 |
| Mono + any non-mono | -5 |
| General + anything | +0 |

Role detection uses font name keywords (Display, Text, Caption, Mono) and metric heuristics (stroke contrast, x-height ratio).

### x-height proximity

Two fonts set at the same point size should look the same optical size. x-height is the primary driver of this.

| Condition | Effect |
|---|---|
| Within 5% | +5 |
| Within 10% | +3 |
| Within 20% | +1 |
| Greater | +0 |

### Cap height proximity

Different cap heights create visual imbalance in headings and mixed-case settings.

| Condition | Effect |
|---|---|
| Within 4% | +4 |
| Within 8% | +2 |
| Greater | +0 |

### Ascender/descender harmony

The total vertical proportion of a font. Very different proportions mean one font feels cramped next to the other in running text.

| Condition | Effect |
|---|---|
| Within 8% | +3 |
| Within 15% | +1 |
| Greater than 15% | -2 |

### Weight contrast

Usable weight hierarchy between the two fonts.

| Condition | Effect |
|---|---|
| One regular (400) + one bold (700+) | +3 |
| Same weight + same skeleton | -5 |

### Weight range availability

Fonts with wide weight ranges are more flexible pairing partners.

| Condition | Effect |
|---|---|
| One has bold, other has regular | +3 |
| Both have wide ranges (variable or 100-900) | +3 |
| Neither has bold, neither has wide range | -2 |

### Shared foundry or designer

Fonts from the same designer or foundry often share subtle proportional decisions that make them work well together, even when they aren't a formal superfamily.

| Condition | Effect |
|---|---|
| Same foundry or designer | +4 |

### Both variable fonts

Variable font pairs are inherently flexible — the designer can fine-tune weight, width, and optical size to create precise hierarchy.

| Condition | Effect |
|---|---|
| Both variable | +2 |

### Flesh contrast bonus

One linear + one contrasting creates textural variety that adds visual interest.

| Condition | Effect |
|---|---|
| Different flesh contrast | +3 |

### Spacing personality

Fonts have natural spacing rhythms. Two tight-spaced fonts suffocate each other. A normal-spaced text font with an open display font creates comfortable contrast.

| Condition | Effect |
|---|---|
| Normal + Open | +3 |
| Normal + Normal | +2 |
| Tight + Normal | +2 |
| Tight + Open | +1 |
| Open + Open | -2 |
| Tight + Tight | -3 |

Spacing personality is measured from average lowercase advance widths normalized against the font's units-per-em.

### Width contrast

Fonts have proportional width classes (condensed, normal, expanded). Pairing a condensed font with a normal-width font creates natural visual hierarchy — the condensed font occupies less horizontal space, making it a natural headline partner for a normal-width body font.

| Condition | Effect |
|---|---|
| Condensed + Normal | +4 |
| Condensed + Expanded | +2 |
| Normal + Normal | +0 |
| Both condensed | -3 |
| Both expanded | -2 |

Width class is read from the OS/2 table's usWidthClass field.

---

## How results are organized

Results are grouped into three named sections instead of a ranked list. Each section represents a different kind of typographic relationship.

### Plays well together
*Same DNA, different feel*

Fonts that share underlying structure (same skeleton) or are part of a designed superfamily. Safe, reliable starting points.

Includes: pair_type = "harmonious" or "superfamily"
Cap: 4 results

### Interesting tension
*Different structure, deliberate contrast*

Fonts with different skeletons and contrasting flesh. The visual tension is intentional and creates energy.

Includes: pair_type = "bold"
Cap: 4 results

### Worth a shot
*We're less sure — but try it*

Lower confidence pairs where one or both fonts lack full classification, or the score is below 60. Worth exploring.

Includes: pair_type = "uncertain" or score < 60
Cap: 3 results

### What's excluded

Conflicts (same flesh, different skeleton) are never shown. These fonts look alike on the surface but fight underneath — surfacing them would waste the designer's time.

---

## Card labels

Each match card shows a short tag instead of a score or grade:

| Pair type | Tag | Color |
|---|---|---|
| harmonious | Same DNA | Green |
| superfamily | System | Gold/Amber |
| bold | Tension | Blue |
| uncertain | Maybe | Gray |

The section header already contextualizes the relationship — the tag is a quick visual indicator, not a judgment.

---

## Detail view labels

When expanding a match card:

| Pair type | Detail label |
|---|---|
| harmonious | Same DNA |
| bold | Intentional tension |
| superfamily | Designed as a system |
| uncertain | Worth a shot |

The "Why this might work" callout replaces the previous "Why this works" — softer language that acknowledges these are starting points, not guarantees.

---

## Manual overrides

Users can manually set any font's skeleton classification. Manual overrides:

- Persist across sessions (stored in SQLite)
- Are never overwritten by auto-classification
- Show a pencil icon on the skeleton badge
- Can be reset to auto-classification at any time

Changing a font's skeleton immediately re-scores all its pairings.

---

## Data sources

| Data | Source | When populated |
|---|---|---|
| Skeleton (dynamic/rational/geometric) | Glyph outline analysis via skrifa | First scan, or manual override |
| Flesh (contrast, serif) | OS/2 + Panose tables, name keywords | First scan |
| x-height, cap height, ascender/descender | OS/2 table (sxHeight, sCapHeight, sTypoAscender) | First scan |
| Optical role | Font name keywords + metric heuristics | First scan |
| Superfamily | Hardcoded lookup + name prefix matching | First scan |
| Spacing personality | Average lowercase advance widths from hmtx table | First scan |
| Foundry, designer | Google Fonts API + curated lookup table | First scan (requires API key for full coverage) |
| Weight range | OS/2 usWeightClass, consolidated per family | First scan |
