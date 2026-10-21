# SwiftUI for a React designer

Short notes on what the FontDrop app uses, with the React idea each one maps to and the file where you can see it. Open the file next to this page and read the real code.

Folder: `macos/Sources/FontDrop/`.

## The big picture

| React world | This app |
|---|---|
| `src/main.tsx` + `<App />` | `FontDropApp.swift`. `@main` marks the entry point. `WindowGroup` is the window. |
| A component tree | A view tree. `RootView` holds the sidebar, content and inspector. |
| A store (Zustand, Redux) | `AppModel.swift`. One object holds the app's state. |
| `fetch()` to your API | `core` calls (`lib.listFamilies()`). The Rust engine, behind generated Swift. |
| `package.json` | `project.yml` (the spec) and `FontDrop.xcodeproj` (what Xcode opens). |

## View ~ component

A `View` is a struct with a `body`. `body` returns what to draw. It re-runs when its inputs change, like a function component.

- `Components.swift`: `TagPill`, `EvidenceChip`, `InspectorSection`. Small pieces with props (`let text: String`).
- Props are plain `let` properties. There is no `props` object.
- Children go in `{ }` braces (`@ViewBuilder`), like `children`.
- Modifiers (`.padding()`, `.font()`) chain onto a view. Order matters, like wrapping in another `<div>`. `.padding().background()` and `.background().padding()` look different.
- `VStack` / `HStack` / `ZStack` are flex column, flex row, and stacked layers.

## @State and @Observable ~ useState and a store

- `@State private var showNewBrand = false` (`SidebarView.swift`) is `useState`. It lives inside one view. Changing it redraws that view.
- `@Observable final class AppModel` (`AppModel.swift`) is a shared store. Any view that reads `model.brands` redraws when `brands` changes. SwiftUI tracks what each view reads, so there are no selectors to write.
- `@Environment(AppModel.self) private var model` is `useContext`. `FontDropApp.swift` puts the model in with `.environment(model)`. Every view below gets it.
- `@Bindable var model = model` (`RootView.swift`, `ReadingView.swift`) lets you write `$model.search`. The `$` makes a two-way binding, like passing `value` and `onChange` together. Controls such as `TextField` and `Picker` take bindings.
- `@MainActor` means "only touch this from the main thread". The UI lives there. It is why `AppModel` is safe to read from views.

## .task ~ useEffect

`.task { ... }` runs async work when a view appears and cancels it when the view goes away.

- `.task { await model.bootstrap() }` (`RootView.swift`) is `useEffect(() => { load() }, [])`.
- `.task(id: someValue)` re-runs when the value changes. That is `useEffect` with a dependency. `ReadingView.swift` reloads candidates when the Display face changes. `DisplayView.swift` reloads the inspector detail when the selected family changes.
- `await` is `await`. `Task.detached { }` runs work off the main thread, like a web worker you can call inline. `AppModel.background(_:)` wraps this for every core call, so SQLite never blocks the UI.

## Why fonts are preloaded (the one rule to remember)

The first spike loaded each font inside its row and wrote state when it finished. That caused multi-second freezes. So now:

- `FontLoader.swift` keeps a cache. `FontLoader.preload` fills it in batches off the main thread.
- `FontText` (`Components.swift`) only reads that cache. No state, no effects.

In React terms: do the data fetch in the store, hand rows plain props, keep rows free of effects.

## NavigationSplitView ~ a three-pane layout

`RootView.swift`. `NavigationSplitView { sidebar } detail: { content }` is the macOS sidebar plus content layout. It gives you the real sidebar material, the collapse button and the window title bar for free. In React you would build this with CSS grid and write the collapse logic yourself.

`SidebarView.swift` is a `List(selection:)`. The selection binding is `model.screen`, so clicking a row changes the screen. `.tag(screen)` says which value a row stands for, like `value=` on a radio.

`ContentRouter` and `InspectorRouter` (`RootView.swift`) are a `switch` on the current screen. That is your `routes` table.

## .inspector ~ a right-hand details panel

`.inspector(isPresented: $model.showInspector) { ... }` (`RootView.swift`) adds the right panel and its show/hide state. Apple's own apps use it for "Get Info". The content is a normal view. `DisplayView.swift` has `FamilyInspector`. `ReadingView.swift` has `ReadingInspector`.

## LazyVGrid ~ a virtualized CSS grid

`DisplayView.swift` and `ReadingView.swift`. `LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))])` is `grid-template-columns: repeat(auto-fill, minmax(220px, 1fr))`, plus it only builds the cards that are on screen (like `react-window`). 700 families scroll without lag because of the `Lazy` part.

## .searchable ~ a search input wired to state

`.searchable(text: $model.search, prompt: "Search families")` (`RootView.swift`) puts a native search field in the toolbar. Typing writes `model.search`. The grid and the Reading list filter by it. No input component to write.

## Toolbar and menus

- `.toolbar { ToolbarItem { ... } }` puts controls in the window's toolbar. Each screen adds its own: the category picker in `DisplayView.swift`, the four lens menus in `ReadingView.swift` (`LensToolbar`). Switch screens and the toolbar swaps. It is like a component rendering into a portal.
- `Menu { Picker(...) } label: { ... }` is a dropdown. `LensMenu` in `ReadingView.swift` is the "How much contrast: Clear" pill.

## Plain logic you can test

`Lenses.swift` has the Reading filters as pure functions (`LensEngine.apply`). No views, no state. `Tests/FontDropTests/LensEngineTests.swift` tests them with `macos/build.sh --test`. Same idea as a reducer plus a unit test.

## Core Text ~ the browser's font engine

The old Tauri app used CSS `@font-face`. This app asks macOS directly: `CTFontManagerCreateFontDescriptorsFromURL` reads a file, `Font(CTFont)` hands it to SwiftUI (`FontLoader.swift`, `Components.swift`). It reads variable axes (`CTFontCopyVariationAxes`) and x-height too. What you see is what the Mac sets.

## Debug flags

`AppModel.swift` (`LaunchOptions`) and `Bench.swift`. `--db <file>` points at a copy of the library. `--screenshot out.png --screen reading --appearance dark` renders a PNG without screen-recording permission. `--bench` scrolls the Display grid and prints frame times. See `macos/README.md`.
