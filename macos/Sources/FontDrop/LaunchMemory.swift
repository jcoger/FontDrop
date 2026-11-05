import Foundation

/// What FontDrop remembers per brand between launches: the last screen, the Display face and Text candidate on
/// show, and the template. Stored by brand id, never globally, so each brand lands where you left it.
///
/// React: a per-key slice of localStorage with a pure "where do we land" function beside it.
struct BrandMemory: Codable, Equatable {
    var screen: String?
    /// Display grid selection (a family name).
    var display: String?
    /// Text list selection (a family name; candidate ids change between scans, names do not).
    var candidate: String?
    var template: String?
}

enum LaunchMemory {
    static func key(_ brand: Int64) -> String { "brandMemory.\(brand)" }

    static func load(_ defaults: UserDefaults, brand: Int64) -> BrandMemory? {
        defaults.data(forKey: key(brand)).flatMap { try? JSONDecoder().decode(BrandMemory.self, from: $0) }
    }

    static func save(_ memory: BrandMemory, _ defaults: UserDefaults, brand: Int64) {
        if let data = try? JSONEncoder().encode(memory) { defaults.set(data, forKey: key(brand)) }
    }

    /// The screen a brand opens on. Set with no face chosen has nothing to show, so it falls back to Display.
    /// A brand with nothing stored opens on Display.
    static func landingScreen(stored: Screen?, hasDisplay: Bool, hasText: Bool) -> Screen {
        guard let stored, Screen.sidebar.contains(stored) else { return .display }
        if stored == .set && !hasDisplay && !hasText { return .display }
        return stored
    }
}
