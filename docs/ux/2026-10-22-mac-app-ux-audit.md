# FontDrop Mac app: UX audit and next plan

2026-10-22, branch `swiftui-wave4b`. Done before more features, at Jarrett's request.

**Evidence base**
- 41 screenshots of the real app, on a copy of a real library (brand renamed Acme). They cover 3 window sizes (1000×692, 1360×860, 1728×1080), light and dark, first run, every template, Colors and the playground.
- View-tree measurements from the app's own `--dump-views`.
- The SwiftUI source.
- A cold walkthrough by an agent that saw only the screenshots and tried six designer tasks (section 7).
- Skills used: ui-craft (chain and composition), ux-copy (gates, cut test), improve-animations (motion audit).

## 1. The verdict in five lines

1. **Reading is broken at normal window sizes.** Its content needs about 900pt, so at the default 1360 window the sidebar and inspector are pushed off both edges. At the minimum window the sidebar is gone. This is the "couldn't change the size" bug, and it is measured.
2. **Reading hides the thing you came to compare.** Every card leads with the same Display headline, as big as possible. The body face, the only thing that changes between cards, sits small and below the fold. At 1360 you see two candidates, and both look the same at a glance.
3. **There are three "keep this" ideas on one screen:** Save (star), Add to shortlist, Use for Reading. Plus Hide. A designer can't tell which one matters.
4. **Chrome outweighs content.** Reading has two control bars: four lens menus in the toolbar, then a title, a 3-line explainer, a template switch, a Layout menu and Colors in the content. Display has two rows of mixed filter chips before the first font.
5. **It doesn't behave like a Mac app yet.** It has no keyboard navigation, no menu commands and no preview-size control. The style names are file names ("GrandHeavy", "psz]").

Display, the playground and Colors are close. Reading needs a structural fix, and the rest is cutting.

## Decisions (Jarrett, 2026-10-22)

- **Approved: Reading becomes list + stage (section 3).** "It was weird to come in the product and see a bunch of posters and not the fonts."
- **Principle: show the vibe, reveal the technical.** Designers want simplicity, developers want every detail. The default view is minimal and shows the feel. Technical detail (metrics, axes, OpenType codes, sources, file names) comes out on hover, on a disclosure, or behind a setting. It never shows by default and is never hidden for good. This applies to every screen. It is why S6 (glyph tiles, codes in tooltips) and the 2-chip card limit (S8) matter.
- **Later: the glyph tells.** Each font shows, by default, the details a designer checks when choosing: I l 1 (can you tell them apart?), a and g (single or double story), R leg, G spur, Q tail, 0 and O, &, figures, quotes. It's a small strip on the list row and the inspector. Not in this round.

## 2. Broken: fix first (measured, no design debate)

| # | What | Evidence | Fix | Done when |
|---|---|---|---|---|
| B1 | Reading content wider than its column | Host 1419pt in a 1360 window (x=−29.5); 1139pt in a 1000 window. Cause: `.fixedSize()` header controls in ReadingView.swift:41-56, a 330pt minimum card. | Let the header wrap and condense, drop `fixedSize`, card min 280, and collapse the inspector below about 1250pt. | `--dump-views` host width = window width at 1000, 1360 and 1728 |
| B2 | Templates split words ("rememb / er", "Roo / ms") and cut the hero off | Saved Display size 63pt is ×1.58 the design size on a fixed board. | Never break inside a word. Display lines shrink to fit the board width, with a floor, before wrapping. | No mid-word breaks at Size 14 to 120 in all 11 variants |
| B3 | Style names are file stems | `styleLabel()` Playground.swift:195: "GrandHeavy", "ABCReproMono-Regula…", "psz]" | Use the font's own style name (name table 17, then 2), from core. | Every style picker reads "Grand Heavy", "Regular", "Text Book" |
| B4 | Reading playground Style picker is blank | OT Miniature, 1728 shot | The selection tag isn't in the list (suggested body path). Fall back to the nearest listed style. | Never blank |
| B5 | Set shows a blank band instead of the headline | set-1360x860 with the saved Agrandir 63pt settings | Same root as B2 (TightLines at large size). | Headline renders at every playground size |

## 3. Reading: make it a stage (structural, needs Jarrett's OK)

**The job:** gather candidates, judge them against the headline in a real layout, decide. Designers judge body type by flipping between faces in the same spot, not by scanning a wall of near-identical posters.

**Proposal: list plus stage.** This is the Keynote/Photos pattern: a navigator on the left, the canvas on the right.

```
[ sidebar ][ candidates list        ][ stage: the pair in the template      ][ inspector, optional ]
           [ Difference Structure…  ][ Layout ▾   Colors   − Fit +          ]
           [ PP Editorial New       ][                                      ]
           [ "Good typography works ][   The quiet details people           ]
           [  the way good service" ][   remember                           ]
           [ ✓ Sans with serif      ][   Good typography works the way…     ]
           [ OT Miniature    ☆      ][                                      ]
           [ …                      ][        [ Shortlist ] [ Use for Reading ]]
```

- **Each list row** is the family name, two lines of body text set in that face at real reading size (16pt), and at most 2 reason chips. The thing that varies leads, and about 8 candidates fit on screen at 1360 (2 today).
- **The stage** shows the selected candidate in the chosen template, scaled to fit. The headline appears once. Zoom is Fit, 100%, ⌘+ and ⌘−. This is the size control that's missing today.
- **↑ and ↓ flip candidates in place, instantly.** That's how type gets compared. No animation, on purpose.
- **Compare:** shortlist 2 or 3 and press Compare, and the stage splits into side-by-side columns, same template.
- **Commit:** "Use for Reading" lives on the stage bar, next to the thing you're judging. The inspector keeps "Why it pairs" and the playgrounds, and is closed by default under about 1400pt.
- **Lenses** (Difference, Structure, Foundry, Sort) move from the window toolbar to the head of the list they filter.

**Smaller alternative, if the stage is too much right now:** keep the grid, but crop each card to the body region, add a card-size control (S, M, L and ⌘+/−) and a click-to-enlarge preview. It fixes the bug and density, not the comparison.

**Recommendation: the stage.** It removes the size problem rather than adding a control for it.

## 4. Simplify: cut and merge (no new features)

| # | Change | Why (rule) |
|---|---|---|
| S1 | **One keep-concept per screen.** Display: Save (star) and Hide, which curate the library. Reading: Shortlist and Use for Reading. Remove Save and Hide from the Reading inspector. Subtitle "Reading · 1 saved" becomes "Reading · 1 on shortlist". | One concept, one word (ux-copy, lexicon). "Saved" meant two things. |
| S2 | **Display filters on one row:** a scope menu "Your fonts + Google ▾" (Your fonts, Google Fonts, Mac system, Saved, Hidden), kinds as one segmented control (All, Serif, Sans, Script, Display, Mono), and More ▾ for traits. Drop the sidebar Library and Saved row, which is a filter pretending to be a place. | Elements per axis, and one perceived object instead of 11 chips (ui-craft composition). The sidebar is for places, not toggles. |
| S3 | **Star shows on hover and when saved only.** | Signal cost against frequency: a star on 396 cards that are 0 saved is noise (ui-craft rule 10). |
| S4 | **Cut the narrative leaks:** the disabled Export button ("arrives in a later wave"), the "Colors · Parked" sidebar row, and "Coming next. This is a plain specimen, not the Set tool yet." Ship nothing that is about our roadmap. | ux-copy: narrative leak, and a dead control is a dead end. |
| S5 | **Cut explainer copy that the layout already says.** Reading's "Acme pair · Agrandir with each candidate / Headlines are set in your Display face. Body and interface text are the candidate." (4 lines at 1360) goes. The stage shows it. Display's "Acme set in each of 396 families. Your fonts come first…" repeats the subtitle and goes. | Cut test: nothing changes for the reader if it disappears. |
| S6 | **Letters: show the glyph, not the code.** The 11 stylistic-set toggles ("ss01 · Alt a") become a grid of small tiles that render the alternate glyph, with the code in the tooltip only. The group starts collapsed. | Real content over labels. The current list pushes Facts off screen. |
| S7 | **Reading inspector order:** Why it pairs, then the Reading playground (open), then the Display playground (collapsed, "edited on Display"). | The candidate is what's being judged here. |
| S8 | **Card chrome:** one separation (border or fill, not a grey header band plus border plus fill), at most 2 chips per card, the rest under Why. | One separation mechanism, and per-row signal cost (ui-craft rules 2 and 10). |

## 5. Make it feel like a Mac app

- **Keyboard:**
  - arrows move selection in the grid and the list;
  - Return = Use for (role);
  - Space = big preview (Quick Look style);
  - ⌘F search;
  - ⌘1/⌘2/⌘3 = Display, Reading, Set;
  - ⌘+/⌘− = preview size;
  - ⌘Z = undo the last choice;
  - ⌥⌘I = inspector;
  - ⌘N = new brand.
- **Menus:** commands in the menu bar, so they're discoverable and show their shortcuts.
- **Type your own sample:** an editable sample line on Display, defaulting to the brand name. Every font browser has it (Font Book, Google Fonts, Fontstand).
- **First run:** don't auto-select the first font (a random trial face) and fill the inspector with it. Start with nothing selected, plus a one-line prompt to pick a face.
- **Window:** the minimum stays 1000×640, and every screen must fit it (B1). The inspector collapses itself when space runs out, like Mail and Finder.

## 6. Motion (improve-animations)

**Current motion is mostly right:**
- choose/undo swaps use easeOut 0.2s;
- disclosures use snappy 0.2s;
- the check bounces once;
- Reduce Motion is respected everywhere.

There's no `ease-in`, nothing over 300ms, and no motion on high-frequency actions.

| # | Severity | Finding | Change |
|---|---|---|---|
| M1 | Decision | Flipping candidates and switching templates must stay instant | Write it down so nobody adds a crossfade. A/B comparison depends on a hard cut. |
| M2 | Medium | Choosing a face gives no signal where it went (the sidebar row changes silently) | Highlight the sidebar row once, 200ms easeOut, then fade. Skip it under Reduce Motion. |
| M3 | Low | Counts on chips and the status line jump | `.contentTransition(.numericText())` on counts. |
| M4 | Low | Stage zoom (new) | Animate scale 200ms easeOut on ⌘+/−, never on window resize. |
| M5 | Decision | Grid reflow on filter or sort, with hundreds of cards | Keep it instant. |

## 7. Cold walkthrough (outside check)

An agent saw only 15 screenshots. It played a brand designer who knows type, and tried six tasks: start a brand, find a Display face, tune it, find a Reading face, judge 2 or 3 in a layout, and commit. Every data claim below was checked against the database before it went in here.

**Where it would give up (its three moments):**
1. **First Reading screen.** The headline breaks "rememb / er" with lines colliding, and the body sits below the fold. *"If the tool can't set my headline, I don't trust it with my body text."* (B2, section 3)
2. **Reading at laptop size.** The sidebar turns into orphan characters and the main button has no label. (B1)
3. **Right after committing.** "Next: sizes and spacing" lands on "Coming next. This is a plain specimen", and Share is greyed out. *"Once I've picked the pair, what do I take out of this app to my client and into my design file?"* (new: H1)

**New findings, verified:**

| # | Finding | Verified | Goes to |
|---|---|---|---|
| D1 | PP Neue Machina is flagged as a serif, so Reading says "Sans with serif" for a sans pair | DB: `flesh_serif=1` for all 40 Machina files | Engine: the serif detector misreads blocky terminals as feet |
| D2 | "Foundry: Alexander Slobzheninov" is a person, and "Same foundry" and "Same designer" both show | DB: foundry falls back to designer | Wave 5a shows only "Same designer"; engine should map vendor IDs to foundries |
| D3 | Thin and UltraLight both read "Weight 250"; Italic sorts above Regular | Aileron's own files say 250 for both | Order upright before italic, then by name (wave 5a) |
| C1 | "Difference: Clear" reads as a verb, next to "Clear filters" | Copy | Rename to Distinct (wave 5a) |
| C2 | Kind chip "Display 19" and the job "Display" sit on one screen with two meanings | Copy | Rename the kind chip to **Decorative**, which is what the data already calls it (Simplify round) |
| C3 | Two "saved" ideas with different counts on one screen ("Reading · 1 saved" vs "Saved 0") | Screens | S1, plus subtitle "N on shortlist" (wave 5a) |
| C4 | The counts don't add up (389 + 27 ≠ 396 shown; 241 + 40 ≠ any total) | Chip counts are each "if you add this", and sets overlap | Header shows only what's on screen; chip counts move into a tooltip (vibe first) |
| U1 | No way to type your own sample; you judge a headline face on a four-letter word | Screens | Section 5 |
| U2 | A tuned family (GrandHeavy 63pt) renders tuned in the grid while the others are default, which is an unequal comparison | Screens | The grid always shows default style; the tuned card gets a small "Tuned" mark |
| U3 | Slider values aren't editable fields; there are no steppers | Screens | Mac round: a field and stepper per slider, as in Pages and Keynote |
| U4 | Stylistic-set switches don't line up and get cut off by the bottom button | Screens | S6 glyph tiles, in an aligned column |
| U5 | Display opens on three "ABC Repro … Unlicensed Trial" cards, and first run auto-selects one | Alphabetical sort | No auto-select on first run; offer a Sort |
| U6 | Reading must start from Display; many brand projects start from the text face | Product | **Open question for Jarrett** |
| H1 | No hand-off. Export is disabled and Set is a placeholder | Screens | **Moves up:** a Hand-off v1 round before the Set tool |

**What it said works:**
- the brand name set in every card, with your fonts first;
- the Name-this-brand sheet;
- "Find a Reading face →";
- Trial badges;
- the honest "241 not made for long text · Show them";
- concrete evidence ("x-height 4% smaller than Display");
- the contrast line in Colors.

## 8. Plan of action

| Round | What | Status / proof |
|---|---|---|
| **5a. Reading stage + fixes** | Section 3, B1 to B5, C1, C3 (subtitle), D2 and D3 display-side, plus walkthrough items 2 to 9 sent to the builder | **Building now.** Proof: dump-views widths at 3 sizes; at least 6 candidates visible at 1360 (was 2); no mid-word breaks |
| **5a+. Either way in** | Display ranks against a chosen Reading face (see the decision below) | Cold walkthrough, run starting from a body face, completes with no stuck points |
| **5b. Hand-off v1** | H1: one export that answers "what do I take to the client and into my file". A pair spec page (PNG and PDF): the pair, your tuning, colors, and a license list with foundry links for trials. Copy CSS and Tailwind tokens. Copy a Paper spec. Until it ships, "Next" points at the specimen, honestly labeled. | Rerun cold walkthrough task 6: no dead end |
| **5c. Simplify** | S1 to S8, C2, C4, U2, U5; remove narrative leaks; engine fixes D1 (serif detector) and D2 (vendor-to-foundry map) | Controls per screen counted before and after; data spot-checks on D1 and D2 |
| **5d. Mac behaviour** | Section 5, U1, U3, U4, M2 to M4 | Every core task doable from the keyboard; menus list their shortcuts |

Then features resume: the Set tool, the glyph tells, and the same-family headline style.

**Decided (Jarrett, 2026-10-22): Reading works as a starting point (U6).**
- **Wave 5a:** Reading works with no Display face. The list shows faces fit for long text, each judged on its own, and after choosing, the next step is "Find a Display face".
- **New round 5a+, "Either way in":** after a Reading face is chosen, Display ranks faces against it. That means a "Pairs with <Reading face>" sort, reason lines, and the evidence worded by role ("x-height 4% smaller than your Reading face"). The engine's `font_candidates` already takes a primary font and a job, so the work is wording and UI, plus a check that the scoring isn't one-way.
