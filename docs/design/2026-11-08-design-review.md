# Design review, Nov 8: the Instrument system, tightened

Scope: every screen, both themes, read from the running app and from the code. Paper page "Design review · Nov 8" holds the sketches. This doc replaces the separation, surface and control sections of `2026-11-05-instrument-look.md`. Everything else in that spec stands.

## Verdict

The look is right. The system under it is not finished. The app has one good idea (a red live value on a dark instrument) and repeats its supporting moves until they stop meaning anything. The fix is mostly removal.

Three findings explain most of what feels off:

1. **One value is drawn up to four times.** Body appears as a Doto number, a ruler, a slider and a stepper. Measure appears on a screen, on a slider and in a stepper. The eye has to work out which one is the control.
2. **Treatments have too many jobs.** The recessed screen does 5 jobs. Mono caps do 6. A treatment shared by that many roles encodes nothing.
3. **Nothing says which surface is the work.** Three panels sit at one level with three different fills.

## Findings, worst first

### Structural

| # | What is wrong | Broken relationship | Fix |
|---|---|---|---|
| S1 | The Body slider and stepper do nothing while the scale is on Auto. They dim to 55% and ignore the drag. | State without an exit: the control looks present and refuses. The way to enable it (turn a different control) is not discoverable. | Every control is always live. Touching Body takes the scale out of Auto. |
| S2 | Slider, stepper and readout show the same value. | Redundancy: three objects, one fact. Hit target confusion: the eye goes to the slider, the stepper competes. | One row: label, value, track. Click the value to type. Up and Down nudge. No plus and minus. |
| S3 | Sidebar, content and inspector have three fills. The middle is a panel at the same level as its tools. | Elevation means z-position: all three float, so none is the work. | Two surfaces. **Ground** is the work. **Panels** are the tools, one token, floating on it. |
| S4 | Panels sample the desktop through system glass, so the same panel changes tint with the wallpaper. | A token fill stops being a token. | Panels are opaque. Glass only on bars that float over the stage, where it has something to show. |
| S5 | Text inspector stacks a scale line and the dial, both recessed, both saying 1.25. | Redundancy at the top of the panel. | Open, the line becomes a plain section header. Closed, it stays the readout. |

### Behavioral

| # | What is wrong | Broken relationship | Fix |
|---|---|---|---|
| B1 | Traffic lights jump. AppKit moves them on layout passes the app does not listen for, and the app put them back one tick later. | Placement ran after the move, asynchronously. | Watch the buttons' own frames and correct in the same pass. |
| B2 | Two different sliders in one inspector: the app's own on Set, the system's in Spacing and features. | State sets differ between twins. | One slider component. |
| B3 | "Nothing selected" appears twice side by side on Text. | Same message on two surfaces. | The stage says it. The inspector stays quiet. |

### Visual

| # | What is wrong | Broken relationship | Fix |
|---|---|---|---|
| V1 | Inset shadow is a 3 pt blurred stroke on all four sides. | Light comes from above, but the shadow rings every edge, so it reads as fog. | One inner shadow from the top, tight, using the system's inner shadow. A hairline lit edge at the bottom only in dark. |
| V2 | Recessed treatment on sample, letter tiles, alternates, empty states, dial, readouts, status. | Rule 11: seven uses, no meaning. Rule: nothing glows near a specimen. | **Screens** hold live numbers only: dial, scale line, status. Specimens sit in a flat **well**. Empty states have no container. |
| V3 | Evidence points are chips, and one is a full sentence. | A chip promises a toggle or a tag. These are neither. Wrapped chips make ragged negative space. | Plain lines, one fact per line. |
| V4 | Mono caps on section heads, control labels, Back to Auto, footers, range ends, meta lines. | Six roles, no hierarchy. | Mono caps mark section heads and labels on screens. Everything else is SF. |
| V5 | Section numbers (01, 02, 03) imply a sequence the panel does not have. | Signal with no information. | Cut. |
| V6 | Sections separated by a space that varies from 22 to 34 pt. | Grouping by gap alone needs a much larger gap than the panel can afford. Sketches A and B on the board. | A full-bleed rule, one token, between sections. It touches the panel edge, which makes the panel feel wider. Fill-step groups added a fourth nested radius. |
| V7 | Colors is a capsule in a capsule. | Two separations on one boundary. | One. |
| V8 | Control heights 22, 24, 26, 30, 36, and three radii on the same line. | Density not derived from one type size. | Control 28. Compact 22. Primary 40. Radius by nesting. |
| V9 | Inspector title sits 52 pt down. The top row sits 16 pt down. Traffic lights sit at a third height. Action bar buttons sit outside the 20 pt lane. | No shared top line, no shared side lane. | One top line: the traffic lights, the search row and the inspector title centre on it. One side lane of 20 pt. |
| V10 | Selected card has a 2 pt white ring. Every other selection is a neutral fill. | One state, two languages. | 1.5 pt ring at reduced strength. The card needs an edge because its fill is a specimen ground. |

## The system

### Surfaces

| Token | Dark | Light | Used for |
|---|---|---|---|
| ground | #121211 | #F1F1EE | window, gutters, grid, stage, Set page |
| panel | #1E1E1C + grain | #FFFFFF + soft shadow | sidebar, inspector, Text list, cards |
| bar | glass | glass | only what floats over the stage |
| screen | #0D0D0C, inner shadow | #EDEDEA, inner shadow | live numbers |
| well | white 5% | black 4% | specimens inside a panel |
| rule | white 7% | black 8% | between sections |

Rule: **the work sits on the ground, tools float on it.** A new surface needs a new z-position, not a new shade.

### Controls

- **Value row.** Label left, value right, track under. Value is dim while Auto and bright once set. A small return mark appears when it can go back to Auto. Click the value to type. Up and Down step by one.
- Track 2 pt, thumb 14 pt, hit area the full row height.
- **Control heights.** 28 for menus, search and buttons. 22 for inline. 40 for the one primary action per panel.
- **One signal.** Red is a live value. One glowing instrument per product.

### Sections

Title block at the top line. Then sections, each with a mono-caps head, 16 above and 20 below, and one full-bleed rule between. No numbers.

## For the other products

This is the part that travels. The other products in the suite take these rules as they are and change only their instrument.

1. Two surfaces: ground for the work, panel for the tools.
2. One instrument with a live red value. Everything else is quiet.
3. Screens hold live numbers. Wells hold specimens. Nothing else is inset.
4. Sections are split by one full-bleed rule.
5. Every number is a value row. Never a slider and a stepper for one value.
6. Every control is live. A control never waits for another one to unlock it.
7. Mono caps name sections. Doto shows numbers on screens. SF does the rest.
8. One top line, one side lane, three control heights.

The test for a new component: name its one job. If an existing treatment already has that job, use it. If the treatment has another job, make a new one or do without.

## Decided in the build, reversible

- Steppers are gone (added in R7). Typing and arrow keys replace them.
- "No hairlines" in the Nov 5 spec is reversed for one case, between inspector sections.
- The Text list is now its own panel.
- The Export block in the Set inspector is gone. It repeated the Export menu on the same screen.
