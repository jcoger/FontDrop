# FontDrop in SwiftUI: plan

Decided 2026-10-21 (Jarrett): the app's interface moves to SwiftUI. The Rust engine stays.

## Why SwiftUI here
- Real macOS controls: sidebar, toolbar, inspector, search, menus, Liquid Glass on macOS 26.
- **Core Text renders the fonts.** Previews match how the Mac sets type. Variable axes (opsz, wght, STYL) and `.ttc` collections are first-class. No web-view font loading.
- The Rust core (scan, name tables, classifier, pairing, evidence, benchmarks) is tested and measured. Keep it.

## Shape
```
fontdrop/
  core/        Rust library: DB, scan, classifier, pairing, evidence, user data
               exposed to Swift with UniFFI (Mozilla's Rust-to-Swift bindings)
  macos/       SwiftUI app (Xcode project), links the core as an XCFramework
  src-tauri/   current app, kept running until the SwiftUI app replaces it
```
User data (brands, shortlist per job, stars, chosen type systems) moves into the SQLite DB through the core, so both apps see the same data during the switch.

## Screens (from the Paper direction)
| Mac pattern | FontDrop |
|---|---|
| Sidebar (`NavigationSplitView`) | Brands, then jobs: Display, Reading, + UI, + Mono; Set |
| Toolbar + search field | Search families, lens controls, Export |
| Content | Display: family grid with the brand's name (and optional logo). Reading: candidates in real copy, compare 2-3 |
| Inspector (`.inspector`) | Evidence for the selected candidate, shortlist for this job, Claude notes |
| Set | Scale, measure, line height, x-height and optical-style switch, live specimen |

## Waves
0. **De-risk (now):** design the three core screens in Paper with Mac patterns, light and dark. In parallel, a spike: Rust core over UniFFI into a SwiftUI window that lists every family rendered with Core Text, and scrolls 5,000+ fonts smoothly.
1. Extract `core/` from `src-tauri/`, generate Swift bindings, keep Tauri building.
2. App shell: sidebar, toolbar, search, brand switcher, settings.
3. Display picker.
4. Reading: lenses, side-by-side compare, inspector evidence, shortlist per job, "Like my picks".
5. Set: scale, measure, axes (opsz, STYL), live specimen.
6. Export (CSS variables, Tailwind theme, Paper-ready spec); Brand Colors stays parked.
7. Ship: signing, notarisation, DMG, then retire the Tauri app.

## Learning SwiftUI along the way
Each wave introduces a few concepts on purpose (views and state, lists and grids, navigation, async loading, Core Text). Explanations stay short and tied to the screen being built.
