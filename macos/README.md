# FontDrop for macOS (SwiftUI)

The SwiftUI app. The Rust engine in `core/` does the work (library DB, classifier, pairing, brands, shortlists). SwiftUI draws it. Fonts are drawn by Core Text.

Wave 2: app shell, Display, Reading, a placeholder Set. Wave 3: choosing that lands, the pair shown together, a live type playground, presentation templates, designer-word copy. See `LEARN.md` for SwiftUI notes mapped to React.

| Light | Dark |
|---|---|
| ![Display, light](docs/wave2-display-light.png) | ![Display, dark](docs/wave2-display-dark.png) |
| ![Reading, light](docs/wave2-reading-light.png) | ![Reading, dark](docs/wave2-reading-dark.png) |

## Wave 3

| Display, playground open (variable font) | Reading, Article template |
|---|---|
| ![Display with playground](docs/wave3-display-playground.png) | ![Reading, Article](docs/wave3-reading-article.png) |

| Reading, App UI template | No brand yet: Name this brand |
|---|---|
| ![Reading, App UI](docs/wave3-reading-appui.png) | ![Name this brand sheet](docs/wave3-name-brand-sheet.png) |

- **Choosing never errors.** With no brand, "Use for ..." opens a "Name this brand" sheet (prefilled), creates the brand, selects it, then applies the choice.
- **Choosing lands.** The inspector footer becomes "Display face set" with Undo (puts back the previous face, or clears) and a next step: "Find a Reading face" or "Next: sizes and spacing". The check bounces once, not with Reduce Motion on.
- **More candidates.** Reading asks the core for a flat ranked list (`Library.font_candidates`, one per family, 40 at a time, "Show more" adds 40). Filters still run in the app. A footer says how many the filters hide and offers "Clear filters". "Show them" lifts the long-text rule (display cuts, condensed, mono, families without italic or bold).
- **The pair, not separate fonts.** Every Reading card draws the Display face (with its playground settings) for headlines and the candidate for body and interface text. No Display face chosen: Reading says so and links to Display.
- **Playground** (inspector, Display and Reading): style picker, variable axes read with `CTFontCopyVariationAxes` (names, min, max, default, hidden axes skipped), size, tracking (em), line height, and OpenType features read with `CTFontCopyFeatures` (stylistic sets with the font's own names, small caps, figure style and spacing, contextual alternates, ligatures). It builds a `CTFontDescriptor` with variation and feature attributes. Nothing is registered with the system. Reset per group.
- **Playground persistence.** Settings are saved per brand + job + family as JSON next to the library DB (`<db path>.playground.json`, so a test DB copy gets its own file). This is a candidate to move into the core and the DB later, when Set needs the same numbers.
- **Templates** (`Sources/FontDrop/Templates/`): Article, Landing hero, App UI, Poster. To add one: a new file with a small `View` that takes a `PairContext` and a `static let descriptor`, then one line in `Templates.all` (`Template.swift`). Sample copy is neutral.
- **Copy.** All engine-to-designer wording lives in `Lexicon.swift` (source: `docs/copy/lexicon-and-strings.md`, sections 1 to 7). Book terms appear only in help popovers.

Core additions: `font_candidates` (flat ranked list, unit-tested for limit, one per family, hidden and unfit exclusion) and `choice_clear`. `font_pairs` and the Tauri commands are unchanged.

## Run it in Xcode

1. Build the Rust core once (about 3 minutes the first time): `core/build-swift.sh`. It writes the XCFramework and the generated Swift into `macos/FontDropCore` (git-ignored). Needs Rust (`~/.cargo/bin/cargo`).
2. Open `macos/FontDrop.xcodeproj`.
3. Pick the **FontDrop** scheme and **My Mac**, then press Run (Cmd-R). If Xcode asks for a signing team, choose "Sign to Run Locally" under Signing & Capabilities. No account is needed.

The app opens the shared library DB (`~/Library/Application Support/co.dynolabs.fontdrop/fontdrop.db`), the same one the Tauri app uses. Opening runs schema migrations. Brands, shortlists and choices are saved there.

To work on a copy instead (do this for anything that writes test data):

```
sqlite3 "$HOME/Library/Application Support/co.dynolabs.fontdrop/fontdrop.db" ".backup '/tmp/fontdrop-copy.db'"
macos/build/FontDrop.app/Contents/MacOS/FontDrop --db /tmp/fontdrop-copy.db
```

In Xcode: Product > Scheme > Edit Scheme > Run > Arguments, add `--db /tmp/fontdrop-copy.db` (or the environment variable `FONTDROP_DB`). DB path order: `--db`, `$FONTDROP_DB`, the shared DB.

## Build from the terminal

```
macos/build.sh                  # macos/build/FontDrop.app (runs core/build-swift.sh first if the XCFramework is missing)
macos/build.sh --run            # build and open
macos/build.sh --test           # unit tests (Lens filters)
macos/build.sh --rebuild-core   # regenerate the Rust lib and Swift bindings, then build
```

`project.yml` is the XcodeGen spec. `build.sh` regenerates `FontDrop.xcodeproj` from it when it is newer (`brew install xcodegen`). Both are committed. Bundle id `co.dynolabs.fontdrop.mac`. macOS 14+, Apple Silicon (the core XCFramework is arm64 only).

## Developer flags

| Flag | What it does |
|---|---|
| `--db <path>` | Use this library DB. |
| `--brand <name>` | Start with this brand selected. |
| `--refresh` | Rescan the disk and reclassify before showing the library (can take a minute or more). |
| `--screenshot <png> [--screen display\|reading\|set] [--appearance light\|dark] [--select <family>] [--no-inspector] [--template article\|hero\|appui\|poster] [--open-playground]` | Render the window to a PNG and quit. It captures the app's own window in-process (no screen-recording permission). Sheets are captured and composited onto it. Playground settings are read, never written, in this mode. |
| `--demo-choose <family>` | With `--screenshot`: start with no brand and press "Use for Display" on this family, so the Name this brand sheet shows. `--no-brand` alone starts with no brand selected. |
| `--bench` | Print load times and scroll frame times for the Display grid and Reading, then quit. |

Screenshots in `docs/` were made with `--db <copy>`, brand "Acme" (a demo brand added to the copy only).

## How it is put together

```
Sources/FontDrop/
  FontDropApp.swift   entry point, window
  AppModel.swift      the store: library, brands, choices, shortlist, candidates; launch options
  FontLoader.swift    Core Text loader and cache (preloaded off the main thread)
  Lenses.swift        Reading lenses: pure filter and sort over core evidence
  RootView.swift      NavigationSplitView + inspector + toolbar + routers
  SidebarView.swift   Brands, Type, Set, Colors
  DisplayView.swift   family grid (Display, UI, Mono) and its inspector
  ReadingView.swift   lens menus, candidate cards, evidence inspector, shortlist
  SetView.swift       placeholder
  TypeSettings.swift  playground settings, what a font file offers (axes, features), JSON store
  FaceText.swift      FaceSpec + FaceText: text drawn with playground settings, font memo
  Playground.swift    the inspector's playground group
  Lexicon.swift       engine words to designer words, help text, strings
  Templates/          Article, Landing hero, App UI, Poster + registry
  Components.swift    FontText, chips, tags, flow layout, inspector section
  Bench.swift         --screenshot and --bench
Tests/FontDropTests/  lens and lexicon tests, choose/undo flow, playground settings (neutral fixture names)
FontDropCore/         local Swift package: generated UniFFI bindings + XCFramework (git-ignored output)
```

Rules that came out of the spike (wave 0):

- Fonts load in the model, off the main thread, in batches (`FontLoader.preload`). Rows read the cache and never write state. Loading from each row caused multi-second stalls.
- All DB work goes through `AppModel.background`, a detached task. The UI thread never waits on SQLite.

## Measurements (wave 2)

Apple Silicon Mac, 60 Hz display, window 1360x860. The `--bench` harness scrolls the real `NSScrollView` behind the grid at 6,000 pt/s on a display link.

Current library (rescanned DB copy: 699 families, 5,975 files):

- Open and migrate 95 ms. `list_families` + `list_fonts` + brands 66 ms. Preload 699 family fonts 59 ms.
- Display grid, 5 passes of 42,558 pt (426 frames each): p50 = p95 = p99 = 16.7 ms. 0 to 1 late frames per pass, max 33 ms. No severe hitches.
- Reading (11 candidates): ready 289 ms after switching to the screen; scroll passes 8 to 9 frames, max 33 ms.
- Memory: 80 MB after load, 120 MB after scrolling the grid.

Stress case (stale DB copy: 3,339 "families", one card per style file):

- Preload 245 ms. Five passes of 206,238 pt (about 2,060 frames each): p99 16.7 ms. Two passes had a 160 and a 207 ms frame (4 and 1 severe frames out of about 2,060). Memory 113 to about 300 MB.

## Credits for the copy

Sources named in the Why list as short titles: Better Web Typography (Matej Latin), Universal Principles of Typography (Elliot Jay Stocks), Typewolf checklist (Jeremiah Shoaf), Flexible Typesetting (Tim Brown), Smashing Book 6 (chapters by Douglas Bonneville and Dan Mayer), Typekit and Monotype guidance.

## Known gaps

See the final report of wave 2 in the PR/handoff notes. Short list: no Claude advise box, no "Like my picks" sort, no popularity data (so "Unexpected first" uses fewer shortcut reasons), UI and Mono reuse the Display grid, Export is a disabled placeholder. Wave 3 gaps: "N not made for long text" has no count yet (needs a core call), Set does not use the templates yet, only the first face of a .ttc collection is read, the Display card ignores the size slider.
