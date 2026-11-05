import XCTest

/// Every UserDefaults suite the tests made. Emptied when a test ends and again when the whole run ends.
///
/// Removing a domain leaves an empty plist in ~/Library/Preferences, and the preferences daemon can write a suite
/// again a moment after the test that used it is gone (the app model saves in the background). So the plist files
/// are deleted once more at the end of the run, when nothing is writing any more.
final class TestSuites: NSObject, XCTestObservation {
    nonisolated(unsafe) static let shared = TestSuites()
    private let lock = NSLock()
    private var names: Set<String> = []
    private var observing = false

    func register(_ name: String) {
        lock.lock(); defer { lock.unlock() }
        names.insert(name)
        if !observing { observing = true; XCTestObservationCenter.shared.addTestObserver(self) }
    }

    func removeAll() {
        lock.lock(); let all = names; lock.unlock()
        for name in all { UserDefaults().removePersistentDomain(forName: name) }
        Thread.sleep(forTimeInterval: 0.5)                  // let the preferences daemon finish its own writes
        let dir = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Preferences")
        for name in all { try? FileManager.default.removeItem(atPath: (dir as NSString).appendingPathComponent("\(name).plist")) }
    }

    func testBundleDidFinish(_ testBundle: Bundle) { removeAll() }
}

extension XCTestCase {
    /// A throwaway UserDefaults suite for one test. Its domain is removed when the test ends and its plist when the
    /// run ends, so a test run leaves no `fontdrop-*` suites in ~/Library/Preferences. Every test that needs a suite uses this.
    func makeTestSuite(_ prefix: String) -> UserDefaults {
        makeTestSuite(named: "\(prefix)-\(UUID().uuidString)")
    }

    /// The same, for a test that needs the same suite twice (a second store that reads what the first saved).
    func makeTestSuite(named name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        TestSuites.shared.register(name)
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }
}
