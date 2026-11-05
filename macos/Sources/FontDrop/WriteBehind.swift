import FontDropCore
import Foundation

/// Saves changed values to the library database a moment after the last change.
///
/// The three per-brand stores (scale, colors, face settings) keep their values in memory, so the UI reads them
/// without waiting. When a value changes, the store `mark`s its key. A slider drag is many changes, so the write
/// waits until the changes stop, then goes to the database on a background thread. (The database's own writer may
/// be busy with a font scan, and the main thread must never wait on it.)
///
/// `persist: false` (screenshot, bench and test runs) reads the database but never writes it.
/// React: a debounced `useEffect` that posts the dirty keys.
@MainActor
final class WriteBehind<Key: Hashable & Sendable> {
    /// Set when the library opens. Without it nothing is written (the values live in memory only).
    var library: Library?
    let persist: Bool
    /// Builds the write for one key from the store's current value, on the main thread. Nil: nothing to write.
    private let job: @MainActor (Key) -> (@Sendable (Library) throws -> Void)?
    private var dirty: Set<Key> = []
    private var task: Task<Void, Never>?
    private let delay: Duration

    init(persist: Bool, delay: Duration = .milliseconds(400), job: @escaping @MainActor (Key) -> (@Sendable (Library) throws -> Void)?) {
        self.persist = persist
        self.delay = delay
        self.job = job
    }

    func mark(_ key: Key) {
        guard persist, library != nil else { return }
        dirty.insert(key)
        task?.cancel()
        task = Task { [weak self] in
            guard let delay = self?.delay else { return }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.writeInBackground()
        }
    }

    private func take() -> [@Sendable (Library) throws -> Void] {
        let keys = dirty
        dirty = []
        return keys.compactMap { job($0) }
    }

    private func writeInBackground() async {
        guard let library else { return }
        let jobs = take()
        guard !jobs.isEmpty else { return }
        await Task.detached(priority: .utility) {
            for write in jobs {
                do { try write(library) } catch { print("FONTDROP brand settings write failed: \(error)") }
            }
        }.value
    }

    /// Writes what is waiting, now, on this thread. For quitting and for tests.
    func flush() {
        task?.cancel()
        guard persist, let library else { return }
        for write in take() {
            do { try write(library) } catch { print("FONTDROP brand settings write failed: \(error)") }
        }
    }
}
