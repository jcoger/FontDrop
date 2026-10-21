# Idea: pairing as questions you steer, not a score you read

Status: idea, not planned. 2026-10-21. Prompted by Jarrett: "a lot of people's advice is just 'choose the same foundry'... finding good contrast is important, hence PP Museum even though it was weirder. These are things you ask yourself." And: share reasoning and ideas, but do not take away the designer's choice.

Grounded in: `docs/research/pairing-rulebook.md`, `pairing-from-books.md` (sections 2, 7), `src-tauri/src/pairing.rs`, `src/components/PairMode.tsx`, and the Paper file "FontDrop — Rethink" (jobs not ranks; fonts first, logo optional; Brand is the scope).

## The idea in one paragraph

Today the engine decides, then shows its answer. A designer works the other way round. They ask a question, look, ask the next one. FontDrop should expose the lenses as questions the designer asks. The engine answers each with measured facts. The designer picks the answer they want. Fitness for the job stays fixed. Taste stays theirs.

## 1. Where today's model clashes with how designers choose

| What designers do | What the engine does today |
|---|---|
| Brown: gather 6-8 candidates fast, do not research each first (R4) | Returns up to 11 ranked cards. Ranking implies "stop at the top". |
| Judge the pair together, on one surface, real text (R5) | Each card shows one wordmark. The Reading step needs real copy and the real headline face. |
| Time-box, sleep on it, look again tomorrow (R6) | No way to park candidates. Stars are global, not per job or per brand. |
| Latin's 4 steps: anchor, candidates, judge together, decide | One screen, one score. No "my shortlist" stage. |
| Ask "do I need a second face at all?" (R1) | Always finds a partner. "Keep one face" is never offered. |
| Sources split on sans+sans, weight direction, x-height, history (section 7) | One weight set, one answer. Disagreement is hidden in the numbers. |
| "Why PP Museum? Because it contrasts." Reasons are personal | One fixed recipe. Foundry and "same hand" were tuned to one designer's 9 pairs and hurt on others. |
| Pairing is asymmetric: header and body are different jobs | Score is nearly symmetric. The job filter is the only asymmetry. |

The root problem: the engine hands over a verdict. Designers want a tool for asking.

## 2. The lenses as questions

Two kinds. **Fixed** lenses are fitness for the job. A face that fails them is not a taste choice, it is a bad body face. **Steerable** lenses are taste. The designer sets them. The engine only measures.

### Fixed (never a slider)

| Question | Measured | Behaviour |
|---|---|---|
| Can it do the job? Regular, italic, bold, bold italic | Style coverage per family (`unfit_for_reading`) | Hard filter for Reading. Show "hidden: 14 (no italic)" so it is not silent. |
| Is it a text cut, not display? | Name keywords, optical size | Hard filter for Reading. |
| Does it survive small sizes? Not condensed, not mono | Width class, mono flag | Hard filter for Reading. Mono has its own job. |
| Is it licensed and complete? | Trial tag, glyph coverage | Flag on every card. Never filter silently. |

Even fixed filters show a "show hidden" link. A designer who wants a display face in body copy can see why it was hidden and override it for this brand.

### Steerable (the questions)

| Question | What the engine measures | Default | Control | Shows as |
|---|---|---|---|---|
| **How much contrast?** close / clear / extreme | Serif vs sans, skeleton distance, weight gap, width gap. Near-duplicate and too-far penalties. | Clear | **Filter** (3-way). Extreme is a real choice, not an error. | Chip: "serif + sans, different skeleton" |
| **Same hand or crossed?** pen-made vs constructed | Skeleton camp (dynamic vs geometric/rational). Typewolf 73-78. | Either | **Filter** (same / crossed / either). Today it silently adds +4. | Chip: "both pen-made" or "crossed hands" |
| **Same foundry or designer?** | Foundry, vendor, designer names. A weak proxy per the web sources. | Off | **Filter** (only these / any). Never in the rank. | Chip with the name, strength "shortcut" |
| **Match x-height?** | x-height ratio gap, cap-height gap | Show gap, no bias | **Sort** ("closest first") plus a visible number. Not a filter: a clear difference is valid (Latin, Stocks). | "x-height 9% smaller" plus a one-click size fix |
| **Popular or unexpected?** | Popularity: installs, Google Fonts rank, usage counts. Needs a data source. | Mixed, with the unexpected end labelled | **Sort** (popular to unexpected) | Chip: "common" / "uncommon" |
| **Same weight range?** | Weight gap, available weights | Show only | **Just shown**. Sources disagree (R33 vs R34). Set it on the Set screen. | Chip |
| **Include designed-together families?** | Superfamily group | Own group, collapsed | **Group toggle**. Never in the top group. | Group header |
| **Mood** (don't mix scenes) | Not measurable | n/a | **Not an engine lens.** Optional Claude note only. | none |

Rules for the control set:
1. Four controls visible, not eleven: Contrast, Hand, Origin, Sort. Others live behind "more".
2. Every control has an "any" state. Nothing is on by default except the fixed fitness filters.
3. A control that removes results says how many it removed.
4. Controls are per job and per brand. Display and Reading can ask different questions.

## 3. Showing reasoning without a verdict

**Evidence chips, not a score.** The `Evidence` struct already carries lens, detail, source and strength. Show each as a chip. Colour by effect only (helps, counts against, neutral). The big number goes. If a number must exist, it is a sort key, not a badge.

**A chip opens to its source.** Click "x-height 9% smaller" and see: the measured values, "Latin: reinforces, not definitive", and "Stocks: any mismatch can be fixed by resizing". The designer reads what the books say, including that the books split.

**Surface disagreements.** When a chip sits on a contested point (section 7: sans+sans, weight direction, history), mark it "experts split" and show both positions. Do not pick a side in the score. Four of the nine disagreements in the books are visible in the measurements; show those.

**"Why not this one?"** Every near miss answers on demand. Example: "Futura + Bodoni: crossed hands (Typewolf 73-78 calls this a clash), x-height 12% apart. Counts against: 2. Helps: serif + sans." The designer can still pick it. PP Museum is exactly this case: weirder, contrasting, chosen on purpose.

**Own picks feed a house style, visibly.**
- Stars and chosen pairs per brand form a small profile: "Your picks lean: serif display, humanist sans reading, x-height within 8%, no shared foundry."
- It shows as a banner above the results: "House style from 4 picks. Use it as a sort? [Off]". Off by default.
- It never filters. It never changes the fixed filters. It can be cleared in one click.
- With under three picks it says nothing. Taste from two data points is noise.
- It is per brand. One brand's taste does not leak into another.

## 4. The Reading step, end to end

1. Display face is set (from the logo, or picked). The Reading step opens with the question: "What carries the long reads?" One line, not a score.
2. The designer sees the **fixed filters already applied**, with "14 hidden" and a link to see why.
3. Four steering controls sit above the candidates: Contrast, Hand, Origin, Sort. Defaults are neutral. The designer changes any of them, or none.
4. Candidates appear as **real copy on the real headline**: the brand's headline in the Display face, a paragraph in the candidate. Brown's "judge together, real context". Copy can be replaced with the brand's own text.
5. The designer **flags 6-8 quickly** with one key (star, or "keep"). No scoring, no explanation required. This is the gather step (R4).
6. The shortlist tray holds the flags. It persists per brand and per job. Closing the app does not lose it. This is the "sleep on it" step (R6).
7. The designer selects **2-3 from the tray to compare**. They sit side by side, same text, same size, same measure. Controls: body size, measure, x-height correction on or off.
8. Chips under each candidate show what the engine measured, with sources. "Why not" is available on anything dropped.
9. The designer may open the contested chips ("experts split on weight direction") and read both sides.
10. The designer chooses one. The decision button is the only highlighter-yellow action: "Use for Reading". Chosen, not recommended.
11. The pair moves to the Set screen with the x-height correction and a size scale. Nothing else changes silently.
12. Later, "Revisit" reopens the tray. The unchosen two are kept, not deleted.

### Where Claude fits (advise vs apply)

Two modes, set by the designer, never by default to apply.

- **Advise (default).** Claude reads the shortlist and the evidence and writes a short note in the designer's own terms: "Satoshi and PP Mori both match x-height. Satoshi has a stiffer feel against Gambarino's soft serifs. Your past picks for another brand were humanist; neither of these is." Claude may suggest a candidate the engine did not surface, and say it is outside the measurements. The note is text. It does not highlight, rank or select.
- **Apply.** The designer says "set this up". Claude sets the values on the Set screen (family, size, line height, x-height correction) and lists every value it set, each with an undo. It does not pick the pair. Apply works only after the designer has chosen.
- **Connector.** `suggest_partners` takes the same steering parameters as the UI (contrast, hand, origin, sort). `explain_pair` returns the chips and the "why not". Claude gets facts and evidence, never a "best". This keeps Claude and the UI answering the same question the same way.
- **Boundary.** Claude can say what it would pick and why. It can never press "Use for Reading".

## 5. What this means for the engine

### Weights to become user-steerable

| Today | Becomes |
|---|---|
| Same hand: +4 for contrast pairs in one camp | Filter (same / crossed / either). Off by default. |
| Shared foundry +4, designer +3 | Filter ("only same foundry"). Out of the rank entirely. |
| x-height: up to +20 | Sort key ("closest first"). Not a score term. |
| Near-duplicate -20, width too far -6 | Part of the "how much contrast" filter (close / clear / extreme). |
| Texture +4 | Shown as a chip only. |
| Contrast bucket always first | Contrast level is the user's choice. "Uniform" is a choice, not a bucket. |

### What the benchmark should and should not optimize

- **Optimize** for coverage of good non-obvious options. Popularity predicts "good pair" better than rules in the Adobe data (73.6% vs 55.8%). The tool earns its place when the popular fonts are removed (rules 67%, popularity 55%). Measure that case first.
- **Optimize** for: do the designer's own picks appear anywhere in the candidates under some steering setting? Report "reachable" (appears in top N under some setting), not "ranked first".
- **Do not optimize** a single default ranking against Jarrett's 9 pairs. They are one taste. Report them separately, as already planned.
- **Do not optimize** AUC on taste signals (foundry, hand). They are filters now. Judge them by "does the filter keep the designer's pick when set sensibly".
- **Do** keep the books set (74 argued pairs, with negatives) as a regression test for the fixed lenses only: near-duplicates, middle, display in body.
- **Do** track "disagreement" pairs as a category: where sources split, the engine should show both sides, not score them.

### Stop building

- A single pair score as the headline. Keep a sort key internally; stop showing a number.
- Tuning foundry or hand weights against the 9 pairs.
- More weight terms in `score_pair`. New lenses become filters or chips.
- A "recommended" or "best match" badge.
- Symmetric pair scoring for the Reading job. Score "good Reading face for this Display face".
- Mood or history scoring (not measurable, no source gives numbers).

## Open questions for Jarrett

1. Popularity needs a data source. Google Fonts rank covers Google faces only. Installed commercial faces have no signal. Does "popular" apply to Google faces only, or do we skip it for v1?
2. Does the tray show the shortlist across jobs, or one tray per job?
3. House style: is a banner enough, or do you want it as a labelled sort from the first pick?

## Sketch

A new artboard "B2 · Reading, steerable" in the Paper file shows the Reading screen with the question bar, the tray and the side-by-side compare.

## Decisions (Jarrett, 2026-10-21)

- **Popularity:** Google Fonts popularity is the starting source. Look for more data later (GitHub usage counts from the benchmark mining; Fonts In Use only with permission).
- **Shortlists:** one per job (Reading, UI, Mono each keep their own), per brand.
- **House style:** ships as a "Like my picks" sort. Appears after 3 picks, off by default, always states what it learned (e.g. "same foundry in 7 of 9 picks"). Never changes the fixed filters.
- **Trend fatigue is a real lens (Jarrett, 2026-10-21):** skinny high-contrast serifs (e.g. Gambarino) now read as a slop marker. A studio brand moved from Gambarino to Timeless Serif + Timeless Sans, valued for its axes (wght, STYL: 0 = Display, 100 = Text on the serif; Sans/Grotesk on the sans). "Popular or unexpected" should eventually include "overused right now", not just raw popularity.
- **Trial fonts are encouraged (Jarrett, 2026-10-21):** trials are how designers explore and how clients get sold on paid faces. While exploring, "Trial" is a neutral tag, never hidden or ranked down. At hand-off, Export lists trial faces under "license before shipping" with the foundry link read from the file (108 of 135 trial families on a real library carry one).
