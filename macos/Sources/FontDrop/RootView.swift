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
                        .accessibilityLabel("Sidebar")
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                ContentPanel { ContentRouter() }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(model.screen.title)
                if model.showInspector && !model.hidesInspector {
                    InspectorRouter()
                        .frame(width: 330)
                        .modifier(PanelChrome(fill: \.glassInspector, radius: 24))
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Inspector")
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(8)
        }
        .ignoresSafeArea()
        .background(WindowConfigurator())
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { model.windowWidth = geo.size.width }
                .onChange(of: geo.size.width) { _, w in model.windowWidth = w }
        })
        .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .snappy(duration: 0.22), value: model.showSidebar)
        .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .snappy(duration: 0.22), value: model.showInspector)
        .onChange(of: model.screen) { _, _ in model.applyInspectorRule() }
        .onChange(of: model.windowWidth) { _, _ in model.applyInspectorRule() }
        .overlay { phaseOverlay }
        .sheet(isPresented: Binding(get: { model.pending != nil }, set: { if !$0 { model.pending = nil } })) {
            NameBrandSheet().environment(model)
        }
        .alert("Something went wrong", isPresented: Binding(get: { model.errorMessage != nil },
                                                            set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
        .task { await model.bootstrap() }
        .task { await ScreenshotRunner.runIfRequested(model: model) }
        .task { await Bench.runIfRequested(model: model) }
    }

    @ViewBuilder
    private var phaseOverlay: some View {
        switch model.phase {
        case .loading:
            ProgressView("Opening library").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        case .failed(let message):
            ContentUnavailableView("Could not open the library", systemImage: "exclamationmark.triangle",
                                   description: Text(message))
                .background(.background)
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
        LinearGradient(colors: [theme.windowTop.color, theme.windowBottom.color], startPoint: .top, endPoint: .bottom)
    }
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

/// Display has no stage toolbar, so its search field and the inspector toggle sit in a row above the grid.
struct DisplayTopRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            SearchField(prompt: Lexicon.Finder.searchPrompt)
                .frame(maxWidth: 280)
            Spacer(minLength: 0)
            InspectorToggle()
        }
        .padding(.horizontal, 20).padding(.top, 16)
    }
}

/// A search field on the control ground. Replaces the window toolbar's field.
struct SearchField: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    let prompt: String

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(theme.textSecondary.color)
            TextField(prompt, text: $model.search)
                .textFieldStyle(.plain).font(.system(size: 12))
            if !model.search.isEmpty {
                Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 12)) }
                    .buttonStyle(.plain).foregroundStyle(theme.textSecondary.color)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .pill()
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
        .accessibilityLabel("Inspector")
    }
}

/// Full-size content under a transparent title bar: the traffic lights sit inside the sidebar panel.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let w = view.window else { return }
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.styleMask.insert(.fullSizeContentView)
            w.isMovableByWindowBackground = true
            w.title = "FontDrop"
            // No control starts with the keyboard focus ring: it appears when you tab or arrow into one.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { w.makeFirstResponder(nil) }
        }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
}
