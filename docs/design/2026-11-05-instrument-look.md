# The Instrument look: build spec for R2

2026-11-05. Source of truth: Paper file "FontDrop — Rethink (Oct 2026)", page "Design review · Nov 4", boards 13 (dial), 16 (selection), 17 (dark), 18 (light), 19 (where the dial lives). Values below were set on those boards; where this spec and a board disagree, this spec wins (it carries the contrast fixes).

## Rules
1. Themes swap tokens only. No view branches on color scheme. One token resolver per theme.
2. Red #E5341D has one job: a live value (the dial needle, the lit stop, the lock light). Nothing else is red. Red is never text.
3. One separation mechanism per edge. Glass = fill plus rim (one material). Regions = fill step. Rows = gaps. No hairline rules anywhere else.
4. Dark mode has no drop shadows. Light mode uses one soft tinted shadow on floating glass.
5. Screens (dial, letter tiles, status readout, scale readout line) are recessed in both themes.
6. Doto is for numbers on screens only. Geist Mono is for small caps labels only. Neither renders a font under review. Nothing glows near a specimen.
7. Every text pair is 4.5:1 or better, unrounded, in both themes and every state.

## Tokens

| Token | Dark | Light |
|---|---|---|
| glass.sidebar fill | #232321 at 72% | #FFFFFF at 58% |
| glass.inspector fill | #161614 at 84% | #FFFFFF at 58% |
| glass.bar fill (stage toolbar pills, action bar) | #2A2A28 at 78% | #FFFFFF at 72% |
| glass.rim | inset top 1px white 10%, inset ring 1px white 4.5% | inset top 1px white 95%, inset ring 1px white 60% |
| glass.shadow | none | 0 8 28 rgba(30,40,70,0.10) + 0 1 2 rgba(30,40,70,0.08); bars 0 2 10 black 8% |
| panel.content | #1C1C1B, inset ring white 3.5% | #FFFFFF + glass.shadow |
| stage | #111110 | #F2F2F0 |
| template card | white, no shadow | white, 0 1 3 black 10% |
| select.list (pill) | #2C2C2A | #EAEAE7 |
| select.sidebar | white 10% | black 7% |
| control.ground (chips, menu pills) | white 7% | #F2F2F4 (pills), black 5% (chips) |
| screen.fill | #0D0D0C | #EFEFEC |
| screen.inset | inset 0 1 2 black 55%, inset 0 -1 0 white 5% | inset 0 1 2 black 10%, inset 0 -1 0 white 90% |
| text.primary | #EDEBE5 | #1D1D1F |
| text.secondary | **#A5A29A** (R2a: lifted from #9A978F, which measured 4.19:1 on the sidebar pill; now 4.5:1 or better on every ground, see ContrastTests) | **#5F5F64** (check 4.5+ on #EAEAE7) |
| text.on-primary-button | #161615 on #EDEBE5 | #FFFFFF on #161615 |
| signal (red) | #E5341D | #E5341D |
| dial.arc | #3A3A37, dashed 1.5 on 5 | #C4C2BC |
| dial.stop (inactive) | #77756F | #8F8D87 |
| dial.pivot | #EDEBE5, hole screen.fill | #1D1D1F, hole screen.fill |
| slider.track / fill / thumb | #2B2B29 / #EDEBE5 / #EDEBE5 + 0 1 2 black 60% | #DEDEDB / #1D1D1F / white + 0 1 3 black 25% |
| ruler ticks | #5E5C57, 1px every 8 | #B8B6B0 |
| grain | fractal noise, base frequency 0.9, 3 octaves, white at 7%, 160 px tile, on sidebar, content panel, inspector only | none |

Glow (red only): Locked = two shadows on the needle and lit stop, radius 2 at 90% and radius 7 at 45%. Turning = radius 3 and 10, settling back in 300 ms after release. Auto = no glow, needle text.secondary. Light theme keeps only the tight one (radius 1.5 at 60%). Increase Contrast: no glow, needle 1px thicker.

## Type
- UI: SF Pro. Inspector title 17 semibold. List title and verdict 15 semibold. Rows and menus 13. Row names, pills, chips 12 (names semibold). Meta 11.
- Labels: Geist Mono 10, tracking 0.14em, uppercase ("01 · SCALE", "TEXT CANDIDATE", "LOCKED").
- Readouts: Doto 900. Dial value and Body value both 30. Scale readout line 18. Status readout 13.
- Doto and Geist Mono are OFL fonts. Bundle them in the app and list them in the About window.

## Layout
- List: container inset 8, rows radius 10, padding 12 vertical / 12 horizontal, gap 2, no dividers. Text sits on the 20 px lane in every row, selected or not.
- Inspector modules: 20 px side padding, 22 top / 10 bottom, no rules between modules. Header labels carry the structure.
- Template card centred in the free area between the stage toolbar and the action bar.
- Sidebar rows 44 tall for jobs with a second line (Display, Text, Set), radius 12, inside a 12 px sidebar inset.

## Icons
SF Symbols, one weight (regular), 16 pt: Display `textformat.size`, Text `text.alignleft`, Set `square.stack` (or the closest stacked-rectangle symbol), brand switcher `chevron.up.chevron.down`, menus `chevron.down`, pop-up buttons `chevron.up.chevron.down`. No text glyphs as icons.

## Components
- **Selection pill** (list and sidebar). Keyboard focus uses the system focus ring, distinct from the pill.
- **Dial** (Set inspector, per board 13): five stops at equal angles (1.2, 1.25, 1.333, 1.5, 1.618), 1.333 straight up. Turning locks. Pressing (click or Space) returns to Auto. In Auto the needle is grey and sits at the ratio the Auto sizes add up to. Readout: "RATIO", Doto value, interval name ("FOURTH"). Header right: lock light + "LOCKED" or hollow light + "AUTO". A trackpad click (NSHapticFeedbackManager, .alignment) at each stop. Arrow keys step one stop. VoiceOver: "Ratio, 1.333, locked". Reduce Motion: no spring.
- **Body slider** under the dial: label "BODY", Doto 30 value, ruler, track with thumb, range labels 9 and 24.
- **Scale footer:** "HEADLINE 84 PT · 5.6×" left, "PRESS FOR AUTO" right (text.secondary).
- **Scale readout line** (top of the Text inspector, board 19): recessed screen, "SCALE" label, Doto "15 · 1.333", lock light, chevron. Click opens Set.
- **Letters strip** (Text inspector, module "LETTERS"): four recessed tiles Il1, ag, RGQ, 0O in the candidate face, 21 pt.
- **Why it pairs:** verdict (15 semibold) + up to two chips + "Sources ›".
- **Status readout** (sidebar foot): recessed, Doto 13, "688 FAM · 4549 FILES". Red light only while scanning.

## Done check
App screenshots of Text (both themes) and Set (both themes) placed beside boards 17, 18 and 19 on one contact sheet. A contrast script over the token table passes every pair in both themes. A VoiceOver walk of the dial reads its value and state.

## Launch (D8, boards 20 and 20b)
- **First run** (no brands, library scanning): the content area shows a centred recessed scan screen: "SCANNING YOUR FONTS", a percentage, a Doto counter of files read, "OF <n> FILES · <m> FAMILIES SO FAR", and a dot-matrix progress row (lit dots text.primary, unread dots #2B2B29, the live position one red glowing dot). Under it: "Start with a headline face, or a text face." / "Fonts show up as they are read. When you pick one, FontDrop asks which brand it is for." and two buttons, "Start with Display" (primary) and "Start with Text". Either button dismisses the screen into that job. No inspector on first run. The sidebar readout shows the red light while scanning.
- **Returning:** open on the last brand, on the last screen used for that brand, with the same candidate and template (store per brand id).
- **Switching brands:** each brand lands on its own last screen.
- **Edges:** last screen Set with no faces chosen → Display. A chosen face no longer installed → its sidebar row says "Not installed". No fonts after a finished scan → a plain empty state with "Open Font Book".
