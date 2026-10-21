import FontDropCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 235, max: 300)
        } detail: {
            ContentRouter()
                .inspector(isPresented: $model.showInspector) {
                    InspectorRouter()
                        .inspectorColumnWidth(min: 280, ideal: 330, max: 460)
                }
        }
        .searchable(text: $model.search, prompt: "Search families")
        .navigationTitle(model.brand?.name ?? "FontDrop")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {} label: { Label("Export", systemImage: "square.and.arrow.up") }
                    .disabled(true)
                    .help("Export arrives in a later wave")
                Button { model.showInspector.toggle() } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .help("Show or hide the inspector")
            }
        }
        .overlay { phaseOverlay }
        .alert("Something went wrong", isPresented: Binding(get: { model.errorMessage != nil },
                                                            set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
        .task { await model.bootstrap() }
        .task { await ScreenshotRunner.runIfRequested(model: model) }
        .task { await Bench.runIfRequested(model: model) }
    }

    private var subtitle: String {
        switch model.screen {
        case .display, .ui, .mono: "\(model.screen.title) \u{00B7} \(model.visibleFamilies.count) families"
        case .reading: "Reading \u{00B7} \(model.shortlist("reading").count) saved"
        case .set: "Set"
        case .colors: "Colors"
        }
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
        switch model.screen {
        case .display, .ui, .mono: FamilyPickerView(screen: model.screen)
        case .reading: ReadingView()
        case .set: SetView()
        case .colors: ContentUnavailableView("Colors are parked", systemImage: "circle.lefthalf.filled")
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
        case .set, .colors:
            ContentUnavailableView("Nothing to inspect yet", systemImage: "sidebar.trailing",
                                   description: Text("The Set inspector arrives with the Set tool."))
        }
    }
}
