# STRING SHEET + LEXICON: FontDrop Mac app (pairing) · macOS · 2026-10-21

**Assignment:** the Reading and Display screens, lens controls, evidence, shortlist and choose flow, read by a working brand designer mid-task.
**Voice source:** Jarrett's CLAUDE.md voice (direct, plain, designer-to-designer). No product voice doc yet.
**Band:** shared (labels, confirmations) · **Mode:** Instructive by default; Adding Delight only on "chosen" moments.
**Gut-check:** would a designer who never read a type book know what to do, and why?

**Open questions**
1. Section 7 (cold read) overrides earlier rows. "Less common first" needs popularity data. Until then the sort can't honestly say "unexpected" (see 2.4).
2. The contrast slider replaces the Contrast menu once pair types map to a continuous score. Copy for both is below.

## 1. Lexicon (one concept, one word)

Designer words beat book words. A book term appears only inside a help popover, never as a label.

| Concept (engine) | UI word | Not this | Help text (popover, one line) |
|---|---|---|---|
| skeleton | **Structure** | skeleton, bones | How the letters are built: from the pen, from geometry, or from rational rules. |
| dynamic | **Humanist** | dynamic, pen-made | Built from the pen: open shapes, a slight diagonal stress. |
| rational | **Rational** | constructed | Upright and regular: grotesques, neo-grotesques, modern serifs. |
| geometric | **Geometric** | constructed | Built from circles and straight lines. |
| same camp / crossed hands | **Same feel / Mixed feel** | same hand, pen-made vs constructed | Humanist with humanist feels calm. Humanist with geometric or rational adds tension. |
| flesh_serif | **Serif / Sans** | flesh | — |
| flesh_contrast | **Stroke** (even / high contrast) | texture, flesh, linear | How much the strokes go thick to thin. |
| pair_type contrast | **Contrast** | clear contrast | Different enough to look intentional, usually serif with sans. |
| pair_type uniform | **Harmony** | uniform | Same form and structure. Reads as one voice. |
| pair_type superfamily | **Superfamily** | designed together | Drawn as a set by the same designer. Safest choice. |
| pair_type middle | **In-between** | middle | Similar enough to look like a mistake. The books warn against it. |
| evidence | **Why** | evidence, lenses measured | — |
| strength rule | **Firm** | rule | Most sources agree. |
| strength guideline | **Common advice** | guideline | Widely recommended, not absolute. |
| strength shortcut | **Rule of thumb** | shortcut | Raises the odds, no guarantee. |
| strength caveat | **Use with care** | caveat | Sources disagree. |
| effect 0 | **Not scored** | your call | Shown for your judgment. Doesn't change the order. |
| job | **Role** in prose; job names as is | job | Display, Reading, UI, Mono |
| is_trial | **Trial** | test, demo | Free to try. License it before you ship. |

Source citations shown to designers use author names, not codes: "Latin, Typewolf" not "LAT ch.5; TWC 69-70". Codes stay in the engine.

## 2. Lens controls (Reading toolbar)

| ID | State | Key | Current | Proposed | Note |
|---|---|---|---|---|---|
| 2.1 | label | lens.contrast | How much contrast | **Contrast** | Menu today, slider later (2.6) |
| 2.1a | options | lens.contrast.* | Close · Clear · Extreme · Any | **Similar · Distinct · Bold · Any** | Similar = Harmony; Distinct = Contrast; Bold = Contrast with stroke or feel difference |
| 2.2 | label | lens.feel | Same hand | **Feel** | The confusing one |
| 2.2a | options | lens.feel.* | Same · Crossed · Either | **Matching · Mixed · Either** | Help: 1 "same feel" line |
| 2.3 | label | lens.foundry | Same foundry | **Foundry** | |
| 2.3a | options | lens.foundry.* | Yes · Any | **Same foundry only · Any** | Options must read alone (Gate D) |
| 2.4 | label | lens.sort | Sort: Unexpected first | **Sort: Fewest shortcuts first** → better **hide** until popularity data | Accuracy (Gate A): today it sorts by fewer rule-of-thumb reasons, not by how common a face is. "Unexpected" would be a lie |
| 2.4a | options | lens.sort.* | — | **Best match · Same x-height first · Name** | Ships now; "Less common first" returns with data |
| 2.5 | status | lens.hidden | 3 hidden by your lenses · Show everything | **3 hidden by your filters · Show all** | "Lens" is our word; "filter" is theirs |
| 2.6 | future slider | lens.contrast.slider | — | Label **Contrast**, ends **Similar** ↔ **Bold**, value shown under the thumb: **Similar / Distinct / Bold** | Same three steps, so the copy carries over |

## 3. Candidate cards and evidence chips

| ID | Key | Current | Proposed | Note |
|---|---|---|---|---|
| 3.1 | chip.contrast | + Clear contrast: serif + sans | **Serif with sans** | The group header already says Contrast (cut the echo) |
| 3.2 | chip.skeleton | + Skeleton: both dynamic | **Both humanist** | |
| 3.3 | chip.feel.mixed | crossed hands | **Mixed feel** | Neutral style, never a minus |
| 3.4 | chip.xheight.same | + x-height: within 0% | **Same x-height** | "within 0%" reads like an error |
| 3.5 | chip.xheight.diff | x-height 9% smaller | **x-height 9% smaller** | Keep: specific, true |
| 3.6 | chip.texture | + Texture: contrasting vs linear | **High contrast with even stroke** | |
| 3.7 | chip.foundry | + Foundry: Alexander Slobzheninov | **Same foundry** | Name moves to the Why list (it's a person, not the foundry, when the name table says so) |
| 3.8 | chip.designer | + Designer: … | **Same designer** | |
| 3.9 | chip.neardup | near-duplicate | **Nearly identical** | Not scored, shown as a warning |
| 3.10 | card.cta | Why this one | **Why** | Opens the inspector's Why list; "this one" is a pronoun with no noun (Gate Q) |
| 3.11 | card.meta | 11 styles | **11 styles** | Keep |

## 4. Inspector

| ID | Key | Current | Proposed |
|---|---|---|---|
| 4.1 | insp.subtitle | Reading candidate · 4 lenses measured | **Reading candidate** |
| 4.2 | insp.section.why | Evidence | **Why it pairs** |
| 4.3 | insp.row.strength | Guideline / Shortcut | **Common advice / Rule of thumb** (2nd line, quiet) |
| 4.4 | insp.row.source | LAT ch.5; TWC 69-70; BON p.145; MAY | **Latin, Typewolf, Bonneville, Mayer** |
| 4.5 | insp.row.notscored | Your call | **Not scored. Your choice.** |
| 4.6 | insp.shortlist.title | Shortlist · Reading | **Shortlist** (role is already in the sidebar) |
| 4.7 | insp.shortlist.add | Add to shortlist | **Add to shortlist** |
| 4.8 | insp.shortlist.remove | (icon only) | Label for VoiceOver: **Remove [Family] from shortlist** |
| 4.9 | insp.shortlist.empty | — | **Nothing here yet. Add faces you want to compare.** |
| 4.10 | insp.facts.licence.ok | Not marked as trial | **Full license** → accuracy: we only know "no trial words". Use **No trial marks** |
| 4.11 | insp.facts.licence.trial | Trial | **Trial · License before you ship** + link **Get the license** |

## 5. Choose flow

| ID | State | Key | String | Note |
|---|---|---|---|---|
| 5.1 | default | choose.display | **Use for Display** | Passes WYLTIWLT |
| 5.2 | default | choose.reading | **Use for Reading** | |
| 5.3 | success | choose.done.display | **Display face set** | Inspector, replaces the button. One delight beat: a check, no confetti |
| 5.4 | success | choose.done.reading | **Reading face set** | |
| 5.5 | action | choose.undo | **Undo** | |
| 5.6 | next | choose.next.display | **Find a Reading face** | Arrow icon carries direction; text stays plain |
| 5.7 | next | choose.next.reading | **Set the type** | |
| 5.8 | already chosen | choose.current | **Current Display face** | When viewing the chosen one again |

## 6. Empty states and prompts

| ID | Key | String | Note |
|---|---|---|---|
| 6.1 | brand.sheet.title | **Name this brand** | |
| 6.2 | brand.sheet.field | Placeholder **Brand name** | |
| 6.3 | brand.sheet.help | **Your faces and shortlists save to this brand.** | |
| 6.4 | brand.sheet.ok | **Create brand** | |
| 6.5 | brand.sheet.cancel | **Cancel** | |
| 6.6 | brands.empty | **No brands yet** | Keep (seen in the build) |
| 6.7 | reading.needsdisplay.title | **Pick a Display face first** | |
| 6.8 | reading.needsdisplay.body | **Reading suggestions start from it.** | |
| 6.9 | reading.needsdisplay.cta | **Choose a Display face** | |
| 6.10 | reading.fixed | **Showing faces made for long text** | Replaces "Text cuts only" |
| 6.11 | reading.fixed.hidden | **42 hidden · Why?** | Popover: **Hidden: display cuts, condensed and mono faces, and families without italic or bold.** |
| 6.12 | reading.none | **No matches with these filters. Show all** | |
| 6.13 | reading.more | **Show more** | |

## Findings (AUDIT order)

1. **Inaccurate:** "Unexpected first" (2.4) claims popularity the app doesn't have. "Not marked as trial" (4.10) is fine but "Licensed" would be false; use "No trial marks".
2. **Ambiguous:** "Same hand" (2.2), "Why this one" (3.10, pronoun), "x-height: within 0%" (3.4).
3. **Inconsistent:** pair groups named three ways across PRs (Same DNA, Clear contrast, Contrast). This sheet fixes them as Contrast / Harmony / Superfamily / In-between.
4. **System words in UI (Gate R):** skeleton, dynamic, texture, linear, lens, evidence, guideline, shortcut, source codes.
5. **Wordy / echo:** chip prefixes repeat the group header (3.1).
6. **Cuts:** "4 lenses measured" (4.1), "· Reading" in the shortlist title (4.6).

## Gates

A pass after 2.4 and 4.10 · B pass for these surfaces (loading/error states not in scope) · C pass (no em dashes) · D pass · E n/a (no errors in scope besides 6.12) · F pass, all shorter or equal · G pass after 3 · H pending cold read · K pass (no colour-only meaning; VoiceOver label 4.8) · N pass · O cuts listed · Q pass after 3.10 · R pass after 4

## 7. Cold read, round 1 (2026-10-21): changes

A fresh reader (working brand designer, no plan) read the rendered strings. Findings were checked against the engine before applying. These rows override sections 1 to 6.

| ID | Was | Now | Why |
|---|---|---|---|
| 7.1 | Filter **Contrast**: Similar · Distinct · Bold · Any | **Difference**: Close · Clear · Strong · Any | "Contrast" meant three things: the filter, a group and stroke contrast. "Bold" read as weight. Contrast now means stroke only, its normal type meaning |
| 7.2 | Future slider **Contrast**, Similar ↔ Bold | **Difference**, Close ↔ Strong | Same steps as 7.1 |
| 7.3 | Group **Contrast** | **Clear difference** | Frees "contrast" (7.1) |
| 7.4 | Group **In-between**: "…The books warn against it." | **Too close**: "So alike it can look like a mistake." | Label said nothing alone; "the books" was vague and preachy |
| 7.5 | Group **Superfamily**: "Drawn as a set by the same designer." | "Drawn as one set. Safest choice." | Superfamilies are often drawn by a team |
| 7.6 | Filter **Feel**: Matching · Mixed · Either | **Structure**: Same · Mixed · Any | Its help defined Feel with structure, so it was one idea under two names. "Any" everywhere, never "Either" |
| 7.7 | Help, Feel | Help, Structure filter: **"Same structure reads calm. Mixed adds tension. Not scored."** | Covers every mix, not only humanist ones |
| 7.8 | Chip **Mixed feel** | **Mixed structure** | Follows 7.6 |
| 7.9 | Chip **x-height 9% smaller** | **x-height 9% smaller than Display** | Name the reference point |
| 7.10 | Chip **High contrast with even stroke** | **Even stroke vs high-contrast Display** | Says which face is which |
| 7.11 | Chip **Nearly identical** | **Too close to Display**, warning style (icon + secondary color) | Looked like a positive chip |
| 7.12 | Help, Rational: "…modern serifs" | "…and Didone serifs like Bodoni" | "Modern" reads as "recent" to designers |
| 7.13 | Help, Structure: "…from rational rules" | "How the letters are built: from the pen, from circles and lines, or upright and regular." | Defined rational with "rational" |
| 7.14 | Help, Stroke: "How much the strokes go thick to thin." | **Stroke contrast**: "How much strokes change from thick to thin." | Label now carries the word contrast (7.1) |
| 7.15 | Sources as surnames: "Latin, Typewolf, Bonneville, Mayer" | Short titles: **Better Web Typography · Typewolf checklist · Smashing (Bonneville) · Smashing (Mayer)** · **Universal Principles of Typography** · **Flexible Typesetting** · **Typekit** | "Latin" read as the script; "Stocks" as finance. Full citations live in the README credits |
| 7.16 | Strength words with no ranking | Help line under each: **Firm**: "Most sources agree." **Common advice**: "Several sources recommend it." **Rule of thumb**: "Helps, no guarantee." **Use with care**: "Sources disagree." | Reader couldn't rank Common advice vs Rule of thumb |
| 7.17 | Licence **No trial marks** / **Trial** | **Not marked as trial** / **Trial version · License before you ship** | "Trial marks" read as watermarks. Still accurate: we only detect trial words |
| 7.18 | Next step **Set the type** | **Next: sizes and spacing** | Says where it goes |
| 7.19 | **3 hidden by your filters · Show all** | **3 hidden by your filters · Clear filters** | Two hidden counts; "Show all" was unclear about the 42 |
| 7.20 | **42 hidden · Why?** | **42 not made for long text · Show them** (popover unchanged) | Separate control for the role rule |
| 7.21 | **No matches with these filters. Show all** | **No matches with these filters. Clear filters** | Same as 7.19 |

Landed and locked (reader said clear): the hidden-count line with Why, the Harmony and Superfamily descriptions, "Not scored. Your choice.", "License before you ship", "Pick a Display face first", "Name this brand", "Nothing here yet".

Engine follow-up: source codes in `core/src/pairing.rs` stay codes; the UI maps them to the short titles in 7.15.

## 8. Finding fonts (wave 3b, 2026-10-21)

Strings for the filter bar, Saved, Hide and the Reading changes. Checked against sections 1 to 7: the designer's word wins over the engine's ("Your fonts", not "User"; "Mac system", not "System"), no em dashes, every label reads alone (Gate D). Keys live in `Lexicon.Finder` in `Lexicon.swift`.

### 8.1 Filter bar (Display, UI and Mono grids)

| ID | Key | String | Note |
|---|---|---|---|
| 8.1 | source.yours | **Your fonts** | Fonts in ~/Library/Fonts and /Library/Fonts. Never "User" (engine word) or "Installed" (system fonts are installed too) |
| 8.2 | source.google | **Google Fonts** | The installed family is on Google's public list. Not "Web fonts": says where, not what |
| 8.3 | source.system | **Mac system** | Fonts that ship with macOS. Not "System" alone: it reads as a setting |
| 8.4 | chip.count | **Your fonts 376** | Quiet number after the label. It is what you get, with every other filter applied, so chips never read 0 just because another is on |
| 8.5 | kind.* | **Serif · Sans · Script · Display · Mono** | Matches the categories designers use. "Sans", not "Sans serif": shorter, and the grid is already crowded |
| 8.6 | more | **More** | Menu. Becomes **More · 2** when two style filters are on, so a hidden filter is never silent |
| 8.7 | more.help | **Style filters and hidden families** | Tooltip |
| 8.8 | traits.header | **Style** | Menu section: **Italic · Variable · Condensed · Wide · Trial**, each with its count. "Wide", not "Extended": the word the foundries' own specimens use |
| 8.9 | showhidden | **Show hidden** | Toggle with a count (what it would add). Not "Show excluded": the old app's manager word |
| 8.10 | search.prompt | **Search name, foundry or designer** | Display, UI, Mono. Says what it matches. Reading keeps **Search families** (it matches names only) |
| 8.11 | clear | **Clear filters** | Same as 7.19 and 7.21. Also restores the new-user default: Your fonts + Google Fonts, junk hidden |
| 8.12 | empty.nomatch | **No families match these filters.** + **Clear filters** | Grid empty state |
| 8.13 | subtitle | "Acme set in each of 376 families. **Your fonts come first.**" | Replaces "User-installed fonts come first" |

### 8.2 Saved, Hide, Unhide

| ID | Key | String | Note |
|---|---|---|---|
| 8.14 | saved | **Saved** | Chip (with a star), sidebar item, inspector button state. One word for the global star. The per-brand list stays **Shortlist** (4.6): Saved is yours everywhere, a shortlist belongs to one brand and one job |
| 8.15 | save | **Save** | Inspector button and card context menu when not saved. Tooltip on the card star |
| 8.16 | save.remove | **Remove from Saved** | Context menu and star tooltip when saved. VoiceOver: **Remove [Family] from Saved** / **Save [Family]** |
| 8.17 | saved.empty | **Nothing saved yet. Star a family to keep it here.** | Saved filter with no results. Same shape as 4.9 |
| 8.18 | hide | **Hide** | Card context menu and inspector. Not "Exclude" or "Remove": nothing is deleted |
| 8.19 | hide.help | **Hide this family from every list. Show it again from More.** | Tooltip. Says the way back (Gate E) |
| 8.20 | unhide | **Unhide** | On a hidden family (visible when Show hidden is on) |
| 8.21 | unhide.help | **Put this family back in the lists.** | Tooltip |
| 8.22 | hidden.tag | **Hidden** | Pill on a card while Show hidden is on, same style as **Trial** |
| 8.23 | source.fact | **Source** · "Your fonts · Google Fonts" | Inspector Facts row |

### 8.3 Reading

| ID | Key | String | Note |
|---|---|---|---|
| 8.24 | reading.longtext | **42 not made for long text** · **Show them** | Implements 7.20. The number is families removed by the long-text rule, from the core. With nothing removed the line reads **Showing faces made for long text** (6.10). Popover text unchanged (6.11) |
| 8.25 | sort.lesscommon | **Less common first** | Sort option. Returns now that there is popularity data (2.4 said to hide it until then). Accurate: it orders by Google's popularity rank |
| 8.26 | sort.lesscommon.help | **Faces fewer sites use. Families not on Google Fonts come first.** | Tooltip on the option and a quiet line beside the status while the sort is on. Says what "common" means and where unlisted families land (often paid or trial faces) |

### Gates for section 8

A pass (8.25 says Google, which is the data) · B pass · C pass (no em dashes; the numeric separator is a middle dot) · D pass (8.3, 8.8 read alone) · E pass (8.19 names the way back) · F pass · G n/a · H pending cold read · K pass (chips carry selection through fill and outline, and VoiceOver reads the selected state) · N pass · Q pass · R pass (no engine words: not "source", "kind", "trait", "facet")
