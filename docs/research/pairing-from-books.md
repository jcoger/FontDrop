# Pairing: what the books say

Research date: 2026-10-21. Method: fresh read of every typography book, guide and note in the author's reference library, pairing sections only. Extracted text was treated as data. Quotes are kept to one short phrase per source. Everything else is paraphrase.

## 0. Short answer

- The skill's `pairing.md` is one author deep. It is Matej Latin's chapter 5 and nothing else. The library holds 19 sources with pairing content.
- The biggest rule sets the skill never used: Typewolf's checklist (items 67-79), Typewolf's 20 worked pairs, Elliot Jay Stocks (Kupferschmid's font matrix), Tim Brown's palette method, and Dan Mayer and Douglas Bonneville in Smashing eBook #6.
- The font matrix is new to the skill but already in the engine. Most other gaps are in neither.
- Seven statements in the skill go further than their source. See section 5b.
- Sources disagree on nine real points. See section 7.

Counts: 19 sources, 56 rules, 23 failure rules, 117 named pairs (see section 8).

Key to the "In font file?" column: **yes** = readable from tables or outlines. **partly** = needs a lookup table, name keywords or rendering. **no** = human judgment or outside data.

Key to the "Strength" column: **rule** = the author states it flat. **guideline** = the author says "best practice" or "usually". **shortcut** = the author says it raises odds, no guarantee. **caveat** = the author warns against over-using it.

---

## 1. Sources found

### Used (pairing content)

Short codes are used in every table below.

| Code | Source | How read |
|---|---|---|
| LAT | Matej Latin, *Better Web Typography for a Better Web*, ch. 5 "Combining typefaces" | EPUB to text |
| LCS | Latin, *Combining Fonts Cheat Sheet* (2 pages) | Image only. Read by eye. |
| LCL | Latin, *Better Web Type Checklist* and *Recognising Font Styles Cheat Sheet* | pdftotext |
| BRO | Tim Brown, *Flexible Typesetting*, ch. 3 (type palette), ch. 5 (contrast), ch. 6 (clashing textures) | EPUB to text |
| STO | Elliot Jay Stocks, *Universal Principles of Typography* (foreword Ellen Lupton), pp. 8-9, 40-47, 53, italic principle | EPUB to text |
| TWC | Jeremiah Shoaf (Typewolf), *Flawless Typography Checklist*, items 17-22, 52, 57-60, 67-82, 90 | Plain text |
| TWG | Typewolf, "10 Best Serif + Sans-Serif Font Combinations" on Adobe Fonts, Typekit and Google Fonts | pdftotext |
| SM6 | Smashing eBook #6, *Getting the Hang of Web Typography*: Dan Mayer "The Typography Dress Code" (pp. 123-142), Douglas Bonneville "Best Practices of Combining Typefaces" (pp. 143-157), and a 2009-era survey of headline and body faces (pp. 103-109) | pdftotext |
| DUG | Smashing Book 4, ch. 9 (Marko Dugonjic), "Combining Typefaces" section | pdftotext |
| REY | Smashing, *Typography Best Practices*, Dan Reynolds "How To Choose The Right Face For A Beautiful Body" (pp. 28-35) | pdftotext |
| NLE | Nguyen Le, *Typography Playbook* (149 pp.) | Image only. OCR (macOS Vision). One page checked by eye. |
| RUI | Refactoring UI, "Use good fonts" (pp. 108-112) and "Choose a personality" | pdftotext |
| RFR | Refactoring UI, *Font Recommendations* sheet | pdftotext |
| TON | Beth Tondreau, *Layout Essentials, Revised* (case captions) | EPUB to text |
| EDS | *Expressive Design Systems*, ch. 3 and ch. 4 | EPUB to text |
| LTL | *Logos That Last*, brand elements and brand typography | EPUB to text |
| UXP-A | UXPin, *Web UI Design for the Human Eye: Content Patterns and Typography* | pdftotext |
| GFC | greatsimple.io, *Google Fonts Combinations* (one pair, no text) | pdftotext |
| SAM | Timothy Samara, *Making and Breaking the Grid*, 2nd ed. (x-height note only) | EPUB to text |

**SM6 key:** MAY = Dan Mayer's chapter. BON = Douglas Bonneville's chapter. "SM6 survey" = the survey article. All three are in the one book.


### Checked, nothing usable on pairing

UXPin *Web UI Trends: Dramatic Typography* (effects, not pairing), Smashing *Legacy of Typography*, *The Graphic Design Reference and Specification Book* (classification only), *Hardboiled Web Design*, Smashing Book 3, *Design is a Job*, *Designing for Emotion*, `Typography Lesson.txt` and `Typeface Notes.txt` in the iA Writer folder (Jarrett's notes, one line on ITC Conduit). There is no Bringhurst there.

### Not in the library (cited only second-hand)

Bringhurst *The Elements of Typographic Style* (quoted by TWC and STO), Jason Santa Maria *On Web Typography* (quoted by TWC and STO), Erik Spiekermann (quoted by TWC), Ellen Lupton *Thinking with Type* (only the foreword to STO is here), Indra Kupferschmid's font matrix primary text (read through STO), Tim Brown *Combining Typefaces* (the pocket guide Latin says his method is "very much based on"), Stephen Coles *The Anatomy of Type* (quoted by TWC), Carl Dair *Design with Type* (named by BRO). The skill already flags Bringhurst as missing. This confirms it and adds the rest.

### Attribution slip in the skill

`pairing.md` calls the four-step sequence "Latin's method". Latin says it is based on Tim Brown's *Combining Typefaces*. Brown's own, different method is in *Flexible Typesetting* ch. 3 and the skill does not use it.

---

## 2. Rules

Own words. Chapter, page or item numbers point to where each rule lives.

### A. Process

| # | Rule | Measurable property | In font file? | Source and place | Strength |
|---|---|---|---|---|---|
| R1 | Ask first whether you need a second face. One face, used well, is a valid answer. Many families already cover serif, sans, slab, script and mono. | Count of families. Does the family offer sibling styles? | partly | LAT ch.5 (Gill quote, Baskerville single-face example); STO p.42; MAY (use one face for months); TWC 67; LCL | guideline (5 sources) |
| R2 | Pick the anchor first. It is the body face, chosen against real content. All other faces complement it. | None | no | LAT ch.5 step 1; BRO ch.3 "Choose an Anchor Typeface" | rule |
| R3 | A good body anchor has sturdy shapes, even color and an active but not busy texture. Prefer low stroke contrast, large x-height, open apertures, large counters. | Stroke contrast, x-height, aperture, counter size | yes | BRO ch.3; TWC 17; TWG intro | guideline |
| R4 | Gather six to eight candidates fast. Do not research each one first. Research before seeing the face can lock you into a combination you then fight to make look right. | None | no | BRO ch.3 "Make loose choices", "Do a quick tech check"; LAT ch.5 step 2 | guideline |
| R5 | Judge the pair together, on one surface, in real context, with real text. Squint, then look close. | None | no | BRO ch.3 "Seek graphic harmony"; LAT ch.5 step 3 | rule |
| R6 | Time-box the search (BRO: two or three hours). Then sleep on it. If it still feels right tomorrow, ship it. | None | no | BRO ch.3; LAT ch.5 step 4 | guideline |
| R7 | Look at Fonts In Use for faces already combined with your anchor. | Outside data | no | BRO ch.3 | shortcut |
| R8 | Give each face a written job. BRO lists six jobs: body, display, signage/UI, tabular data, technical accuracy (code, math), small text. Treat them as a wheel, not a list. Bonneville runs 4 fonts from 3 families by fixing each role. | Role tag per font | partly | BRO ch.3 Fig 3.4; BON pp.146-147 | rule |
| R9 | The target depends on the job. Display should stand out when you squint. UI should read a little clearer than the rest. Supporting text should recede or match the anchor's color and texture. | Rendered gray value, x-height, stroke contrast | partly | BRO ch.3 "Study texture" | guideline |
| R10 | Define the roles and then hold to them. A consistent system matters more as faces multiply. | Role map | no | TWC 61, 67; BON p.147 ("when in doubt, define") | rule |
| R11 | Loosen the "rules" with skill. Almost any two faces can work in the right hands. Know the rule you break. | None | no | TWC 79; MAY (rule five, "no rules"); STO p.47 | caveat |

### B. Contrast and uniformity

| # | Rule | Measurable property | In font file? | Source and place | Strength |
|---|---|---|---|---|---|
| R12 | Keep it the same or change it a lot. The middle fails. | Distance between the two faces on any chosen axis | partly | LAT ch.5; MAY "Decisive Contrast" (coin analogy); TWC 72; STO p.47; BON "Avoid Similar Classifications" | rule (4 sources) |
| R13 | When you shift face, size or weight, shift on purpose. A timid shift looks like a mistake. | Size ratio, weight gap | yes | LAT ch.5 (Rob Carter quote); TWC 57 | rule |
| R14 | Too much contrast also fails. Extreme weight or width gaps look awkward, not bold. | Weight gap, width gap | yes | BON p.153 (Antique Olive Nord with Garamond Narrow); BRO ch.3 "Study proportion" | guideline |
| R15 | Serif with sans is the easy contrast. Same-class pairs are hard. If you must, go very similar or very different. | Serif present (yes/no) | yes | LAT ch.5 "On combining similar styles"; TWC 69-70; BON p.145; MAY | guideline |
| R16 | A second sans or second serif is not banned. TWC says avoid. LAT says possible but hard. MAY says it worked for him once. | Same genre, same class | partly | TWC 69-70; LAT; MAY rule 5 | caveat (sources split, see section 7) |
| R17 | Dissonance is a tool. You can break harmony on purpose and keep one thread tying the design (same face, same size, aligned x-height). | None | no | STO p.47 (Grunge example) | caveat |
| R18 | Contrast level should follow layout complexity. Wide, busy layouts need strong contrast. Narrow, focused ones need little. | Viewport or column count | no | BRO ch.5 "Decrease contrast as the composition gains focus" | guideline |

### C. Construction and shape

| # | Rule | Measurable property | In font file? | Source and place | Strength |
|---|---|---|---|---|---|
| R19 | Read each face in three layers: skeleton (dynamic, rational, geometric), flesh (stroke contrast and serifs), skin (serif shape, texture, decoration). Same skeleton pairs well. Opposite skeleton and opposite flesh pairs well. Same flesh with a different skeleton does not. | Skeleton class, contrast, serif | partly (engine does this) | STO p.44 (Kupferschmid, via Schondorfer) | shortcut ("guides, not rules") |
| R20 | Handwritten versus constructed is the simplest harmony test. Humanist and Old Style faces show a pen angle. Geometric and Modern (Rational) faces are upright and built. Match the two camps. | Stress angle of round letters | yes | TWC 73 | guideline |
| R21 | Genre table. Geometric sans with Modern serif. Grotesque or gothic with Transitional serif. Neo-grotesque with slab. Humanist sans with Old Style. Neo-humanist sans with contemporary serif. | Class tags | partly | TWC 74, 75, 76, 77, 78 | guideline (item 79 says "suggestions") |
| R22 | Avoid mixing two aesthetics: geometric sans with Old Style serif, Modern serif with Old Style serif, geometric sans with humanist sans. | Class tags | partly | TWC 69 (tips), 70 (tips), 74 (tips) | guideline |
| R23 | Look for shared glyph details. In about 9 of the 20 TWG pairs the author names a shared g, a, k or c shape, or a shared terminal style. Brown names R leg, c aperture, k join, a bowl. | Outline similarity of g, a, k, c, R | partly | TWG Adobe #1, #2, #4, #7; Google #2, #3, #6, #9, #10; BRO ch.3 Fig 3.27 | guideline |
| R24 | Shapes need not match to feel related. A square and a circle both read geometric. Either feels closer to the other than to a calligraphic form. | Geometric vs calligraphic | partly | BRO ch.3 "Study shape" | guideline |
| R25 | Terminal style can match or contrast. Rounded with rounded (Lora with Varela Round, Abril Text with Brandon Grotesque) is harmony. Rounded against sharp (Sofia Soft with Freight Display) is a chosen contrast. | Terminal shape | partly | TWG Adobe #2, #6; Google #9 | shortcut |
| R26 | Look for a hint of the body face's angles and curves in the partner. Study energy (blocky, fluid, calm, jumpy) and the rhythm of black and white shapes. Shared rhythm gives harmony. Contrasting rhythm helps a display face stand out. | Rendered rhythm | no (needs rendering) | BRO ch.3 "Study texture", "Study rhythm" | guideline |

### D. Metrics

| # | Rule | Measurable property | In font file? | Source and place | Strength |
|---|---|---|---|---|---|
| R27 | x-height: match it or differ clearly. Do not land in between. Matching reinforces a pair and is "not a definitive rule". Differing on purpose is possible but uncommon. | sxHeight / em | yes | LAT ch.5; LCS (both panels); BON (Sabon with Trade Gothic: both tall) | guideline |
| R28 | Equalize optical size by rescaling one face until the x-heights line up. Same point size looks like different size. Stocks sets Swear at 37.8 pt next to Degular at 40 pt. | Ratio of x-heights = size factor | yes | STO pp.8, 45; TWC 82 (Merriweather with Mrs Eaves at 21 px); SAM (same-size specimens: the sans has a much larger x-height than the serif) | rule |
| R29 | Check ascenders and descenders. Clashes may need a new line height. Short descenders on both sides help (Playfair Display with Fira Sans, SchoolBook with Adelle Sans). | Ascender and descender depth / em | yes | STO p.45; TWG Google #1, Adobe #3 | guideline |
| R30 | Match small caps and figures to the x-height of the face they sit in. | Small-cap height vs x-height | partly | STO p.8; NLE p.15 | guideline |
| R31 | Shared proportions make a palette feel calm. Contrasting proportions make it feel agitated, unless vertical proportions agree and only width differs. | Width class, cap:x ratio, extender reach | yes | BRO ch.3 "Study proportion" (Source Sans with Modesto and Ernestine); TWG Adobe #9, Google #5, #7 | guideline |
| R32 | Use width as a role tool. Condensed suits headlines. A width axis can replace a second family. Avoid short-x-height condensed faces for main UI text. | usWidthClass, width axis | yes | TWC 81; STO (width principle); RUI p.111; TWG Adobe #1 | guideline |
| R33 | Weight must separate the roles. The heading has to outweigh the body or the eye skips it. Change one thing at a time. | Weight range | yes | BON p.148-149; TWC 58; RUI (hierarchy chapter, "Don't rely on font size") | rule |
| R34 | Opposite view: weight should fall slightly as size rises. Large bold heads overpower the page. Lighten weight or color. | Weight vs size | yes | TWC 60 (Bringhurst); LAT ch.5 (a slightly lighter Korolev worked) | guideline (conflicts with R33, see section 7) |
| R35 | Match typographic color (density) when faces share a line or must sit seamlessly. Check with a squint. | Rendered ink density | partly | STO p.53; BON p.149; BRO ch.3 | guideline |
| R36 | Use different point sizes to separate hierarchy. Sizes should be equal or clearly different. | Size ratio | yes | BON p.156; TWC 57 | rule |
| R37 | When two sizes share one line, align on the baseline, not the middle. | Baseline | yes | RUI (mixed font sizes) | guideline |

### E. Origin, family and history

| # | Rule | Measurable property | In font file? | Source and place | Strength |
|---|---|---|---|---|---|
| R38 | Same family first. Serif, sans, slab, script and mono siblings share a skeleton and metrics. They are the safest pairs. | Family or superfamily match | partly | STO pp.40-41; LAT; TWC 68 | rule |
| R39 | Same designer next. Same foundry after that. Raises odds, no guarantee. Latin says author and foundry pairs work as uniform only. | Designer or foundry name | partly | STO p.43; LAT ch.5; TWC 71 (Perpetua with Gill Sans, Palatino with Optima) | shortcut |
| R40 | You do not have to take the superfamily partner. Most sans in superfamilies are humanist. | Sibling class | partly | TWC 68 (tips) | caveat |
| R41 | History works two ways. Far apart (contrast) or same period (harmony). Latin: works best with pre-digital faces. Mayer: same period, and better if the same designer. | Year of release | no | LAT ch.5 "Based on history"; LCS; MAY p.136 | guideline |
| R42 | Shared period is not enough once faces are post-digital. Too many new faces exist. | Year | no | LAT ch.5; LCS | guideline |

### F. Personality and role

| # | Rule | Measurable property | In font file? | Source and place | Strength |
|---|---|---|---|---|---|
| R43 | Do not mix moods. Pairs read as a scene. Futura Bold with Souvenir works because both are wide, circular, high-x-height and a little quirky. Franklin Gothic Bold with Souvenir reads as a stern guard ignoring a child. | Width, roundness, x-height (proxies only) | partly | BON pp.150-151 | rule |
| R44 | Pair one distinctive face with a neutral foil. | Contrast, apertures, quirk (proxies) | partly | BON p.152; TWG Adobe #2, #8 | rule |
| R45 | Loud display faces go in small doses. | Display flag | partly | MAY p.139 (Pink Belt Principle) | rule |
| R46 | Match face character to the job. A poster can carry character. A hard document needs a stable face. | None | no | DUG ch.9 | guideline |
| R47 | Basic UI components get neutral faces: high x-height, open apertures, low contrast. Expressive components can use character and higher contrast. | Stroke contrast, x-height | yes | EDS ch.3 | guideline |
| R48 | In a UI the safest base is a neutral sans. Favor families with five or more weights. A short-x-height condensed face fails at small UI sizes. | Weight count, x-height | yes | RUI pp.108-111 | guideline |
| R49 | Brand parts must look like one hand. A random font beside a custom mark reads as strangers. | Designer match | no | LTL (brand elements) | guideline |
| R50 | Headings are the easiest place to take a risk. Survey data showed designers used alternative faces far more in headings than body. | None | no | SM6 survey p.109 (dated survey) | weak, descriptive |

### G. Optical sizes, mono and style coverage

| # | Rule | Measurable property | In font file? | Source and place | Strength |
|---|---|---|---|---|---|
| R51 | Use the display cut for headlines. Never set body in a display cut. Swap to the text cut for headlines on small screens. | Name keyword, stroke contrast, spacing | partly | TWC 21, 52, 90; REY pp.33-34 | rule |
| R52 | A display and text cut of one family harmonize by design. Swapped, the caption cut looks clumsy large and the display cut looks thin small. | Optical-size siblings | partly | REY p.34 (Garamond Premier Display and Caption); TWC 70 (tips) | rule |
| R53 | Small text is its own job. Choose a face with looser spacing and higher x-height, or an optical-size cut. | Spacing, x-height | yes | BRO ch.5 | guideline |
| R54 | A mono is a valid complement, often in the same family (Fira Sans with Fira Mono for captions). Do not set long text in mono. | Mono flag, tabular figures | yes | STO p.46; TWC 22, 40 | guideline |
| R55 | The partner must ship regular, italic, bold and bold italic, with true italics. Obliques blend in and defeat the point of italic. | Style list, italic flag | yes | TWC 18, 19, 36; STO (italic principle); TWG Google #5 (Source Serif Pro ruled out as body for no italics) | rule |
| R56 | Check glyph and language coverage before pairing. A missing glyph falls back to another font and looks jarring. Check licence for the partner at the start, not the end. | Cmap coverage | yes | STO pp.46-47 and Licensing principle; BRO ch.3 | rule |

---

## 3. Failure rules

What breaks a pair, with the example the author used.

| # | What fails | Example and verdict | Source |
|---|---|---|---|
| F1 | The middle. Similar enough to notice, different enough to look wrong. | FF Meta with Camingodos (on the fence: too like the body to contrast). Proxima Nova with Freight Sans. Meta with PT Sans. | LAT ch.5; TWC 72; STO p.47 |
| F2 | Two sans with different personalities. | Trade Gothic Bold No.2 with Bell Gothic. Futura with Helvetica. Franklin Gothic with Helvetica. | BON p.144; TWC 69; MAY |
| F3 | Two serifs of the same class. | Caslon with Baskerville. Clarendon Bold with Officina Serif (slab with slab). | TWC 70 (Santa Maria); BON p.145 |
| F4 | Mixing two aesthetics. | Geometric sans with Old Style serif. Modern serif with Old Style serif. Geometric sans with humanist sans. | TWC 69, 70, 74 |
| F5 | Mismatched mood. | Franklin Gothic Bold with Souvenir. Dax Bold with Bernhard Modern (narrow and tall-x against wide and low-x, and tech against quiet). | BON pp.150-153 |
| F6 | Too far apart. | Antique Olive Nord with Garamond Narrow. | BON p.153 |
| F7 | Weight inversion. | Myriad Light over Minion Bold. | BON p.148 |
| F8 | Same point size, different x-height. | Merriweather and Mrs Eaves both at 21 px with line height 1.5. One looks huge, one tiny. | TWC 82; STO p.45 |
| F9 | A display cut in a text role, or a text cut in a display role. | Playfair Display for body. Garamond Premier Display and Caption swapped. | TWC 21; REY p.34 |
| F10 | Overusing the loud face. | Sho on every line of a Thai menu. | MAY p.140 |
| F11 | Clashing textures. | Azo Sans subheads on Open Sans text ("clunky"). Quatro: w and y stand out badly. FF Enzo: humanist, wrong for the brief. JAF Facit: no reason given. | BRO ch.6 Fig 6.33; LAT ch.5 |
| F12 | Missing italic, bold or bold italic. Faux styles follow. | Source Serif Pro (no italic at the time) ruled out for body. | TWC 18, 36; TWG Google #5 |
| F13 | Contrasting proportions across the palette. | Palette feels agitated and discordant. | BRO ch.3 |
| F14 | Slab serifs fight for dominance. | Slab beside slab. Slab described as horn-rimmed glasses, conspicuous in the wrong place. | BON p.145; MAY p.133 |
| F15 | A neo-grotesque as the only UI face where I, l and 1 look alike. | Helvetica. Prefer a humanist sans. | TWC 80 |
| F16 | Condensed face in body or main UI text. | Short-x-height condensed. | TWC 81; RUI p.111 |
| F17 | Mono for long text. | Awkward spacing, slow reading. | TWC 22 |
| F18 | Faces with few weights. Often poorly built. | Under five styles. | RUI p.110 |
| F19 | Poor kerning in the partner. | Test with the word WAVES. | TWC 84 |
| F20 | Display face on small screens. | Letters break apart. | TWC 52 |
| F21 | Two similar sans from a layout that needs contrast, when serif is available. | Almost any serif looks better beside Futura than a second sans does. | TWC 69 |
| F22 | Unplanned dissonance. | Dissonance is fine only as design intent. | STO p.47 |
| F23 | A tiny difference between roles reads as noise. | A barely noticeable change makes the reader ask why it changed. | STO p.47 |

---

## 4. Named pairs

Verdict key: **+** praised, **-** criticised, **~** shown with no verdict or mixed. Weight key: **argued** = the author gives a reason. **shown** = pair shown, no reasoning. Second-hand verdicts are marked.

### 4a. Argued pairs

| # | A | B | Roles | Verdict | Weight | Source |
|---|---|---|---|---|---|---|
| P1 | Futura (caps) | Baskerville | A heads, B body | + | argued (history contrast, matching x-height) | LAT ch.5; LCS |
| P2 | Merriweather Sans | Adobe Garamond Pro | not stated | ~ (x-height contrast example) | shown | LCS |
| P3 | DIN Alternate | Helvetica | not stated | ~ (history harmony example) | shown | LCS |
| P4 | Univers | Apollo | not stated | + (same author, Frutiger) | argued | LAT ch.5; LCS |
| P5 | Viato | Plume | not stated | + (same foundry, Dalton Maag) | shown | LCS |
| P6 | Merriweather | Merriweather Sans | body / companion | + | argued (superfamily) | LAT; LCS; TWG Google #7 |
| P7 | Roboto | Roboto Slab | body / companion | + | argued (shared g skeleton) | LAT; LCS; TWG Google #10 |
| P8 | FF Tisa | FF Tisa Sans | body / companion | + | shown | LCS; TWC 68 |
| P9 | FF Meta | Korolev | A body, B headings | + (clear winner) | argued (narrow, large x-height, medium weight gives full contrast) | LAT ch.5 |
| P10 | FF Meta | Camingodos | body / headings | - (on the fence) | argued | LAT ch.5 |
| P11 | FF Meta | Quatro | body / headings | - | argued (w, y stand out) | LAT ch.5 |
| P12 | FF Meta | FF Enzo | body / headings | - | argued (humanist, wrong brief) | LAT ch.5 |
| P13 | FF Meta | JAF Facit | body / headings | - | argued weakly (felt wrong, no reason given) | LAT ch.5 |
| P14 | Source Sans (Pro) | Modesto Expanded | body / display | + (closest match) | argued (proportion, rhythm, energy) | BRO ch.3 Fig 3.24-3.26 |
| P15 | Source Sans (Pro) | FF Ernestine | body / display | + (also fine) | argued (matching vertical proportions, contrasting width) | BRO ch.3 Fig 3.26 |
| P16 | Source Sans (Pro) | Brothers | body / display | - (less like Source Sans) | argued (rhythm) | BRO ch.3 Fig 3.25 |
| P17 | Open Sans | Azo Sans | text / subheads | - (clunky textures) | argued | BRO ch.6 Fig 6.33 |
| P18 | Open Sans | Open Sans Bold | text / subheads | ~ (acceptable, boring) | argued | BRO ch.6 Fig 6.33 |
| P19 | Open Sans | Abril Text | text / subheads | + (more interesting) | argued | BRO ch.6 Fig 6.33 |
| P20 | Caslon | Baskerville | serif with serif | - | argued (second-hand, Santa Maria) | TWC 70 |
| P21 | Freight Display | Freight Text | display / text | + | argued (same family) | TWC 70, 90 |
| P22 | Futura | Bodoni | sans / serif | + (classic) | argued (constructed, vertical stress) | TWC 73, 74 |
| P23 | Futura | Garamond | sans / serif | - (less harmonious than Bodoni) | argued | TWC 73 |
| P24 | Futura | Helvetica | sans / sans | - | argued | TWC 69 |
| P25 | Futura | Proxima Nova or Avenir | head / body | + (only if sans body is needed) | argued | TWC 69 |
| P26 | Proxima Nova | Freight Sans | neither | - | argued | TWC 72 |
| P27 | Perpetua | Gill Sans | serif / sans | + | argued (same designer) | TWC 71 |
| P28 | Palatino | Optima | serif / sans | + | argued (same designer) | TWC 71 |
| P29 | Helvetica | Bembo | sans / serif | + | argued (author says there is no real explanation) | MAY p.135 |
| P30 | Franklin Gothic | Helvetica | sans / sans | - | argued | MAY p.134 |
| P31 | Trade Gothic Bold No.2 | Bell Gothic | head / body | - | argued (personality clash) | BON p.143-144 |
| P32 | Trade Gothic | Sabon | head / body | + | argued (tall x-height, same mission) | BON p.144 |
| P33 | Clarendon Bold | Officina Serif | head / body | - | argued (slab with slab) | BON p.145 |
| P34 | Clarendon Bold | New Baskerville | head / body | + | argued (neutral partner) | BON p.146 |
| P35 | Akzidenz Grotesk (bold caps and medium) | Rockwell Bold and Bembo | slug and subhead / headline and body | + | argued (fixed roles) | BON p.146-147 |
| P36 | Myriad Light | Minion Bold | head / body | - | argued (weight inversion) | BON p.148 |
| P37 | Myriad Black | Minion (regular) | head / body | + (heavy-handed but clear) | argued | BON p.149 |
| P38 | Franklin Gothic Bold | Souvenir | head / body | - | argued (mood clash) | BON p.150 |
| P39 | Futura Bold | Souvenir | head / body | + | argued (wide, circular, tall x-height) | BON p.151 |
| P40 | Dax Bold | Bernhard Modern | head / body | - | argued | BON p.152-153 |
| P41 | Dax Bold | Caslon | head / body | + | argued (neutral foil) | BON p.153 |
| P42 | Antique Olive Nord | Garamond Narrow | head / body | - | argued (too far apart) | BON p.153-154 |
| P43 | Antique Olive Bold | Chaparral | head / body | + | argued (higher x-height, more neutral) | BON p.154 |
| P44 | Helvetica Neue (3 fonts) | Garamond (2 fonts) | head / body | + | argued (two families, five fonts) | BON p.155-156 |
| P45 | TheMix Italic | New Century Schoolbook | head / body | + (after size change) | argued | BON p.157 |
| P46 | Sho | neutral text face | display / text | - if on every line | argued | MAY p.139-141 |
| P47 | Garamond Premier Display | Garamond Premier Caption | head / text | + (swapped = -) | argued | REY p.33-34 |
| P48 | Degular | Swear | heading / emphasized words | + | argued (same designer, size-matched) | STO p.45 |
| P49 | Meta | Meta Serif | heading / paragraph | + | argued (shared skeleton, serif vs sans) | STO p.47 |
| P50 | Meta | PT Sans | heading / paragraph | - | argued (not different enough) | STO p.47 |
| P51 | Meta | Rollerscript | heading / paragraph | + (very deliberate contrast) | argued | STO p.47 |
| P52 | Fira Sans | Fira Mono | body / captions | + | argued | STO p.46 |
| P53 | Quatro Slab, Decoy, Hatch, Neighbor (Mark Caneso) | each other | not stated | + (same metrics, logical pairs) | argued | STO p.43 |
| P54 | Franklin Gothic (condensed) | Caslon | head / body | + | argued | TWG Adobe #1 |
| P55 | Brandon Grotesque | Abril Text | head / body | + | argued | TWG Adobe #2 |
| P56 | SchoolBook | Adelle Sans | not stated | + | argued (short descenders, wide) | TWG Adobe #3 |
| P57 | Lapture Display | Freight Sans | not stated | + | argued (shared g skeleton) | TWG Adobe #4 |
| P58 | Futura | Kepler | head / body | + | argued (geometric with Modern serif) | TWG Adobe #5 |
| P59 | Freight Display | Sofia Soft | head / not stated | + | argued (vertical stress, rounded terminals contrast) | TWG Adobe #6 |
| P60 | Proxima Nova | Chaparral | not stated | + | argued (shared a, open apertures, x-height) | TWG Adobe #7 |
| P61 | P22 Underground | Freight Text | not stated | + | argued (large x-height, low contrast) | TWG Adobe #8 |
| P62 | Tablet Gothic (Semi Condensed) | Adobe Text | not stated | + | argued (width match) | TWG Adobe #9 |
| P63 | Soleil | FF Tisa | not stated | + | argued (x-height, apertures) | TWG Adobe #10 |
| P64 | Playfair Display | Fira Sans | head / body | + | argued (short descenders, large x-height) | TWG Google #1 |
| P65 | Domine | Open Sans | not stated | + | argued (shared g, large x-heights) | TWG Google #2 |
| P66 | Alegreya Sans | Alegreya | body / companion | + | argued (same skeleton) | TWG Google #3 |
| P67 | Montserrat | Arvo | sans / slab | + | argued (geometric, stout) | TWG Google #4 |
| P68 | Source Serif Pro | Source Sans Pro | head / body | + | argued (same condensed proportions) | TWG Google #5 |
| P69 | Neuton | Lato | not stated | + | argued (large apertures) | TWG Google #6 |
| P70 | Rosario | Crimson Text | not stated | + | argued (humanist pen) | TWG Google #8 |
| P71 | Varela Round | Lora | not stated | + | argued (warm, ball and rounded terminals) | TWG Google #9 |
| P72 | Mrs Eaves | Mr Eaves Sans / Mr Eaves Modern | body / companion | + | argued (humanist and geometric siblings) | TWC 68 |
| P73 | Knockout | Tisa or Proxima Nova | head / body and microcopy | + | argued (match face to role) | UXP-A (about p.67) |
| P74 | Meridian | Geometric (caps) | not stated | ~ (size note: the sans sets larger than the serif) | shown | TON |

### 4b. Shown only (no stated reason)

| # | A | B | Roles | Verdict | Source |
|---|---|---|---|---|---|
| P75 | Baskerville | Georgia | head / body | ~ (Jon Tan's site, two serifs) | SM6 survey pp.108-109 |
| P76 | Rubik | Roboto Mono | head / data or captions | ~ | GFC |
| P77 | Univers Ultra Condensed | Minion Pro | headline / body | + (go-to) | NLE p.38 |
| P78 | Univers Ultra Condensed | Chronicle Text | title / body | + | NLE p.40, 43 |
| P79 | Interstate Bold | Courier | headline / body | + | NLE p.41 |
| P80 | Gotham Black | Chronicle Text | headline / body | + | NLE p.44, 89 |
| P81 | Chronicle Display | Gotham | title / body | + | NLE p.46 |
| P82 | Futura Heavy | Minion Pro | headline / body | + | NLE p.47 |
| P83 | Futura | Acta | titles / body | + | NLE p.49 |
| P84 | Gill Sans Bold | Minion Pro | headline / body | + | NLE p.50 |
| P85 | Miller Display | Gill Sans | title / body | + | NLE p.52 |
| P86 | DIN | Freight Text | headline / body | + | NLE p.59 |
| P87 | Canela | Avant Garde | headline / body | + | NLE p.64 |
| P88 | Frutiger Bold | Minion Pro | headline / body | + | NLE p.65 |
| P89 | Univers Condensed, Knowledge, Avenir Next | (three faces) | title, subtitles and links, body | + | NLE p.79 |
| P90 | Tiempos Headline | Gill Sans, Miller | title / subtitles | + | NLE p.92 |
| P91 | Clarendon | Theinhardt | title / body | + | NLE p.98 |
| P92 | Acta | Oswald | title / subtitles | + | NLE p.104 |
| P93 | Garamond | Knowledge | title / subtitles | + | NLE p.107 |
| P94 | Optima | GT America | titles / subtitles | + | NLE p.113 |
| P95 | Freight | Univers Condensed | titles / subtitles | + | NLE p.116 |
| P96 | Rockwell | Univers | titles / subtitles | + | NLE p.122 |
| P97 | Helvetica | Caslon | titles / body | + | NLE p.128 |
| P98 | Brown | Baskerville | titles / body | + | NLE p.131 |
| P99 | Timmons NY | Freight | titles / body | + | NLE p.137 |
| P100 | Freight Sans Bold | Proxima Nova | headline / subtitle and button | + (recommended) | RFR |
| P101 | Futura Bold | Trade Gothic Next | headline / subtitle and button | + | RFR |
| P102 | Harmonia Sans Black | Graphik | headline / subtitle and button | + | RFR |
| P103 | Meta Serif Bold | Myriad Pro | headline / subtitle and button | + | RFR |
| P104 | Jubilat Semibold | Proxima Nova | headline / subtitle and button | + | RFR |
| P105 | Adelle Extra Bold | Proxima Nova | headline / subtitle and button | + | RFR |

RFR also lists five single-family sets (Proxima Nova, Graphik, Roboto, Interstate, Neue Plak). They are weight pairs, not family pairs, so they are not counted.

### 4c. Superfamily pairs named (shown only)

| # | A | B | Source |
|---|---|---|---|
| P106 | Calluna | Calluna Sans | TWC 68 |
| P107 | Freight Text | Freight Sans | TWC 68, TWG |
| P108 | Adelle | Adelle Sans | TWC 68 |
| P109 | ITC Officina Serif | ITC Officina Sans | TWC 68 |
| P110 | FF Scala | FF Scala Sans | TWC 68 |
| P111 | Fedra Serif | Fedra Sans | TWC 68 |
| P112 | PT Serif | PT Sans | TWC 68 |
| P113 | Droid Serif | Droid Sans | TWC 68 |
| P114 | DM Serif | DM Sans | TWC 68 |
| P115 | Tabac | Tabac Slab | STO p.42 |
| P116 | Recursive (sans) | Recursive (mono) | STO p.46 |
| P117 | Mrs Eaves | Mr Eaves Sans (also counted in P72) | TWC 68 |

---

## 5. Gaps vs the skill

Columns: **Skill** = in `references/pairing.md` or `SKILL.md`. **Engine** = in `docs/pairing-score.md`.

### 5a. In the books, missing from the skill

| # | Gap | Skill | Engine | Note |
|---|---|---|---|---|
| G1 | Kupferschmid matrix: skeleton, flesh, skin. Same skeleton harmonizes. Opposite on both works. Same flesh fails. (R19) | no | **yes** (base score 90 / 75 / 0) | Not a new finding for the engine. New for the skill. |
| G2 | Handwritten versus constructed as one harmony axis. Geometric and Rational (Modern) group together. (R20) | no | partly. Engine splits geometric and rational into different skeletons, so Futura with Bodoni scores "bold" (75), not "same DNA" (90). | TWC calls that pair harmonious. Test case for the engine. Note: `pairing-score.md` lists Bodoni and Helvetica as rational in its skeleton definitions, but its same-flesh examples call them geometric. Whether Futura with Bodoni scores 75 or 90 depends on which part of that doc is right. |
| G3 | Genre pair table and avoid-list (R21, R22) | no | no | Needs class tags. Engine has skeleton, serif and contrast only. |
| G4 | Too much contrast also fails (R14, F6) | no | no | Engine rewards bigger weight and width gaps. It never caps them. |
| G5 | Mood and personality are pairing criteria (R43-R46) | **no, and the skill sends mood to the brand layer** | no | Four sources treat it as part of pairing. Proxies in the file: width, x-height, roundness, contrast. |
| G6 | Weight gap between roles; heading must outweigh body (R33, F7) | no | yes (400 with 700+ gets +3) | Conflicts with R34. See section 7. |
| G7 | Size compensation from the x-height ratio (R28) | yes (em box note) | no | Engine could output a size factor beside each match. |
| G8 | Mono as a complement (R54) | yes (counts as third face) | **opposite**: Mono with any non-mono gets -5 | Sources support mono as a pair. |
| G9 | Width or a width axis instead of a second family (R32) | no | partly (condensed with normal +4, both variable +2) | Adobe #9 matches width instead of contrasting it. |
| G10 | Optical sizes: display cut for heads, text cut for body, swap on small screens (R51-R53) | no | yes (Display with Text +8, Display with Caption +5) | Small-screen swap is not modeled. |
| G11 | Ask whether a second face is needed at all (R1) | no (says "two is the default") | no. The engine always pairs. | A "stay with one family" outcome is missing. |
| G12 | Brown's six jobs. The skill lists five and has no small-text job. (R8, R53) | partly | partly (Caption role) | Skill drops small text and tabular and technical as separate jobs. |
| G13 | Role sets the target. Display stands out, UI is clearer, supporting text recedes. (R9) | no | no | |
| G14 | Shared glyph details (g, a, k, c, R leg) (R23) | no | no | Engine skeleton is coarse. A glyph-level similarity score is missing. |
| G15 | Terminal style: rounded or sharp, match or contrast (R25) | no | no | |
| G16 | Partner needs true italics and four styles; avoid faces under five styles (R55, R48) | no (skill only checks licence weights) | partly (weight range) | Italic availability is not scored. |
| G17 | x-height contrast as a deliberate option (R27) | **dropped** | no (rewards proximity only) | |
| G18 | Contrast level should follow layout complexity (R18) | no | no | |
| G19 | Do not over-research the partner (lock-in) (R4) | partly ("cast wide and shallow") | n/a | Skill lacks the lock-in reason. |
| G20 | Time-box and sleep on it (R6) | no | n/a | |
| G21 | Fonts In Use as precedent (R7) | partly (Eagle refs) | n/a | |
| G22 | Dissonance on purpose (R17) | no | no | Caveat, low priority. |
| G23 | Quality screen: kerning present, five or more weights (F18, F19) | no | no | |
| G24 | Language and licence checked at pair time (R56) | licence yes | n/a | |

### 5b. Where the skill says more than its source

1. **"Based on proportions" is not a Latin lens.** Latin has no such heading. Proportions appear inside "Based on author" (the Apollo with Univers figure). The skill promoted a sub-note to a lens.
2. **"Adjacent-but-different periods usually do not work" has no source.** Latin says far apart and same period both work, and that history works best for pre-digital faces. Typewolf gives the nearest support (do not mix Modern with Old Style serifs) and that is a bad case of far-apart periods, not adjacent ones.
3. **x-height is stated as the most useful lens and mismatch as "the usual cause".** Latin's cheat sheet says x-height harmony only reinforces a pair and is not definitive. It also allows a deliberate x-height contrast (Merriweather Sans with Adobe Garamond Pro). The skill drops that option. Counting TWG, only 7 of its 20 pairs cite x-height at all.
4. **Superfamily as "least distinctive, usually wrong for brand work" is a workspace rule.** Latin, Stocks and Typewolf rank superfamily first and never attach a brand warning. Label the warning as Dyno policy.
5. **"Two faces that look great as specimens routinely fail in a real layout."** Latin only says to test in the browser, in context. "Routinely fail" is the skill's addition.
6. **"Two faces is the default. Mono usually counts as a third."** TWC allows three or more for experienced designers. Bonneville runs three families. Brown wants a big palette. Stocks treats mono as a family member (Fira Mono), not a third face.
7. **The skill puts brand fit outside pairing.** Mayer, Bonneville, Brown and Dugonjic fold mood and personality into pairing.

### 5c. Where the engine and the sources differ

- Mono with any non-mono gets -5. Stocks, Typewolf and four shown pairs treat mono as a complement.
- x-height scoring rewards only closeness. Latin allows clear contrast and warns against the middle.
- Same foundry gets +4 whatever the class. Latin says foundry and author pairs work as uniform only.
- Geometric with Rational (Futura with Bodoni) scores as "bold". Typewolf calls it harmony.
- Weight contrast always scores up. Typewolf (Bringhurst) says heads should get lighter as they get larger.

---

## 6. What agrees

- The middle fails: Latin, Mayer, Typewolf and Stocks all say it. This is the strongest consensus in the library.
- Serif with sans is the easiest route: Latin, Bonneville, Typewolf, Mayer.
- Same family or same designer first: Stocks, Latin, Typewolf.
- Same font-size number does not give the same visual size, so compensate: Stocks, Typewolf, Brown.
- Display and text cuts are different jobs: Typewolf, Reynolds, Brown.

---

## 7. Disagreements

1. **Palette size.** Latin, Typewolf, Mayer and Bonneville default to two faces. Brown says keep a big palette and do not cut until you are composing. Typewolf adds that experienced designers use more. Bonneville shows five fonts from two families and four from three.
2. **Sans with sans.** Typewolf: do not. Latin: hard, so go very similar or very different. Mayer: two geometric sans worked once for him. Bonneville: avoid same class from different families. Refactoring UI and the Playbook use sans-only sets in UI work. Context is the likely discriminator. Editorial work argues for contrast. UI work argues for one neutral family.
3. **Serif with serif.** Typewolf: do not (Caslon with Baskerville). The survey shows Jon Tan's Baskerville and Georgia in use. The Playbook shows Tiempos Headline with Miller in use. Typewolf allows same-family serifs (Freight Display with Freight Text).
4. **Same-skeleton pairs.** Stocks (Kupferschmid): same skeleton is harmonious. The engine demotes same skeleton plus same flesh by 25. Typewolf says same-genre sans is the fallback when two sans are needed. Three positions on one case.
5. **x-height match.** Latin's cheat sheet: reinforces, not definitive, and contrast is also valid. Stocks: any mismatch can be fixed by resizing, so it should not disqualify. Bonneville: matched tall x-heights explain Sabon with Trade Gothic and Futura Bold with Souvenir. Typewolf: 7 of 20 pairs cite it, mostly "both large". Brown: palette x-height is not a test at all, only body size is.
6. **Weight direction.** Bonneville: heading must outweigh body (Myriad Light over Minion Bold fails). Typewolf with Bringhurst: weight should fall slightly as size rises. Latin: a slightly lighter weight made Korolev read as clear contrast. Refactoring UI: two weights only in UI (400 or 500, and 600 or 700).
7. **Geometric sans with Old Style serif.** Typewolf: avoid. Latin: Futura with Baskerville is the lead example, but Baskerville is Transitional, so it does not break Typewolf's rule. The Playbook pairs Futura Heavy with Minion Pro, an Old Style leaning face. Treat Typewolf's rule as guideline strength.
8. **History.** Latin: far apart works (Futura with Baskerville, 200 years). Typewolf: Modern with Old Style serifs "almost always looks bad", though they are 300 years apart. Mayer: same period is more likely to work.
9. **Heading and body direction.** Bonneville: sans heading with serif body is close to impossible to get wrong. Typewolf 77, 78: serif heading with humanist or neo-humanist sans body is fine. Latin's worked example uses sans heads. The 2009-era survey saw sans heads as the majority.

---

## 8. Counts

- Sources with usable pairing content: **19** (LAT, LCS, LCL, BRO, STO, TWC, TWG, SM6, DUG, REY, NLE, RUI, RFR, TON, EDS, LTL, UXP-A, GFC, SAM). About ten more typography files were checked and had none.
- Rules: **56** (R1 to R56).
- Failure rules: **23** (F1 to F23).
- Named pairs: **117** rows (P1 to P117). P117 repeats P72, so 116 are distinct. By table: 74 in the "argued" table (5 of those are marked shown), 31 shown-only, 12 superfamily pairs.
