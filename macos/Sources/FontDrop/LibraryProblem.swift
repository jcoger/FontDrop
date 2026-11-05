import AppKit
import SwiftUI

/// Why the library could not be opened, in words a designer can act on. The core reports a database error string;
/// this reads it together with what the disk says about the folder.
///
/// React: an error boundary's fallback, chosen by the kind of error.
enum LibraryOpenProblem: Equatable {
    /// A newer FontDrop saved this library. This build refuses it and leaves it untouched.
    case newer
    /// The library's folder or file cannot be written.
    case readOnly(folder: String)
    /// Anything else. Shows the file and the error.
    case other(file: String, detail: String)

    static func classify(error: String, dbPath: String) -> LibraryOpenProblem {
        let folder = (dbPath as NSString).deletingLastPathComponent
        if error.contains("newer-library") { return .newer }
        let lower = error.lowercased()
        let looksLikeWrite = ["readonly", "read-only", "unable to open database", "permission", "not permitted", "disk i/o", "cannot create"]
            .contains { lower.contains($0) }
        if looksLikeWrite && !canWrite(dbPath: dbPath) { return .readOnly(folder: folder) }
        return .other(file: dbPath, detail: error)
    }

    /// True when FontDrop could save a library at `dbPath`: the file is writable, or it is missing and the nearest
    /// folder that exists is writable.
    static func canWrite(dbPath: String) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: dbPath) { return fm.isWritableFile(atPath: dbPath) && fm.isWritableFile(atPath: (dbPath as NSString).deletingLastPathComponent) }
        var dir = (dbPath as NSString).deletingLastPathComponent
        while !dir.isEmpty && dir != "/" && !fm.fileExists(atPath: dir) { dir = (dir as NSString).deletingLastPathComponent }
        return fm.isWritableFile(atPath: dir)
    }

    var title: String {
        switch self {
        case .newer: Lexicon.LibraryProblem.titleNewer
        case .readOnly: Lexicon.LibraryProblem.titleReadOnly
        case .other: Lexicon.LibraryProblem.titleOther
        }
    }

    var message: String {
        switch self {
        case .newer: Lexicon.LibraryProblem.bodyNewer
        case .readOnly(let folder): Lexicon.LibraryProblem.bodyReadOnly(folder)
        case .other(let file, _): Lexicon.LibraryProblem.bodyOther(file)
        }
    }

    /// The folder Show in Finder opens.
    var folder: String? {
        switch self {
        case .newer: nil
        case .readOnly(let folder): folder
        case .other(let file, _): (file as NSString).deletingLastPathComponent
        }
    }
}

/// The whole window when the library cannot open. Never a crash, always a next step.
struct LibraryProblemView: View {
    @Environment(\.theme) private var theme
    let problem: LibraryOpenProblem

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 28)).foregroundStyle(theme.textSecondary.color)
                .padding(.bottom, 6)
            Text(problem.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.textPrimary.color)
            Text(problem.message).font(.system(size: 13)).foregroundStyle(theme.textSecondary.color)
                .multilineTextAlignment(.center).frame(maxWidth: 420).textSelection(.enabled)
            if case .other(_, let detail) = problem {
                Text(detail).font(.system(size: 11).monospaced()).foregroundStyle(theme.textSecondary.color)
                    .multilineTextAlignment(.center).frame(maxWidth: 420).lineLimit(3).textSelection(.enabled)
            }
            HStack(spacing: 10) {
                if let folder = problem.folder {
                    Button(Lexicon.LibraryProblem.showInFinder) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: folder))
                    }.buttonStyle(GlassButtonStyle(large: true))
                }
                Button(Lexicon.LibraryProblem.quit) { NSApp.terminate(nil) }.buttonStyle(PrimaryButtonStyle(large: true))
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.panelContent.color)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(problem.title)
    }
}
