# Finding fonts: filters from the engine (wave 3b)

Requested 2026-10-21 (Jarrett): bring the old app's best finding methods over, so a big library doesn't drown the fonts you actually care about. Built in the core so the Mac app, the Tauri app and a future Claude connector all filter the same way.

## What the old app did (and keeps)
- **Source:** your own installed fonts first; Mac system fonts and /Library fonts were noise for brand work.
- **Junk list:** dingbats, symbol, emoji and system UI faces hidden by default (89-line list in `src/data/defaultExclusions.ts`), plus faces you hid yourself, with unhide.
- **Starred:** fonts you saved.
- **Kinds:** serif, sans, script, display, mono.
- **Style traits:** italic, condensed, extended.
- **Google Fonts:** wanted, but tagging needed a Google API key nobody set (0 fonts tagged on a real library).

## Engine design
One query, one answer with counts so the UI can show chips like "Your fonts 376":

```
families(query: FamilyQuery {
    text,                      // name, foundry or designer
    sources: [yours | google | system | all],
    kinds:   [serif | sans | script | display | mono],
    traits:  [italic | variable | condensed | wide | trial],
    saved_only,                // favorites
    include_hidden,
}) -> { families, facet_counts }
```

- **Sources**
  - **Your fonts:** ~/Library/Fonts and /Library/Fonts.
  - **Google Fonts:** the family is in Google's public font list (`fonts.google.com/metadata/fonts`, no key). Cached in Application Support, refreshed weekly.
  - **Mac system:** /System/Library/Fonts.
- **Hidden:** the built-in junk list moves into the core. Per-user hides live in a `hidden` table, with hide and unhide calls.
- **Saved:** a global `favorites` table (a star), separate from the per-brand, per-job shortlists.
- **Kinds:**
  - serif / sans from the outline detector;
  - mono from fixed pitch;
  - script and display from category and name.
- **Traits:**
  - italic: the family has an italic;
  - variable: it has fvar axes;
  - condensed and wide: from width class;
  - trial: is_trial.
- **Defaults** for a new user: Your fonts + Google Fonts, junk hidden. Mac system stays one click away.

## UI (Mac app)
A filter bar above the Display grid: source chips with counts, kind chips, a "More" menu for traits, and the search field. Saved shows as a star on cards and a sidebar item. Copy follows `docs/copy/lexicon-and-strings.md`. "Your fonts", not "User"; "Mac system", not "System".
