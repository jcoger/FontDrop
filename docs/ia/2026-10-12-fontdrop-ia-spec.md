# IA SPEC: FontDrop · macOS desktop (Tauri) · 2026-10-12 · UNTESTED

**Ask:** Jarrett has been away from FontDrop and remembers the structure getting messy. Audit it.
**Audited:** local `feature/font-pairing` @ `8c4ade6`. It is 9 commits ahead of `origin/main` and contains all of it (`git rev-list --count HEAD..origin/HEAD` = 0). The v0.1.0-beta .dmg on Releases is older and does not have Pair mode. Next release read: none (no roadmap doc; `plans/` 001–007 are all done).
**Ledger:** top +0/-0 · nav +0 · views +0/-0/merged 0/moved 0 · doors +1 (Find pairs) · fields merged: brand name 2→1, logo drop 2→1 · dead export items −2. **The proposal adds nothing at the top level. It removes duplicates and fixes broken links between modes.**

**Status 2026-10-21:** findings 1–4, the §6 labels and Decision 2 are built on `feature/font-pairing` (commits `0ec082d`..`3a893dd`). Decisions 1, 2 and 4 took their defaults; Decision 3 stays open. Proof: `cargo test` (a new test fails without the hidden-font fix), `tsc`, lint, `npm run build`. The §8 task walk in the running app has **not** run. The tree is still UNTESTED.

**Decisions for Jarrett:**
1. **Pair results: which filters apply?** Today every filter in the bar (search, source, category, style, Starred) also hides matches. **Default: matches respect only Hidden fonts.** The left panel keeps all filters.
2. **Families view hides one-style fonts.** That was a deliberate call (the "orphan fix", recorded in project memory, reason: empty rows). It hides **1,751 of 5,459 user fonts (32%)**. **Default: show one-style fonts as plain rows with no expander.** That keeps the original fix (no empty expanders) and brings the fonts back.
3. **One brand at a time, or projects?** Starred fonts, the logo, the brand name and the saved palette collection are all one global set. One client's shortlist and another's mix together. **Default: not now.** Do finding 4 first, so a later "switch brand" has one place to live.
4. **Labels marked `taste` below.** **Default: ship them and check them in the task walk** (section 8).

**The big picture:** FontDrop has four modes, but it does two jobs. **Find the typeface** (Logo Grid, Type Explorer, Pair) and **build the palette** (Brand Colors). The objects that should connect the modes do not. The selected font does not travel from Quick View to Pair. The brand's name lives in two fields with two values. The Export menu shows items that do nothing in some views. Pair silently reuses the browse filters, so searching for a font hides its own matches. The risk from the roadmap is scope. The app has no "brand" or "project" object. Starred fonts and palettes from every client pile into one list. Any client-facing use (the Dyno sprint flow) will hit that first.

---

## 1. Needs and top tasks

User: Jarrett and the Dyno team, picking type and color for a client brand.

| # | Task | Need type |
|---|---|---|
| T1 | See my logo/wordmark set in many fonts and shortlist a few | Exploratory |
| T2 | Find one font I can name and look at it closely | Known-item |
| T3 | Find fonts that pair with a font I already like | Exploratory, starts from a known item |
| T4 | Compare shortlisted fonts side by side in real copy (headline, body) | Re-finding |
| T5 | Build a palette for the brand and save it | Exploratory |
| T6 | Send the result to Figma/Paper (PNG, prompt, palette) | Known-item |
| T7 | Get junk fonts out of the way, and bring back one I hid by mistake | Re-finding |

Mostly exploratory, with known-item entry points (T2, T3). The structure needs both browse and search. It has both.

## 2. Objects

| Object (UI name) | Code name | What it is | Instances | Name source |
|---|---|---|---|---|
| **Font** | `FontInfo` / `FontDBRow` | One font file (one style) | 5,808 (`sqlite: select source,count(*) from fonts group by source` → user 5,459 · system 250 · library 99) | team |
| **Family** | `FontFamily` | Fonts sharing `font_family` | 3,022 user families (1,271 with 2+ styles, 1,751 with one) | team |
| **Brand** *(unnamed today)* | `wordmark` + `ceBrandName` + `logoSvg` | The name and logo being designed for | 1, global | **none: no object today** |
| **Starred** (shortlist) | `useStarred` | The set of fonts being considered | 1 set, unified across modes | team |
| **Hidden font** | `useExclusions` | A font removed from all views | user list + built-in list | team (two words, see §6) |
| **Match** | `PairScore` | A scored partner for a Primary font | top 4/4/3 per Primary (`pairing.rs:483-498`) | team |
| **Skeleton** (classification) | `skeleton`, `flesh_*` | Dynamic / rational / geometric | per font; 153 unknown | team (Font Matrix) |
| **Palette** | method output | Colors made by one method | 1 live | team |
| **Collection item** | `useCollection` | A saved palette | many | team |
| **Brand Kit** | `brandKitItem` | A saved palette laid out with roles and fonts | one per collection item | team (renamed from Role Builder, `56b5308`) |
| **Explorer sheet** | `explorerHeaders/Columns/ColSizes` | The column setup in Type Explorer | 1, not saved | team |

Set aside (attributes, not objects): category, style, width, weight, controls (size/track/weight/colors), method params.

**Relationships that should be paths:**

| From → To | Cardinality | Path today |
|---|---|---|
| Font → Matches | 1 → 11 | **Only by picking the font again in Pair's left panel.** Quick View has no link |
| Font → Family | many → 1 | Families view (one-style families excluded) |
| Starred → Brand Colors | set → palette cards | Automatic. Falls back to the first 12 fonts if nothing is starred |
| Brand → every mode | 1 → all | Split: wordmark field (Grid, Pair) and brand name field (Brand Colors) |
| Collection item → Brand Kit | 1 → 1 | Collection hub → item |

**Actions:** Star, Hide and Unhide sit on Font in every mode. Set skeleton sits on Font, in Pair only (`SkeletonBadge`). Export acts on the **current view**. Its items are global, which is the problem in finding 2.

## 3. Homes

| Object | Home | Problem |
|---|---|---|
| Font | **Two detail surfaces**: Quick View (Grid, Explorer) and Pair's Primary/Match view | Neither links to the other (finding 3) |
| Brand | **No home.** Two fields, two values. Wordmark is not saved and defaults to "Fontdrop". Brand name is saved | Finding 4 |
| Logo | Drop target in Grid and Brand Colors. Rendered in Pair with no drop target there | Finding 4 |
| Starred | A filter toggle in the filter row of 3 modes, plus the input to Brand Colors | OK. It is a place-like filter. Keep it |
| Hidden fonts | "Excluded (n)" menu in the filter row | Label only (§6) |
| Collection / Brand Kit | Inside Brand Colors | OK |

List order: fonts sort alphabetically by family (`db.rs:455`, `ORDER BY font_family COLLATE NOCASE`). Matches sort by score. Both are on purpose.

## 4. Navigation

Read from `App.tsx`:

- **Mode tabs: 4** (`App.tsx:531`): Logo Grid · Type Explorer · Brand Colors · Pair. The Tab key cycles all four (`App.tsx:323-330`). The app always opens on Logo Grid; the mode is not saved.
- **Filter row: 17 controls in one 40px row** (`App.tsx:735-832`): source (3) · category (All + 6) · style (3) · Starred (2) · Excluded menu · Refresh Google Fonts (icon only) · count. Hidden in Brand Colors.
- **Brand Colors brings its own nav, 4 layers deep:** method bar (5 of 6 methods visible, `MethodBar.tsx:6`; "Contrast Safe" is hidden), Albers side panel, Collection hub, Brand Kit. Its top bar swaps search for logo + brand name.

Four tabs on a desktop window is fine. The mess is not the tab count. It is the plumbing between the tabs (sections 2 and 3).

## 5. Doors

Desktop app, local only. No deep links, no app menu (`tauri.conf.json` has none; `lib.rs:164` loads only `tauri_plugin_opener`), no notifications, no sibling repos (`ls ~ ~/labs | grep -i font` → only this repo).

| Door | Opens | Live | Lands cold? |
|---|---|---|---|
| App launch | Logo Grid | live | yes |
| Mode tabs, Tab key | that mode | live | yes |
| First-launch toast "Manage in Excluded." | points at the filter-row menu | live | yes |
| Brand Colors empty state "switch to grid" | Logo Grid | live | yes |
| `?` shortcut overlay | overlay | live | **text is wrong** (§ Docs vs code) |
| Outbound: Save PNG, Copy Figma Prompt, Copy Palette, Brand Kit prompt | file / clipboard → Figma, Paper | live | **2 dead in some views** (finding 2) |

No route moves are proposed, so no door breaks.

## 6. Names

**Collisions now:**

| Word or concept | Where | Problem |
|---|---|---|
| **"All" ×3** | filter row: source "All" (`App.tsx:739`), category "All" (`:1068`), star toggle "All" (`:142`) | One word, three scopes, one row |
| **"System"** | source filter "System" (fonts) · pair tag "System" (superfamily, `PairMode.tsx:24`) | One word, two concepts |
| **Pair type: 3–4 names each** | harmonious = "Same DNA" · bold = "Tension" / "Intentional tension" · superfamily = "System" / "Designed as a system" · uncertain = "Maybe" / "Worth a shot" (`PairMode.tsx:21-34`). `docs/pairing-score.md` uses Harmonious / Bold contrast / Designed to pair / Uncertain | One concept, several words. "Worth a shot" is also a bucket name (`pairing.rs:520`) |
| **Hide / Excluded** | Hide-family 9 UI strings vs Exclude-family 5 (count below) | One concept, two words |
| **Wordmark / Brand name** | "Type a word…" (`App.tsx:605`) vs "Brand name…" (`:564`) | One concept, two fields |
| **Font / variant / Individual** | toggle "Individual" (`:668`) · "Hide variant" (`FontFamilyList.tsx:240`) · "Hide font" ×2 · count "N fonts" | One concept, three words |

Count for Hide vs Exclude: `grep -rnoE '…(Hide|Hidden|Unhide)…' src` and `…(Excluded|exclusions|Exclude)…`, then a spot-read to drop class names like `overflow-hidden`. Hide: FontCard:86, TypeExplorer:96, FontFamilyList:110 and :240, QuickView:224, App:170, :189, :205, :300 = **9**. Exclude: App:180, :198, :218, :300, :801 = **5**.

**Proposed labels:**

| Concept | Proposed | Source |
|---|---|---|
| Hidden fonts menu | "Hidden (n)"; toast "Manage in Hidden." | team: majority 9 vs 5 |
| Single font toggle | "Families · Fonts"; "Hide variant" → "Hide font" | team: "font" is the majority word |
| Superfamily tag | "Superfamily" everywhere (card + detail) | team: `pairing-score.md` "Confirmed superfamily" |
| Bold tag | "Tension" everywhere | team: card label |
| Uncertain tag | "Maybe" everywhere | team: card label. Frees "Worth a shot" for the bucket only |
| Star toggle | one "Starred" toggle, no "All" option | taste, check in the task walk |
| Source "All" | "All sources" | taste, check in the task walk |
| Brand field | "Brand name…" in every mode | team: the saved field already uses it |

Re-checked: no proposed label collides with another. "System" now means fonts only. "All" stays only on category. "Brand" names the object, and Brand Colors and Brand Kit are its parts.

## 7. Findings

Ranked by cost to the top tasks.

**1. Searching for a font hides its own matches (T3, broken).** Rust scores every font and keeps the top 4/4/3 (`pairing.rs:455-498`). The frontend then drops any match that is not in the filtered left-panel list (`PairMode.tsx:410`, `if (!font) return null`; `App.tsx:861` passes `filteredFonts`). Type "Garamond", pick it, and every match whose name lacks "Garamond" disappears. A bucket can show its header with no cards. Hidden fonts also take slots and then render nothing.
→ Pass the hidden list to `get_font_pairs`, and score matches from all non-hidden fonts. The filters stay on the left panel only. *Prior decision:* Pair has used the shared filtered list since `f9cde9e` (2026-06-14). Plan 007's comment (`App.tsx:412`) records that the filter is shared. Nothing records that matches should be filtered. **Needs a yes** (Decision 1).

**2. Export items that do nothing.** "Save PNG" and ⌘E in Pair: the target `gridContainerRef` is unmounted in Pair (`App.tsx:450-451`, `:880`), so it returns silently. ~~"Copy Palette" in Brand Kit view does nothing~~ **Corrected 2026-10-21:** Brand Kit sets its own export (`BrandKitView.tsx:142`, copies the kit prompt), so it worked; the label was wrong. In Collection view it copied the live method palette, which isn't on screen.
→ Show only the items that work in each view. Optional later: a Pair export (the comparison card). *Prior decision:* none found (searched plans/, docs/, commit messages, comments). Fix.

**3. No path from a font to its matches (T2 → T3).** Quick View has Star, Hide, prev/next (`QuickView.tsx:218-273`). It has no "pairs". Pair's selection lives inside `PairMode` (`PairMode.tsx:524`), so any mode switch drops it. Today: close Quick View → Pair tab → search again → click. The search then triggers finding 1.
→ Add "Find pairs" to Quick View. Move the Pair selection up to App so it survives mode switches. *Prior decision:* none found. **Needs a yes** (+1 door).

**4. The brand has no home.** There are two name fields with two values, and only one of them is saved (`App.tsx:230` vs `:234`). The logo drop is in Grid and Brand Colors, but Pair renders the logo with no way to load or clear it there (`App.tsx:589-599`, `:863`). Type Explorer shows neither.
→ Create one Brand slot in the top bar: name + logo, the same in all four modes, saved. *Prior decision:* none found (`54db14d`, `c37a388` give no reason for a separate brand name). **Needs a yes.** This sets up Decision 3.

**5. Families view hides 32% of user fonts.** See Decision 2. It is not a finding because the call was recorded; it is listed here so the cost stays visible.

**Watch-items:** "Contrast Safe" is fully built but hidden from the method bar (`MethodBar.tsx:6`, since `c37a388`, no reason recorded). Ask whether it is parked or dead. The Refresh Google Fonts icon sits among filters. It is housekeeping and a candidate for a future app menu.

## 8. Proof plan

| Change | Method | Pass bar | Status |
|---|---|---|---|
| 1, 3 | Task walk in `npm run tauri dev`: "Find partners for Garamond", now vs proposed, counting clicks and checking that matches stay visible | Proposed: ≤3 clicks from a Quick View, 11 matches visible with a search active | UNTESTED |
| 2 | Click every Export item in every view (4 modes + Collection + Brand Kit) | 0 items that do nothing | UNTESTED |
| 4 | Task walk: set brand name and logo once, visit all 4 modes | Same name and logo everywhere, still there after relaunch | UNTESTED |
| §6 taste labels | Cold pre-check (3 subagents get only the label tree), then Jarrett's own first click on "show only my installed fonts" and "only starred" | First click right | NOT RUN |

## 9. Keep-list

Four modes in this order. Starred as one shared set (the legacy per-mode sets were merged on purpose, `useStarred.ts:3-4`). Alphabetical font order. Pair buckets and their names. Brand Colors' internal structure. Hover + S to star.

## 10. Considered and rejected

- **Merging Logo Grid and Type Explorer into one mode with a layout toggle.** They share filters and Quick View, but they serve different tasks (T1 vs T4). The merge is not worth the churn.
- **Moving Brand Colors to its own window.** It already behaves like a separate tool, but it reads Starred and Brand live. A separate window would add sync work for no gain today.
- **"App.tsx size / ColorExplorer monolith"** was deferred in `plans/README.md`. That is an architecture question, not IA, and this spec does not touch it.

## 11. Work order

1. Finding 2: hide dead export items. Fix, reversible.
2. §6 label renames (Hidden, Fonts, pair tags). String-only, handed to ux-copy.
3. Finding 1: unfiltered matches. **Needs a yes.**
4. Finding 3: Find pairs + persistent Pair selection. **Needs a yes.**
5. Finding 4: Brand slot. **Needs a yes.** Then decide on Decision 3.

## Handoffs

- **ux-copy:** the §6 table. Also: the Brand Colors empty state says to star fonts "in Logo Grid or Type Explorer", but Pair stars too (`ColorExplorer/index.tsx:536`).
- **ui-craft:** the filter row has 17 controls in 40px. Look at its density after the label changes.

## Docs vs code (code wins)

- `ShortcutOverlay.tsx`: says Tab switches "Logo Grid / Type Explorer"; it cycles all 4. Says ⌘E exports the "Type Explorer starred view"; it exports Grid or Explorer, and does nothing in Pair. Offer: update the overlay.
- Project memory said starred sets are separate per mode (now unified) and called the toggle "Variants" (code: "Individual"). Memory updated.
- `docs/pairing-score.md` pair-type names differ from the UI (§6). Offer: align the doc after the renames.

## Gates

A pass · B pass (sqlite + grep shown; filter-row count read from `App.tsx`) · C pass · D pass (desktop, no external doors; outbound clipboard/file listed) · E pass · F pass on proposed labels · G pass (no "one place" claim fails: Brand slot is one field in one bar) · H **open**: Font has two detail surfaces (Quick View, Pair detail); finding 3 links them rather than merging, pending owner, default link · I pass · J pass (UNTESTED) · K pass · L pass · M pass (Refresh icon is a watch-item, not a drawer) · N pass · O pass · P pass (pre-check not run, not cited) · Q pass · R pass
