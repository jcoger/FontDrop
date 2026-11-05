> **Update 2026-11-05, after Jarrett read this:** Decision 1 is decided (Set owns the dial). Decisions 2 to 7 are accepted. The job "Reading" is renamed **Text** (lexicon 17), so read "Reading" below as the Text job. A third face is after v1 (ship plan v2).

# IA SPEC: FontDrop Mac app · macOS · 2026-11-05 · UNTESTED

**Ask:** Continue the 2026-10-12 IA spec against the Mac app and the new Paper boards. Check label collisions, the v1 sidebar, the inspector modules, and every door.
**Audited:** worktree `.claude/worktrees/agent-ab9e856df81904fef`, branch `swiftui-basics-vf` @ `567688a` (PR #17, the stack tip). `main` still holds only the Tauri app and there are no external users, so this tip is what the first user will hold. Read-only. Next release read: `docs/plans/2026-11-04-ship-plan.md` (R1 to R6). Boards read: 03, 04, 12, 14 plus the design review.
**Ledger:** top-level destinations +0 / -4 (UI, Mono, Colors, Saved row) · nav structures +0 · screens +0 (Set exists as a placeholder) · doors +1 (Export menu, replaces a disabled button) · Reading inspector sections 5 → 3 (Scale and the Display playground leave; the shortlist list leaves) · labels renamed 6. **The proposal removes more than it adds.**

**Decisions for Jarrett** (each with a default; none is built):
1. **Where does Scale live?** It has two homes today: Reading inspector module 01 and the Set inspector (board 04). The Reading one edits a brand value under a candidate's header. **Default: Scale is edited in Set only. Reading keeps one quiet readout line ("Body 15 pt · Fit") that opens Set.** Cost: you cannot turn the dial while flipping body faces. This reverses lexicon 14.1 (see section 7).
2. **v1 sidebar: Brand switcher · Display · Reading · Set.** Board 14 shows UI, Mono, a Saved row, and Set under Library. Board 04 shows only Display, Reading, Set. **Default: board 04.** UI and Mono hidden (your D4 default), Saved row back in the Display filter bar (UX audit S2), Colors row gone (S4). Set sits with Display and Reading, not under Library.
3. **"Fit" means two things on one screen** (stage zoom, and the scale mode on the dial). **Default: zoom keeps "Fit" (platform word). The scale mode becomes "Auto".** Needs a first-click test.
4. **"Letters" means three things.** **Default: "Letters" names only the glyph tile strip.** The alternates tiles on Display become "Alternates". The OpenType group "Letters" becomes "Small caps and ligatures". The Face row "Letters and spacing" becomes "Spacing and features".
5. **One word for the face you picked: "Current".** Display's "Chosen" tag becomes "Current". Board 03 changes. **Default: Current** (4 uses vs 1).
6. **Export or Hand off?** One concept, two words, and "Handoff" is also a macOS feature name. **Default: the button and menu say "Export". The plans keep "Hand-off" as the round name only.**
7. **Drop the "Saved to Acme" line** on board 04 and the Colors popover. It collides with Saved (the star). **Default: drop it.** A Mac app autosaves and does not announce it.
8. **Launch lands where the brand left off,** not always on Display. **Default: yes, last screen per brand.**

**The big picture:** The structure is sound. Brand is a real scope object now: choices and shortlists are keyed by `brand_id` in the database. The risk now is not the tree. It is that the new boards re-open three settled calls without naming them (Saved row, UI and Mono, Scale's home), and that "Scale" is edited in two places. The risk from the roadmap is the Brand itself. Its type system lives in four stores (database plus three JSON files). R4 Export must read all four. The future connector cannot read three of them. A brand delete exists in the core with no screen, and it would leave the JSON behind and let a new brand inherit it (finding 3).

---

## 1. Needs and top tasks

User: a brand designer picking a type pair for one client. Same as 2026-10-12, now with the loop in the ship plan.

| # | Task | Need |
|---|---|---|
| T1 | Pick a Display face from my own fonts | Exploratory |
| T2 | Find Reading faces for it, or start from a body face and find the Display | Exploratory |
| T3 | Compare 2 or 3 candidates in a real layout | Re-finding (shortlist) |
| T4 | Set body size and ratio for the pair | Known-item |
| T5 | Take the pair to my client and into my design file | Known-item |
| T6 | Switch to another client's brand and find where I left off | Re-finding |
| T7 | Hide junk, bring one back, see what I starred | Re-finding |

Mixed. T1, T2 are browse. T4, T5 are known-item and need exact lists. T6, T7 are re-finding and need stable names.

## 2. Objects

| Object (UI) | Code | Instances | Lives in | Name source |
|---|---|---|---|---|
| **Brand** (scope) | `brands` row | 1 to a few | DB | team |
| **Family** | `FamilySummary` | 688 on the sample library | DB (fonts) | team |
| **Job** (Display, Reading; UI and Mono hidden) | `job` text | 2 live, 2 parked | DB | team |
| **Current face** (per brand, per job) | `choices` | 1 per job | DB | team |
| **Shortlist** (per brand, per job) | `shortlist` | 0 to ~10 | DB | team |
| **Saved** (star, global) | `favorites` | many | DB | team |
| **Hidden** (global) | `hidden` | few | DB | team |
| **Face settings** (style, axes, trim; per brand, job, family) | `TypeSettings` | many | `<db>.playground.json` | team |
| **Scale** (body, ratio, lock; per brand) | `TypeScale` | 1 | `<db>.scale.json` | team |
| **Colors** (3 colors; per brand) | `BrandStyleStore` | 1 | `<db>.colors.json` | team |
| **Candidate** (a Reading option) | `Candidate` | ~37 per list | computed | team |
| **Logo** | `brands.logo_svg` | 0 | DB column, no UI | team |

Set aside: lens (Difference, Structure, Foundry, Sort) is a filter, not an object. Template and layout are view settings.

**Scope rule, stated once:** everything under *Brand* is per brand. *Saved* and *Hidden* are global, like the font library. The sidebar should show that split: the Brand switcher on top scopes the Type group; Saved and Hidden are not Type rows.

| Object | Verbs | Where the verb lives |
|---|---|---|
| Current face | Use, Clear, Undo | Stage bar (Reading), inspector button (Display), Type menu |
| Shortlist | Add, Remove, Compare | Stage bar |
| Saved | Star, Unstar | Card star, filter chip |
| Hidden | Hide, Unhide | Card menu, More menu |
| Scale | Lock, Release, set Body, set Ratio | Reading inspector today. **Set, per decision 1** |
| Brand | Create, Rename, **Delete (core only)**, Switch | Sidebar. Delete has no screen |
| Export | Copy CSS, Copy Tailwind, Spec page, License list | **None yet** (button disabled) |

Every status has a verb that sets it. "Current" is set by Use and cleared by Clear. Nothing is a dead state. Delete is a verb with no door.

## 3. Homes

| Object | Home (one per role) | Status |
|---|---|---|
| Family | Display grid row; Reading list row; inspector | OK. One detail surface per job |
| Current face | Sidebar row under each job (name in the face) | OK |
| Shortlist | Stage bar toggle + list tag. Code also lists it in the Reading inspector | **Two homes in code.** Board 14 drops the inspector list. Follow the board |
| **Scale** | **Reading inspector 01 and Set inspector** | **Two homes. Decision 1** |
| Face settings | Playground in the inspector (Display and Reading) | OK |
| Colors | Stage "Colors" popover | OK. Sidebar "Colors · Parked" row is a second, dead name for it |
| Saved | Filter bar chip, sidebar row | Two doors to one filter. Decision 2 |

List orders (read from code, not changed): Display grid by name with your fonts first; Reading by Best match with Current pinned on top; shortlist by added date.

## 4. Navigation

Mac window: sidebar, content, inspector. No tab bar, no phone target in this plan. Sidebar budget is fine at any count; the problem is meaning, not count.

| | Today (code) | Boards 03/04 | Board 14 | Proposed v1 |
|---|---|---|---|---|
| Group 1 | Brands (list + "+") | Brand row | Brands | Brand switcher |
| Type | Display, Reading, UI, Mono | Display, Reading, Set | Display, Reading, UI, Mono | **Display, Reading, Set** |
| Library | Saved | Saved | Saved, Set | none (Saved is a filter) |
| Other | Set; Colors (disabled, "Parked") | | | none |
| Rows | 7 | 4 | 7 | **3** |

Order matches the loop: Display, Reading, Set. Keyboard: ⌘1, ⌘2, ⌘3 map to them (UX audit section 5). That mapping only stays clean if UI and Mono are hidden (D4). Export is an action in the toolbar, not a destination.

The loop also runs backward (Reading first is allowed, UX audit U6). The sidebar order is a default, not a gate.

## 5. Doors

| Door | Opens | State | Lands cold? |
|---|---|---|---|
| Launch | Display, last brand restored (`lastBrand`), single window | live | Yes. Always Display, even with a pair chosen |
| Sidebar rows | each screen | live | Yes |
| "Find a Reading face →" (Display inspector) | Reading | live | Yes |
| "Next: sizes and spacing" (Reading stage) | Set | live | **No until R3.** Set says "Coming next. This is a plain specimen" |
| "Find a Display face" (Reading, no Display) | Display | live | Yes |
| Menu bar | one menu: Type (Clear Display face, Clear Reading face, Undo). New Item removed on purpose (one window) | live | n/a |
| Keys | ↑ ↓ flip candidates; ⌘− ⌘0 ⌘= ⌘+ stage zoom; Return and Esc in sheets | live | n/a |
| Search | `.searchable` in the toolbar. ⌘F not verified in the running app | live | Yes |
| Export button | nothing (disabled, "arrives in a later wave") | dead | **No. Dead end** |
| Foundry / license link | outside the app (`DisplayView.swift:231`) | live | n/a |
| URL scheme, document types, font-file open, drag and drop | none (no `CFBundleURLTypes`, no `onDrop`, no `dropDestination`; `project.yml` sets none) | none | n/a |
| Launch flags (`--db`, `--screen`, `--select`, `FD_*`) | test and screenshot only | live, developer | n/a |
| Future: Claude connector | search, suggest, set type, save system | **future** (`docs/ideas/connector.md`) | n/a |
| Future: Send to Paper, search by look | | **future** (design review, post v1) | n/a |
| Sibling channel: Tauri app in `src/` | reads the same DB, old nouns (Starred, Excluded) | live until D5 | n/a |

No routes exist, so no moved route breaks a door. Renames break nothing outside the app (no email, no links, no widgets). The one door that moves a name is the connector: tool names should use the final nouns, so settle labels first.

Missing doors the ship plan already names (R5, not new): ⌘1 to ⌘3, ⌘Z, ⌘N, a menu entry for each loop step, Export in File. This spec adds one: **Export belongs in the File menu and the toolbar both**, with the same four items.

## 6. Names

Source tags: `user` none exists (no research, no logs, no support yet). So every label is `team` or `taste`. A first-click test is the only way to move one to `user`.

### Collision table (current and proposed, counts from quoted UI strings; commands in the appendix)

| Word | Meanings | Count | Decision |
|---|---|---|---|
| **Saved** | (a) starred family, 5 strings, sidebar, chip, a11y. (b) "Saved to Acme" persisted, 4 strings, plus board 04 "SAVED TO ACME" | 5 vs 4 | Tie, so collision decides. Drop (b). Decision 7 |
| **Shortlist** | per-brand per-job candidates, 12 strings. Not a synonym of Saved. UX audit S1 recorded this split | 12 | Keep. No collision once (b) goes |
| **Current / Chosen** | Current: 4 uses (tag, stage, inspector title, list row). Chosen: 1 (`DisplayView:130`) | 4 vs 1 | Current. Decision 5. Lexicon 11.7 records Current |
| **Use / Choose / Pick** | button "Use for Reading" (6); title "Choose the Display face" (4 strings use Choose); "Pick" 2 | 6 / 4 / 2 | Button stays "Use for". Title becomes "Display face" (a title is a noun; settles it) |
| **Fit** | zoom: 5 uses incl. ⌘0, "Fit to window". Scale mode: lexicon 14.6, board "PRESS FOR FIT", 2 help strings | 5 vs 3 | Zoom keeps Fit. Mode becomes **Auto** (`taste`, test). Decision 3 |
| **Letters** | OpenType group (`TypeSettings` x4, `Playground.swift:167`); board 04 module (glyph tells); board 03 module (alternates); board row "Letters and spacing" (code: "Scale and spacing") | 3 meanings | Decision 4 |
| **Scale** | brand scale (module 01); "Scale and spacing" per-face group (lexicon 14.10) | 2 | Rename the group to "Spacing and features" (with Letters row). One meaning left |
| **Style** | named instance picker (Playground, board 03 "Style"); `Finder.traitsHeader` "Style" (italic, variable filters); "Styles" count | 3 | Rename the traits header to "Traits" (lowest traffic, 1 use) |
| **Set** | destination (sidebar, subtitle); verb in `setDone` "Reading face set", `Colors.buttonHelp`, 2 Scale help strings; board "Set the type"; "stylistic sets"; "Drawn as one set" | 1 noun, 4 verb, 2 other | Keep the noun (team word from your own direction, in the plan, the audit and every board). Change `setDone` and the 3 other verb uses. Handoff |
| **Set, 4 names** | sidebar "Set"; door "Next: sizes and spacing"; board title "Type scale · A with B"; inspector "Set the type" | 4 | One name. Door becomes "Next: Set". Page title "Type scale" is a description, keep; inspector title becomes "Set" |
| **Export / Hand off** | toolbar "Export" 2 strings; board "Hand off" menu and section; plan "Hand-off v1" | 2 vs 3 | Export. Decision 6 |
| **Colors** | stage popover "Colors" (live); sidebar "Colors · Parked" row; "Colors are parked" | 5 | Cut the parked row. One meaning |
| **Display** | job (sidebar, 6 uses) vs kind chip "Display". Recorded: chip becomes "Decorative" (R2, UX audit C2) | | Already decided. Not a finding |
| **Hide / Hidden** | 9 strings. "Excluded" 0, "Starred" 0 in the Mac app | | The 2026-10-12 collision is closed |
| **Difference** | Distinct (code, lexicon 11.3) vs "Clear" (design review, quoting the older lexicon) | | Code and lexicon win. Review text is stale |

Gate note: proposed labels re-checked against this table. After the changes: Fit (zoom) one meaning, Letters one meaning, Current one meaning, Saved one meaning, Set one noun (verbs removed from UI copy).

### Label list (proposed)

| Place | Label | Source |
|---|---|---|
| Sidebar | Brand name · Display · Reading · Set | team |
| Display title | Display face | taste (test) |
| Display card tag | Current | team (lexicon 11.7) |
| Stage zoom | − Fit + | platform |
| Dial mode | Auto / Locked | taste (test) |
| Inspector modules (Reading) | Why it pairs · Face · Letters | team (boards) |
| Face rows | Style · Spacing and features | taste (test) |
| Reading door to Set | Next: Set | taste (test) |
| Toolbar | Export | platform |

## 7. Findings (delta against 2026-10-12)

**Closed since 2026-10-12 (Tauri rows):**

| Old row | Status on the Mac app |
|---|---|
| Finding 1, pair results and filters | Closed. Reading has its own lenses and says "N hidden by filters" with a Clear action |
| Finding 2, dead export items | **Back in new form.** The Export button is disabled. Same pattern (finding 5 below) |
| Finding 3, no path font to matches | Closed. "Find a Reading face" and "Find a Display face" exist |
| Finding 4, brand has no home | Closed for name. Logo: DB column, no UI. Watch-item |
| Decision 1 (filters), Decision 2 (one-style families) | Closed. Counts shown; the grid lists every family |
| Decision 3 (brands or projects) | **Closed by code.** Brands exist; `lastBrand` restores |
| Hide vs Excluded collision | Closed (9 vs 0) |

**New findings, ranked by cost to the loop. Structural ones need a yes.**

**1. Scale has two homes, and one edits the wrong object (structural).** Reading inspector header says "Agrandir · Reading candidate". Module 01 changes the brand's body size and ratio for both faces (`ScaleSection.swift:1-6`, `TypeScale.swift:41`). Board 04 puts Body, Ratio, Measure, Line and Lock in the Set inspector too. One object, two homes in one role (gate H), and a reader flipping candidates changes the whole brand by accident. *Prior decision:* lexicon 14.1 (2026-11-04) put Scale "at the top of the Reading inspector, shared by both faces". No reason is recorded for the placement. What changed: the design review (Nov 4) says "readouts into the new Set inspector first". Reversing 14.1 is named here; the owner decides (Decision 1). Cost of the default: no dial while flipping faces. Mitigation: ⌘2 and ⌘3 are one key away.

**2. The boards disagree with each other and with three settled calls (structural).**
- Set sits under Library on board 14 and under Type on board 04.
- Saved row returns on boards 03 and 14. UX audit S2 retired it ("a filter pretending to be a place"). Ship plan R2 builds S2. The boards give no new reason. Display also has the scope menu that already holds Saved, so Saved has two doors.
- UI and Mono appear on board 14. The ship plan D4 default is to hide them. The first sidebar plan (`swiftui-plan.md`, 2026-10-21) lists "+ UI, + Mono", so D4 reverses that. D4 names the reason: half-built.
- Default: board 04. See Decision 2.

**3. Brand data is in four stores, and a delete would leave junk behind (watch, becomes a bug when delete ships).** Choices and shortlists are in the DB with `ON DELETE CASCADE` (`core/src/db.rs:139-140`). Colors, Scale and face settings are JSON files keyed by brand id (`TypeSettings.swift:230`, `TypeScale.swift:51`, `BrandStyleStore.swift`). The core has `delete_brand` (`ffi.rs:367`); no screen calls it (context menu has Rename only). `brands.id` is `INTEGER PRIMARY KEY` with no AUTOINCREMENT, so after deleting the newest brand the next one reuses the id, and inherits the old colors, scale and settings. *Prior decision:* `TypeSettings.swift` comment: "A candidate to move into the core (and the DB) later, once the Set screen needs the same numbers." Set needs them in R3. **Default: no brand delete in v1. Move Scale, Colors and face settings into the DB in R3, then add delete.** Export (R4) reads four stores until then. Connector note: `docs/ideas/connector.md` "what has to be true first" item 3 says the same.

**4. Letters, Fit, Style, Current have more than one meaning on one screen (collision).** See section 6. The Fit collision is already written into the lexicon: 11.16 and 14.6. It was never caught because the two rows sit in different sections.

**5. Export is a dead end and the forward door lands on a placeholder (door).** The Export button is disabled with roadmap text ("arrives in a later wave"). "Next: sizes and spacing" opens a screen that says "Coming next". UX audit H1 and S4 name both. R3 and R4 close them. Until then ship nothing that is about the roadmap. Default: no change to the plan.

**6. Launch ignores where the brand left off (door).** `AppModel` restores `lastBrand` but sets `screen = options.screen`, which defaults to Display (`AppModel.swift:16,388`). A designer with a finished pair opens on Display again. *Prior decision:* none found (searched plans, audit, lexicon, doc comments). Decision 8.

**7. The inspector's four modules are not one job each (structural).**

| Module (board 14) | Job | One job? |
|---|---|---|
| 01 Scale | Set brand sizes | No. Wrong subject. Moves to Set |
| 02 Why it pairs | Explain this candidate | Yes |
| 03 Face | Choose style, then tune spacing and features | **Two jobs.** Style is "which cut". Spacing and features is "tune it". Keep as one module only if the second row stays collapsed |
| 04 Letters | Show the shapes that tell faces apart (Il1, ag, RGQ, 0O) | Yes, once Display's alternates tiles are renamed |

After the move the Reading inspector is Why, Face, Letters (3). Display's inspector is Sample, Style, Alternates, Letters (board 03 numbers three; the tells strip should be the same tile strip on both). Shortlist leaves the inspector on board 14. Lexicon 11 already says "Cut: the Save, Hide and shortlist buttons in the Reading inspector"; the code still has a Shortlist section (`ReadingInspector.swift:100`). **Docs vs code: follow the doc and the board.**

## 8. Proof plan

| Change | Method | Pass bar | Status |
|---|---|---|---|
| Sidebar of 3 | Tree test, 8 tasks written without label words ("Where do you see the fonts you starred?", "Where do you get CSS for your client?", "Where do you change body size?", "Where do you start a second client?"), 50+ people | Directness 80%+, success 70%+ (median is 62%) | UNTESTED |
| Fit/Auto, Letters, Set, Next: Set, Export | First click on 3 sketches per label | Right first click 80%+ | UNTESTED |
| Scale in Set | Task walk in the running app: "set body to 16 and ratio 1.25", now vs proposed, with click counts | Same or fewer clicks than today | UNTESTED |
| Launch lands on last screen | Task walk: relaunch with a finished pair | Lands on Set | UNTESTED |
| Cold pre-check | 3 agents, labels as a text tree | **Flags to test only, never evidence** | NOT RUN |

Note for the task walk: the `--inspector` and `--compare` screenshot flags hang the app at launch (design review). Walk with the live window.

## 9. Keep-list

Reading list plus stage and arrow-key flipping (approved 2026-10-22). Current pinned at the top of the Reading list. Use for Reading on the stage bar. Brand scope for choices and shortlists. One window. "N hidden by filters" with a way back. Sidebar row shows the chosen face name. Undo after Clear.

## 10. Considered and rejected

- **Set under Library (board 14).** Library holds global things; Set is brand-scoped. Rejected.
- **Saved as a sidebar row.** Retired by UX audit S2. Not reopened without a new reason.
- **Keeping UI and Mono visible but greyed.** The "+" rows are a roadmap leak (S4).
- **Dial in both Reading and Set.** Two homes for one object. A read-only readout in Reading gives the same feedback.
- **"Sizes" instead of "Set".** Fixes the verb collision, but "Set" is your own word in the plan, audit and boards. Kept, with a test.
- **"Hand off" as the button.** Collides with the macOS Handoff feature. Kept as a round name only.
- **Command palette or chat as navigation.** Doors, not nav. Not needed for 3 destinations.

## 11. Work order

1. **String-only, no yes needed:** drop "Saved to Acme"; Chosen to Current; traits header to Traits; cut the "Colors · Parked" row and the "Coming next" and "Nothing to inspect yet" text; change `setDone`; fix board 03 and 14 to match. Handoff to ux-copy.
2. **R2 sidebar to 3 rows** (D4, S2, S4). Needs yes on Decision 2.
3. **R3:** build Set with Scale in its inspector; Reading keeps the readout. Needs yes on Decision 1. Move Scale, Colors and settings into the DB in the same round (finding 3).
4. **R4:** Export in toolbar and File menu, four items.
5. **R5:** ⌘1 to ⌘3, ⌘Z, menu entries per step, launch on last screen (Decision 8).
6. **After v1:** brand delete with its data, then the connector using final nouns.

## Handoffs

- **ux-copy:** the collision table and label list above. Also `setDone` ("Reading face set"), `Colors.buttonHelp` ("Set the colors..."), the two Scale help strings with the verb "set", and the Fit and Auto copy in lexicon 14.6.
- **ui-craft:** Face module (two jobs in one), the Letters tile strip on both inspectors, and the dial's lock gesture (turn locks, press returns to Auto) with a visible Locked/Auto word, not color alone.

## Docs vs code (code wins)

- Lexicon 11 says shortlist buttons are cut from the Reading inspector; code still has the Shortlist section. Offer: update after the board is built.
- Design review quotes lens words "Close, Clear, Strong"; code and lexicon 11.3 say Close, Distinct, Strong. Offer: fix the review text.
- Lexicon 14.1 places Scale in the Reading inspector. Offer: update if Decision 1 is yes.
- `swiftui-plan.md` lists "+ UI, + Mono" in the sidebar. Offer: add D4.
- 2026-10-12 spec Decision 3 and findings 1 to 4 describe the Tauri app. Offer: mark superseded.

## Gates

A pass · B pass (commands in the appendix; quoted-string greps exclude identifiers and comments, so counts are of UI strings) · C pass (each reversal names its record: lexicon 14.1, UX audit S2, D4, swiftui-plan sidebar) · D pass (no routes, links, widgets or notifications exist; connector and Paper listed as future) · E pass (no word retired by count alone; ties go to the collision rule) · F **open: pending owner**, defaults in Decisions 3, 4, 5, 7 · G pass (re-tested: "one home" holds for Scale only if Decision 1 is yes; sidebar claim "3 rows" counted) · H **open: pending owner**, Scale (Decision 1) and Saved door (Decision 2) · I pass for a Mac sidebar (3 destinations, same order as ⌘1 to ⌘3; no phone target) · J pass (UNTESTED) · K pass (8 decisions with defaults above the fold; body under 250 lines) · L **fails today** for the Export button and the Set placeholder; closes with R3 and R4 · M pass (the Parked row is cut, not kept) · N pass · O pass (connector and Send to Paper marked future) · P pass (no pre-check was run) · Q pass · R pass

---

## Appendix: counts and commands

Run in `macos/Sources/FontDrop` of the audited worktree. "Quoted-string" means a grep for text inside double quotes, which skips most identifiers.

| Count | Command | Result |
|---|---|---|
| Screens (enum cases) | `grep -n "case display" AppModel.swift` | 6: display, reading, ui, mono, set, colors |
| Sidebar rows today | read `SidebarView.swift:21-45` | Display, Reading, UI, Mono, Saved, Set, Colors (disabled) = 7 |
| Shortlist strings | `grep -rnE '"[^"]*[Ss]hortlist[^"]*"' *.swift \| grep -v Bench \| wc -l` | 12 |
| Saved as star | `grep -rnE '"[^"]*(Saved\|Save"\|Remove from Saved\|saved fonts)[^"]*"' *.swift \| grep -vE 'Bench\|Colors\|savedTo' \| wc -l` | 5 |
| Saved as persisted | `grep -rnE 'savedTo\|Saved to\|save to' *.swift \| grep -v Bench \| wc -l` | 4 |
| Fit (zoom) | `grep -rn 'Reading.fit\|zoomFit\|"0", modifiers' *.swift \| wc -l` | 5 |
| Letters (OpenType group) | `grep -c 'group: "Letters"' TypeSettings.swift` plus `Playground.swift:167` | 4 + 1 |
| Export strings | `grep -rnE '"[^"]*Export[^"]*"' *.swift \| grep -v Bench \| wc -l` | 2 |
| Hide / Hidden strings | `grep -rnE '"[^"]*\b(Hide\|Hidden\|hidden\|Unhide)\b[^"]*"' *.swift \| grep -v Bench \| wc -l` | 9 |
| Excluded / Starred strings | `grep -rn "Excluded\|Starred" *.swift \| wc -l` | 0 |
| Current uses | `grep -rn "Lexicon.current\|Reading.current\b\|currentTitle" *.swift` | 4 call sites (`Components.swift:207`, `ReadingStage.swift:312`, `ReadingInspector.swift:115`, `ReadingView.swift:151`) + `currentTitle` title |
| Chosen uses | `grep -rn '"Chosen"' *.swift` | 1 (`DisplayView.swift:130`) |
| keyboardShortcut sites | `grep -rn keyboardShortcut *.swift \| wc -l` | 6 (4 stage zoom, 2 sheet) |
| Menu commands | read `FontDropApp.swift:16-31` | 1 menu (Type); New Item removed |
| URL, document, drop doors | `grep -rn "onOpenURL\|CFBundleURLTypes\|onDrop\|dropDestination" . ../../project.yml` | 0 |
| Brand tables | `grep -n "CREATE TABLE.*\(brands\|shortlist\|choices\|favorites\|hidden\)" core/src/db.rs` | brands (no AUTOINCREMENT), shortlist and choices cascade on brand delete |
| JSON stores | `grep -n '\.json"' macos/Sources/FontDrop/*.swift` | colors, scale, playground |
| Brand delete in UI | `grep -rn "deleteBrand" macos/Sources core/src/ffi.rs` | core only (`ffi.rs:367`) |
| Reading inspector sections | read `ReadingInspector.swift:12-24` | header, Scale, Why, Reading playground, Display playground, Shortlist |

Not counted: tap counts (no task walk run), analytics (none exist), zero-result rate (no logs).
