# Pairing rulebook (merged)

Date: 2026-10-21. Merges `pairing-from-books.md` (19 sources in Jarrett's library, 56 rules, 23 failure rules, 116 named pairs) and `pairing-from-web.md` (academic work, datasets, expert guides). Rule numbers (R, F) point into the books file. Nothing here has changed the engine or the type-set skill yet.

## The big picture

1. **The old rulebook was one author deep.** The skill's `pairing.md` is Matej Latin's chapter 5 only, and Latin credits his method to Tim Brown. 18 more sources were in the library and unused.
2. **No source gives numbers.** Every rule is qualitative. Any weight in the engine is our choice and has to be justified by a measurement, not by a book.
3. **Popularity beats rules in real data.** In Adobe's study of 13k real header/body pairs, "pick popular fonts" scored 73.6%. Designer rules scored 55.8%. Once the popular fonts are removed, rules win (67%) and popularity drops to 55%. FontDrop's value is in the second case: good pairs beyond the obvious ones.
4. **The broad test set already exists.** The books argue 74 pairs with reasons, praised and criticised, from many authors. That is the multi-practitioner set the web research recommends (30–40 needed), with negatives included.

## Rules, mapped to the engine

Status: ✅ engine does it · 🟡 partly · ❌ missing · 🧭 product, not score.

### Core shape
| Rule | Sources | Engine today | Proposed |
|---|---|---|---|
| Same or very different; the middle fails (R12, F1) | LAT, MAY, TWC, STO, BON + web (Typekit) | ✅ contrast / uniform / middle | Keep |
| **Too much contrast also fails** (R14, F6, F7) | BON, BRO | ❌ | Penalise extreme weight or width gaps |
| **Near-duplicates fail** (F3, web) | TWC, BON, Typekit | 🟡 uniform rewards sameness | Penalise near-identical metrics + class |
| Serif with sans is the easy contrast (R15) | LAT, TWC, BON, MAY | ✅ | Keep |
| Second sans / second serif: hard, not banned (R16) | TWC vs LAT vs MAY (split) | ✅ uniform group | Keep, small group |
| Similar on some axes, different on others | Fontjoy, Jiang, Monotype, Typekit | 🟡 | Becomes the scoring shape (below) |

### Structure
| Rule | Sources | Engine today | Proposed |
|---|---|---|---|
| **Pen-made vs constructed camp** (R20, R21, R22, F4) | TWC 73–78, Typekit (history) | ❌ engine splits geometric from rational; Futura + Bodoni scores as a clash | Dynamic = pen camp; geometric + rational = constructed camp. Contrast pairs score higher inside one camp |
| Genre table: humanist sans + Old Style, geometric sans + Modern serif, grotesque + Transitional, neo-grotesque + slab (R21) | TWC 74–78 | ❌ | Falls out of the camp rule above |
| Skeleton / flesh / skin matrix (R19) | STO (Kupferschmid) | ✅ | Keep; "guides, not rules" |
| Shared glyph details g, a, k, c (R23) | TWG ~9 of 20 pairs, BRO | ❌ | Later. Needs outline comparison |

### Metrics
| Rule | Sources | Engine today | Proposed |
|---|---|---|---|
| x-height: match **or differ clearly**, matching is "not definitive" (R27) | LAT, LCS, BON + Typekit, Monotype (first check) | 🟡 rewards match, flat | Keep first among metrics; don't punish a clear difference |
| Equalise optical size by x-height (R28, F8) | STO, TWC, SAM | 🧭 | The x-height correction on the Set screen. Confirmed by 3 sources |
| Ascenders / descenders (R29) | STO, TWG | ❌ (was dropped) | Small signal |
| Shared proportions calm, contrasting agitate (R31, F13) | BRO, TWG | 🟡 width only | Cap-to-x ratio + width |
| Weight must separate roles (R33) vs heads should get lighter (R34) | BON, TWC, RUI vs TWC (Bringhurst), LAT | — | 🧭 Set screen, not score. Sources disagree |

### Origin
| Rule | Sources | Engine today | Proposed |
|---|---|---|---|
| Same family first (R38) | STO, LAT, TWC | ✅ Designed together | Keep its own group |
| Same designer, then foundry: raises odds, no guarantee (R39) | STO, LAT, TWC + web: "weak proxy" | 🟡 +10 foundry, +6 designer | **Cut foundry to a small nudge.** +10 was tuned to Jarrett's habit |
| History: same period or far apart (R41, R42) | LAT, MAY, Typekit | ❌ | Skip. Not in the file; Latin says it fails for post-digital faces |

### Role and fitness (filters, not taste)
| Rule | Sources | Engine today | Proposed |
|---|---|---|---|
| **Reading face must ship R, I, B, BI with true italic** (R55, F12) | TWC, STO, TWG | ❌ | Hard filter for the Reading job |
| **No display cut in a text job** (R51, F9, R52) | TWC, REY | ❌ | Reading job skips display cuts; prefers text cuts |
| Body anchor: low contrast, big x-height, open aperture (R3, R47) | BRO, TWC, TWG, EDS | ❌ | Reading-job fitness score |
| Mono is a valid complement (R54) | STO, TWC | ✅ (v1 penalty gone) | Mono job |
| Condensed / short-x faces fail in body (F16) | TWC, RUI | ❌ | Reading-job filter |
| Few weights = often poorly built (F18) | RUI | ❌ | Small penalty |
| Glyph coverage + licence first (R56) | STO, BRO | ❌ | 🧭 trial tag + coverage check |
| Mood: don't mix scenes (R43, F5) | BON (+3 sources) | ❌ | Not measurable. Optional AI explain layer |

### Pairing is asymmetric
Header and body are different jobs (Jiang; BRO's six jobs; R8). FontDrop's jobs model already says this. The score should ask "good Reading face **for this Display face**", not a symmetric distance.

## What the skill overstated (fix in `type-set/references/pairing.md`)
- "Based on proportions" is not one of Latin's lenses.
- "Adjacent periods fail" has no source.
- x-height is stated harder than Latin, who calls matching not definitive.
- The superfamily warning is a Dyno rule, not the books'.
- "Routinely fail" and "mono counts as a third" are additions.
- The four-step method is Brown's (via Latin), and Brown's own palette method is missing.

## Benchmarks
1. **Books set (now):** 74 argued pairs, praised and criticised, 19 sources. Keep pairs where both faces are installed or on Google Fonts. Positives should rank high; negatives low.
2. **Mined set (next):** open-licence GitHub sites/templates, both faces on Google Fonts, seen in 3+ repos, no family over 5%, popularity-matched negatives. Not Fonts In Use (terms forbid scraping).
3. **Dyno set (kept, reported separately):** Jarrett's 9 shipped pairs. Personal taste, not the target.
4. **Baselines every run:** popularity and Fontjoy's MIT vectors. If the engine can't beat them, the rules add nothing.
