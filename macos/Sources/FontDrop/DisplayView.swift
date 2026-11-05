import FontDropCore
import SwiftUI

/// The grid used by Display, UI and Mono: every family, set in the brand's name.
/// `screen` decides which job "Use for ..." chooses a face for.
struct FamilyPickerView: View {
    @Environment(AppModel.self) private var model
    let screen: Screen
    @FocusState private var focused: Bool
    @State private var keyboardNav = false       // the focus ring shows once a key is used, not after a click
    @State private var gridWidth: CGFloat = 800

    private static let cellMin: CGFloat = 220, cellSpacing: CGFloat = 14
    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 14)]

    var body: some View {
        @Bindable var model = model
        let families = screen == .display ? model.displayGridFamilies : model.visibleFamilies
        let chosen = model.chosen(screen)
        let sample = model.sampleText
        let tick = model.fontTick

        VStack(spacing: 0) {
        FilterBar()
            .padding(.horizontal, 20).padding(.vertical, 10)
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Choose the \(screen.title) face").font(.title2.weight(.semibold))
                    Text(subtitle(count: families.count))
                        .font(.callout).foregroundStyle(.secondary)
                }
                if families.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(families) { family in
                            FamilyCard(family: family, sample: sample, tick: tick,
                                       isSelected: model.selectedFamily == family.name,
                                       isChosen: chosen == family.name,
                                       showFocus: keyboardNav && focused && model.selectedFamily == family.name,
                                       isSaved: model.isSaved(family.name),
                                       isHidden: model.isHidden(family.name),
                                       reason: screen == .display ? model.displayReason(for: family.name) : nil,
                                       tuned: isTuned(family),
                                       toggleSaved: { Task { await model.setFavorite(family.name, on: !model.isSaved(family.name)) } },
                                       toggleHidden: { Task { await model.setHidden(family.name, hidden: !model.isHidden(family.name)) } })
                                .id(family.name)
                                .onTapGesture { keyboardNav = false; model.selectedFamily = family.name; focused = true }
                        }
                    }
                }
            }
            .padding(20)
            .background(GeometryReader { geo in Color.clear.onChange(of: geo.size.width, initial: true) { _, w in gridWidth = w - 40 } })
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()          // the ring is drawn on the card, distinct from the selection ring
        .onAppear { focused = true }
        .onChange(of: model.focusListTick) { _, _ in focused = true }
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .return, .space]) { press in
            guard press.modifiers.isEmpty else { return .ignored }
            switch press.key {
            case .return:
                guard model.canUseSelected else { return .ignored }
                Task { await model.useSelected() }
            case .space:
                guard model.selectedFaceName != nil else { return .ignored }
                model.togglePreview()
            default:
                let dir: GridNav.Direction = press.key == .leftArrow ? .left : press.key == .rightArrow ? .right : press.key == .upArrow ? .up : .down
                keyboardNav = true
                let cols = GridNav.columns(width: gridWidth, minimum: Self.cellMin, spacing: Self.cellSpacing)
                let index = families.firstIndex { $0.name == model.selectedFamily }
                if let next = GridNav.move(count: families.count, from: index, dir, columns: cols) {
                    model.selectedFamily = families[next].name
                    withAnimationIfAllowed { proxy.scrollTo(families[next].name) }
                    announce(families[next].name)
                }
            }
            return .handled
        }
        // Open on the chosen face, so the grid starts where you left off.
        .task(id: "\(model.brandID ?? 0)/\(screen.rawValue)/\(model.fontsReady)") {
            if model.fontsReady, let name = model.chosen(screen) { proxy.scrollTo(name, anchor: .center) }
        }
        // Pairs with: rank every family against the chosen Text face (reloads when that face or the library changes).
        .task(id: "\(model.readingFamily?.fontId ?? "")/\(model.libraryRevision)/\(model.fontsReady)") {
            if screen == .display, model.fontsReady { await model.loadDisplayPairs() }
        }
        }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.scanningEmptyLibrary {
            ProgressView(Lexicon.Scan.scanningFonts)
                .frame(maxWidth: .infinity, minHeight: 240)
        } else if model.filter.savedOnly && model.search.isEmpty && model.filter.kinds.isEmpty && model.filter.traits.isEmpty {
            ContentUnavailableView(Lexicon.Finder.savedEmpty, systemImage: "star")
        } else {
            ContentUnavailableView {
                Label(Lexicon.Finder.noMatches, systemImage: "line.3.horizontal.decrease.circle")
            } actions: {
                Button(Lexicon.clearFilters) { model.filter = .standard; model.search = "" }
            }
        }
    }

    /// The designer changed this family's settings. The grid still draws its default style (an equal comparison),
    /// and the card says so with a small "Tuned" mark (UX audit U2).
    private func announce(_ name: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: Lexicon.Keyboard.selectedAnnouncement(name), .priority: NSAccessibilityPriorityLevel.low.rawValue])
    }

    private func isTuned(_ family: FamilySummary) -> Bool {
        guard let job = screen.job else { return false }
        return model.typeSettings.isModified(model.settingsKey(job, family.name), job: job)
    }

    /// Only what is on screen (UX audit C4, S5). The brand's own sample text is not the brand name once the designer typed one.
    private func subtitle(count: Int) -> String {
        let brand = model.brand?.name ?? "Your brand name"
        if screen == .display, model.displaySort == .pairsWith, model.displayPairsAreCurrent, let text = model.readingFamily?.name {
            return Lexicon.Pairs.subtitle(brand: brand, count: count, text: text)
        }
        return Lexicon.R4.familiesLine(brand: brand, count: count)
    }
}

/// One family card. Takes plain values and holds no state.
struct FamilyCard: View {
    @Environment(\.theme) private var theme
    let family: FamilySummary
    let sample: String
    let tick: Int
    let isSelected: Bool
    let isChosen: Bool
    var showFocus = false            // keyboard focus is on this card (arrow keys), drawn as the system focus ring
    let isSaved: Bool
    let isHidden: Bool
    var reason: String?              // Pairs with: why this face pairs with the Text face, in place of the style count
    var tuned = false                // the designer changed this family's settings; the card still draws the default style
    let toggleSaved: () -> Void
    let toggleHidden: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            FontText(path: family.filePath, text: sample, size: 54, fallbacks: [family.name], tick: tick)
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 124, maxHeight: 124)
                // The star shows on hover and when saved, nowhere else (UX audit S3).
                .overlay(alignment: .topTrailing) {
                    if isSaved || hovering { StarButton(name: family.name, isOn: isSaved, toggle: toggleSaved) }
                }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(family.name).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(reason ?? "\(family.styleCount) \(family.styleCount == 1 ? "style" : "styles")")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                if isChosen {
                    Text(Lexicon.Reading.current).font(.system(size: 11)).foregroundStyle(theme.textSecondary.color)
                } else if isHidden {
                    TagPill(text: Lexicon.Finder.hidden)
                } else if family.isTrial {
                    TagPill(text: "Trial")
                }
                if tuned {
                    TagPill(text: Lexicon.R4.tuned).help(Lexicon.R4.tunedHelp)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
        }
        .onHover { hovering = $0 }
        .contextMenu {
            Button(isSaved ? Lexicon.Finder.removeSaved : Lexicon.Finder.save, systemImage: isSaved ? "star.slash" : "star", action: toggleSaved)
            Button(isHidden ? Lexicon.Finder.unhide : Lexicon.Finder.hide, systemImage: isHidden ? "eye" : "eye.slash", action: toggleHidden)
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.controlGround.color))
        .overlay { if isSelected {      // board 16 option B: a 1.5 pt ring, grids only
            RoundedRectangle(cornerRadius: 12).strokeBorder(theme.textPrimary.color, lineWidth: 1.5)
        } }
        .overlay { if showFocus {
            RoundedRectangle(cornerRadius: 14, style: .continuous).inset(by: -3)
                .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2)
        } }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: isSaved ? Lexicon.Finder.removeSaved : Lexicon.Finder.save, toggleSaved)
    }
}

