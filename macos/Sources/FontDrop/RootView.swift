import FontDropCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var model = model
        ZStack {
            WindowBackdrop()
            HStack(spacing: 8) {
                if model.showSidebar {
                    SidebarView()
                        .frame(width: 235)
                        .modifier(PanelChrome(fill: \.glassSidebar, radius: 24))
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(Lexicon.sidebarRegion)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                ContentPanel { ContentRouter().screenTransition() }
                    .padding(.leading, ReadingLayout.hiddenSidebarInset(sidebarShown: model.showSidebar))   // clears the traffic lights
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(model.screen.title)
                if model.showInspector && !model.hidesInspector {
                    InspectorRouter().selectionFade(model.inspectorFadeKey)
                        .frame(width: 330)
                        .modifier(PanelChrome(fill: \.glassInspector, radius: 24))
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(Lexicon.inspectorRegion)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(8)
        }
        .ignoresSafeArea()
        .background(WindowConfigurator())
        .background { ZoomInAlias() }
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { model.windowWidth = geo.size.width }
                .onChange(of: geo.size.width) { _, w in model.windowWidth = w }
        })
        .animation(Motion.ok(Motion.standard), value: model.showSidebar)
        .animation(Motion.ok(Motion.standard), value: model.showInspector)
        .onChange(of: model.screen) { _, _ in model.applyInspectorRule() }
        .onChange(of: model.windowWidth) { _, _ in model.applyInspectorRule() }
        .onChange(of: model.showSidebar) { _, _ in model.applyInspectorRule() }
        .overlay { phaseOverlay }
        .overlay { if let state = model.preview { FacePreview(state: state) } }
        .onChange(of: model.screen) { _, _ in model.closePreview() }
        .onChange(of: model.brandID) { _, _ in model.closePreview() }
        .sheet(isPresented: Binding(get: { model.pending != nil }, set: { if !$0 { model.pending = nil } })) {
            NameBrandSheet().environment(model)
        }
        .alert("Something went wrong", isPresented: Binding(get: { model.errorMessage != nil },
                                                            set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
        .task { model.appearance.apply() }
        .task { await model.bootstrap() }
        .task { await ScreenshotRunner.runIfRequested(model: model) }
        .task { await Bench.runIfRequested(model: model) }
        .task { await ExportRunner.runIfRequested(model: model) }
    }

    @ViewBuilder
    private var phaseOverlay: some View {
        switch model.phase {
        case .loading:
            ProgressView("Opening library").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        case .failed(let message):
            LibraryProblemView(problem: LibraryOpenProblem.classify(error: message, dbPath: model.dbPath))
        case .ready:
            EmptyView()
        }
    }
}

/// Picks the content column for the current screen.
struct ContentRouter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.showsScanScreen {
            ScanScreen()
        } else if model.libraryIsEmpty {
            EmptyLibraryState()
        } else {
            switch model.screen {
            case .display, .ui, .mono: FamilyPickerView(screen: model.screen)
            case .reading: ReadingView()
            case .set: SetView()
            case .colors: EmptyView()
            }
        }
    }
}

/// Picks the inspector for the current screen.
struct InspectorRouter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.screen {
        case .display, .ui, .mono: FamilyInspector(screen: model.screen)
        case .reading: ReadingInspector()
        case .set: SetInspector()
        case .colors: EmptyView()
        }
    }
}

// MARK: - Window and panels

/// The window behind the panels: a quiet two-stop gradient from the theme.
struct WindowBackdrop: View {
    @Environment(\.theme) private var theme
    var body: some View {
        // The empty chrome between the panels drags the window. This sits behind the panels, so it only ever gets
        // the gutters. It is a SwiftUI gesture, not an NSView: an NSView overlay is hit before any SwiftUI content.
        LinearGradient(colors: [theme.windowTop.color, theme.windowBottom.color], startPoint: .top, endPoint: .bottom)
            .windowDraggable(appKitFallback: false)
    }
}

/// Command-+ also zooms the Text stage in. The View menu holds Command-= (no Shift on a US keyboard).
struct ZoomInAlias: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Button("") { model.stageZoom.zoomIn() }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(!model.canZoomStage || !model.stageZoom.canZoomIn)
            .opacity(0).frame(width: 0, height: 0).allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Makes an empty area drag the window (and double-click zoom it). Only views that say so move it: the dial, the
/// sliders and the colour area never do (the window's own "drag from anywhere" is off, see `WindowChrome`).
///
/// macOS 15 and later: SwiftUI's `WindowDragGesture`, which belongs to the view it is put on and nothing else.
/// macOS 14: an AppKit strip behind the view (`WindowDragHandle`). It sits behind the view's own area only, so
/// callers use this on small empty strips, never on a whole window.
struct WindowDraggable: ViewModifier {
    /// False for a big area (the window backdrop): on macOS 14 it then drags nothing rather than cover the content.
    var allowsAppKitFallback = true

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .onTapGesture(count: 2) { NSApp.keyWindow?.performZoom(nil) }
        } else if allowsAppKitFallback {
            content.background(WindowDragHandle())
        } else {
            content
        }
    }
}

extension View {
    func windowDraggable(appKitFallback: Bool = true) -> some View { modifier(WindowDraggable(allowsAppKitFallback: appKitFallback)) }
}

/// The macOS 14 form of a drag strip: an NSView that moves the window. Never overlaid on content.
struct WindowDragHandle: NSViewRepresentable {
    final class Handle: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { window?.performZoom(nil) } else { window?.performDrag(with: event) }
        }
    }
    func makeNSView(context: Context) -> NSView { Handle() }
    func updateNSView(_ view: NSView, context: Context) {}
}

/// A rounded glass panel with grain (dark only). Clips its content to the corner.
struct PanelChrome: ViewModifier {
    let fill: KeyPath<Theme, RGBA>
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(Grain().clipShape(shape))
            .clipShape(shape)
            .glass(fill, in: shape)
    }
}

/// The middle panel: the white (or #1C1C1B) page the list, the stage and the Display grid sit on.
struct ContentPanel<Content: View>: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        VStack(spacing: 0) {
            if (model.screen == .display || model.screen == .ui || model.screen == .mono) && !model.hidesInspector { DisplayTopRow() }
            content
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.panelContent.color)
        .background(Grain())
        .clipShape(shape)
        .overlay { if let ring = theme.panelRing { shape.strokeBorder(ring.color, lineWidth: 1) } }
        .shadow(color: theme.panelShadow.first?.color.color ?? .clear, radius: theme.panelShadow.first?.radius ?? 0, y: theme.panelShadow.first?.y ?? 0)
        .shadow(color: theme.panelShadow.last?.color.color ?? .clear, radius: theme.panelShadow.last?.radius ?? 0, y: theme.panelShadow.last?.y ?? 0)
    }
}

/// Display has no stage toolbar, so its search field, the Sort menu and the inspector toggle sit in a row above the grid.
struct DisplayTopRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            SearchField(prompt: Lexicon.Finder.searchPrompt)
                .frame(maxWidth: 280)
            Spacer(minLength: 0)
            DisplaySortMenu()
            InspectorToggle()
        }
        .padding(.horizontal, 20).padding(.top, 16)
    }
}

/// A search field on the control ground. Replaces the window toolbar's field.
struct SearchField: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @FocusState private var focused: Bool
    let prompt: String

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(theme.textSecondary.color)
            TextField(prompt, text: $model.search)
                .textFieldStyle(.plain).font(.system(size: 12))
                .focused($focused)
                .onChange(of: model.focusSearchTick) { _, _ in focused = true }       // command-F
                .onExitCommand {                                                         // Escape: clear what is typed, then give the keys back to the list
                    if model.search.isEmpty { focused = false; model.requestListFocus() } else { model.search = "" }
                }
                .onSubmit { focused = false; model.requestListFocus() }              // Return: look at the results
            if !model.search.isEmpty {
                Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 12)) }
                    .buttonStyle(.plain).foregroundStyle(theme.textSecondary.color)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .pill()
        .overlay { if focused { Capsule().strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2) } }
    }
}

/// Shows or hides the inspector. The window has no toolbar any more, so the button lives with the content.
struct InspectorToggle: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        Button { model.inspectorTouched = true; model.showInspector.toggle() } label: {
            Image(systemName: "sidebar.trailing").font(.system(size: 14))
                .foregroundStyle(theme.textSecondary.color)
                .frame(width: 28, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show or hide the inspector")
        .accessibilityLabel(Lexicon.inspectorRegion)
    }
}

/// How the window is set up.
enum WindowChrome {
    /// Full-size content under a transparent title bar: the traffic lights sit inside the sidebar panel.
    /// `isMovableByWindowBackground` stays off: with it on, a drag that starts on the dial, a slider or the colour
    /// area can move the window. Only `windowDraggable()` areas move it.
    @MainActor
    static func configure(_ w: NSWindow) {
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.styleMask.insert(.fullSizeContentView)
        w.isMovableByWindowBackground = false
        w.title = "FontDrop"
        WindowButtons.install(on: w)
    }

    /// The traffic lights sit this far from the sidebar panel's left and top edges (the panel is 8 pt from the window's).
    static let buttonInset: CGFloat = 20
    static let panelGutter: CGFloat = 8
}

/// Puts the close, minimise and zoom buttons inside the sidebar panel (board 17), and keeps them there.
/// AppKit lays them out again on resize and when full screen ends, so this runs after each of those.
/// The strip they sit in is made tall enough to hold them: a button outside its parent's frame cannot be clicked.
@MainActor
final class WindowButtons {
    private static var placers: [ObjectIdentifier: WindowButtons] = [:]
    private weak var window: NSWindow?
    private var tokens: [NSObjectProtocol] = []

    static func install(on window: NSWindow) {
        let key = ObjectIdentifier(window)
        if let existing = placers[key] { existing.place(); return }
        let p = WindowButtons(window)
        placers[key] = p
        p.place()
    }

    private init(_ window: NSWindow) {
        self.window = window
        let names: [Notification.Name] = [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
                                          NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification,
                                          NSWindow.didChangeScreenNotification, NSWindow.didDeminiaturizeNotification]
        for n in names {
            tokens.append(NotificationCenter.default.addObserver(forName: n, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.place(); DispatchQueue.main.async { self?.place() } }
            })
        }
    }

    /// Frames for the three buttons, from the top-left of the strip that holds them. Pure, for the test.
    static func layout(buttonSize: CGSize, step: CGFloat, stripHeight: CGFloat) -> [CGPoint] {
        let x0 = WindowChrome.panelGutter + WindowChrome.buttonInset
        let y = stripHeight - (WindowChrome.panelGutter + WindowChrome.buttonInset) - buttonSize.height
        return (0..<3).map { CGPoint(x: x0 + CGFloat($0) * step, y: y) }
    }

    func place() {
        guard let w = window, !w.styleMask.contains(.fullScreen),
              let close = w.standardWindowButton(.closeButton),
              let mini = w.standardWindowButton(.miniaturizeButton),
              let zoom = w.standardWindowButton(.zoomButton),
              let titlebar = close.superview, let container = titlebar.superview,
              let content = w.contentView else { return }
        let size = close.frame.size
        let step = max(mini.frame.minX - close.frame.minX, size.width + 6)
        let stripHeight = WindowChrome.panelGutter + WindowChrome.buttonInset + size.height + WindowChrome.panelGutter
        let top = content.frame.maxY
        let frame = NSRect(x: 0, y: top - stripHeight, width: container.superview?.bounds.width ?? w.frame.width, height: stripHeight)
        if container.frame != frame { container.frame = frame }
        if titlebar.frame != container.bounds { titlebar.frame = container.bounds }
        let points = Self.layout(buttonSize: size, step: step, stripHeight: stripHeight)
        for (b, p) in zip([close, mini, zoom], points) where b.frame.origin != p { b.setFrameOrigin(p) }
    }
}

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let w = view.window else { return }
            WindowChrome.configure(w)
        }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
}
