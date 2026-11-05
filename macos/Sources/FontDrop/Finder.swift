import FontDropCore
import Foundation

// Finding fonts: the filter the designer set, kept between launches. The core does the
// filtering (`Library.findFamilies`); this is only the chips' state and its storage.
// Words for the chips live in Lexicon.Finder.

extension Source {
    static let all: [Source] = [.yours, .google, .system]
    var key: String {
        switch self { case .yours: "yours"; case .google: "google"; case .system: "system" }
    }
    init?(key: String) {
        guard let match = Source.all.first(where: { $0.key == key }) else { return nil }
        self = match
    }
}

extension Kind {
    static let all: [Kind] = [.serif, .sans, .script, .display, .mono]
    var key: String {
        switch self { case .serif: "serif"; case .sans: "sans"; case .script: "script"; case .display: "display"; case .mono: "mono" }
    }
    init?(key: String) {
        guard let match = Kind.all.first(where: { $0.key == key }) else { return nil }
        self = match
    }
}

extension Trait {
    static let all: [Trait] = [.italic, .variable, .condensed, .wide, .trial]
    var key: String {
        switch self {
        case .italic: "italic"; case .variable: "variable"; case .condensed: "condensed"; case .wide: "wide"; case .trial: "trial"
        }
    }
    init?(key: String) {
        guard let match = Trait.all.first(where: { $0.key == key }) else { return nil }
        self = match
    }
}

/// What the chips say. A new user sees Your fonts and Google Fonts, junk hidden.
struct FinderFilter: Equatable {
    var sources: Set<Source> = [.yours, .google]
    var kinds: Set<Kind> = []
    var traits: Set<Trait> = []
    var savedOnly = false
    var showHidden = false

    static let standard = FinderFilter()

    var isStandard: Bool { self == .standard }

    /// The core's query. Lists go out in a fixed order so the same filter always asks the same question.
    func query(text: String) -> FamilyQuery {
        FamilyQuery(text: text,
                    sources: Source.all.filter(sources.contains),
                    kinds: Kind.all.filter(kinds.contains),
                    traits: Trait.all.filter(traits.contains),
                    savedOnly: savedOnly,
                    includeHidden: showHidden)
    }

    // MARK: remembered between launches

    private struct Stored: Codable {
        var sources: [String]
        var kinds: [String]
        var traits: [String]
        var savedOnly: Bool
        var showHidden: Bool
    }

    static let storageKey = "finderFilter"

    func save(to defaults: UserDefaults = .standard) {
        let stored = Stored(sources: Source.all.filter(sources.contains).map(\.key),
                            kinds: Kind.all.filter(kinds.contains).map(\.key),
                            traits: Trait.all.filter(traits.contains).map(\.key),
                            savedOnly: savedOnly, showHidden: showHidden)
        if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: Self.storageKey) }
    }

    /// The saved filter, or the standard one for a new user (or unreadable data).
    static func load(from defaults: UserDefaults = .standard) -> FinderFilter {
        guard let data = defaults.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return .standard }
        return FinderFilter(sources: Set(stored.sources.compactMap(Source.init(key:))),
                            kinds: Set(stored.kinds.compactMap(Kind.init(key:))),
                            traits: Set(stored.traits.compactMap(Trait.init(key:))),
                            savedOnly: stored.savedOnly, showHidden: stored.showHidden)
    }
}
