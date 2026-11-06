import AppKit
import FontDropCore
import SwiftUI
import XCTest
@testable import FontDrop

/// R9a: the blockers from the first real use. The mouse and the Sample field work, the source menu never reads "No
/// source", Set draws with one face, a new brand selects nothing, Appearance is a setting.
@MainActor
final class R9aTests: XCTestCase {
    private func tempDB() -> String { NSTemporaryDirectory() + "fontdrop-r9a-\(UUID().uuidString).db" }

    private func fixtureFolder() throws -> String {
        let source = "/System/Library/Fonts/Supplemental"
        let files = ["Arial", "Georgia"].flatMap { f in ["", " Bold", " Italic", " Bold Italic"].map { "\(f)\($0).ttf" } }
        for f in files where !FileManager.default.fileExists(atPath: "\(source)/\(f)") { throw XCTSkip("no system \(f)") }
        let dir = NSTemporaryDirectory() + "fontdrop-r9a-fixture-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for f in files { try FileManager.default.copyItem(atPath: "\(source)/\(f)", toPath: "\(dir)/\(f)") }
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        return dir
    }

    private func model(screen: String = "display") async throws -> AppModel {
        let dir = try fixtureFolder()
        let options = LaunchOptions(arguments: ["FontDrop", "--db", tempDB(), "--scan-folders", dir, "--screen", screen], environment: [:])
        let model = AppModel(options: options, defaults: makeTestSuite("fontdrop-r9a"))
        await model.bootstrap()
        return model
    }

    // MARK: 1. Only empty chrome drags the window

    private func allSubviews(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(allSubviews) }

    /// Hosts the real RootView in a window, lets it lay out, and returns the hosting view.
    private func host(_ model: AppModel, size: NSSize = NSSize(width: 1360, height: 860)) -> (NSHostingView<AnyView>, NSWindow) {
        let root = AnyView(ThemeRoot { RootView().environment(model) }.environment(\.colorScheme, .light))
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        window.layoutIfNeeded(); host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        host.layoutSubtreeIfNeeded()
        return (host, window)
    }

    /// Points over the whole window, every 24 pt, in the hosting view's own coordinates.
    private func sweep(_ host: NSView) -> [NSPoint] {
        var points: [NSPoint] = []
        var y: CGFloat = 12
        while y < host.bounds.height { var x: CGFloat = 12; while x < host.bounds.width { points.append(NSPoint(x: x, y: y)); x += 24 }; y += 24 }
        return points
    }

    private func accessibilityElements(in root: AnyObject, depth: Int = 0) -> [AnyObject] {
        guard depth < 14 else { return [] }
        var children: [AnyObject] = []
        if let kids = root.accessibilityChildren?() { children += kids.compactMap { $0 as AnyObject } }
        if let view = root as? NSView { children += view.subviews }
        return children.flatMap { [$0] + accessibilityElements(in: $0, depth: depth + 1) }
    }

    private func isDragView(_ view: NSView?) -> Bool {
        var v = view
        while let current = v { if current is WindowDragHandle.Handle { return true }; v = current.superview }
        return false
    }

    /// Display: nothing in the grid, the Sample field or the dial's neighbours hits a window-drag view.
    func testNoWindowDragViewSitsOverTheDisplayScreen() async throws {
        let model = try await self.model()
        model.selectedFamily = "Arial"
        model.screen = .display
        model.showInspector = true
        let (host, window) = host(model)
        _ = window
        XCTAssertFalse(allSubviews(host).contains { $0 is WindowDragHandle.Handle }, "no AppKit drag handle anywhere in the window (macOS 15 and later)")
        let points = sweep(host)
        XCTAssertGreaterThan(points.count, 500)
        let stolen = points.filter { isDragView(host.hitTest($0)) }
        XCTAssertTrue(stolen.isEmpty, "\(stolen.count) points hit a drag view, first \(String(describing: stolen.first))")
        // The Sample field itself: a real text field, and a click on its middle is not a window drag.
        let sample = allSubviews(host).compactMap { $0 as? NSTextField }.first { $0.placeholderString == Lexicon.R4.samplePlaceholder }
        let field = try XCTUnwrap(sample, "the Display inspector's Sample field is in the window")
        let middle = host.convert(NSPoint(x: field.bounds.midX, y: field.bounds.midY), from: field)
        let hit = host.hitTest(middle)
        XCTAssertFalse(isDragView(hit), "a click on the Sample field is not a window drag: \(String(describing: hit))")
    }

    /// Set: the dial, Body and the sliders live here. None of them is under a drag view.
    func testNoWindowDragViewSitsOverTheSetScreenAndItsDial() async throws {
        let model = try await self.model(screen: "set")
        await model.choose("display", family: "Georgia")
        await model.choose("reading", family: "Arial")
        model.screen = .set
        model.showInspector = true
        let (host, window) = host(model)
        _ = window
        let stolen = sweep(host).filter { isDragView(host.hitTest($0)) }
        XCTAssertTrue(stolen.isEmpty, "\(stolen.count) points hit a drag view")
        // The dial itself, found the way VoiceOver finds it: every point of its frame lands on something that is not a drag view.
        for attribute in ["AXEnhancedUserInterface", "AXManualAccessibility"] {
            NSApp.accessibilitySetValue(true as NSNumber, forAttribute: NSAccessibility.Attribute(rawValue: attribute))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        if let dial = accessibilityElements(in: host).first(where: { (($0.accessibilityLabel?() ?? nil) ?? "") == "Ratio" }) {
            let screenFrame = dial.accessibilityFrame?() ?? .zero
            let inWindow = window.convertFromScreen(screenFrame)
            let frame = host.convert(inWindow, from: nil)
            XCTAssertGreaterThan(frame.width, 40, "the dial has a real frame: \(frame)")
            for fx in stride(from: 0.1, through: 0.9, by: 0.2) {
                for fy in stride(from: 0.1, through: 0.9, by: 0.2) {
                    let p = NSPoint(x: frame.minX + frame.width * fx, y: frame.minY + frame.height * fy)
                    XCTAssertFalse(isDragView(host.hitTest(p)), "a click on the dial at \(p) is not a window drag")
                }
            }
        }
        XCTAssertFalse(window.isMovableByWindowBackground, "dragging the dial or a slider must not move the window")
    }

    // MARK: 2. The source menu

    func testAnEmptySourceSetReadsAsTheDefault() {
        XCTAssertEqual(Lexicon.Finder.sourceMenuValue([], savedOnly: false), "Your fonts + Google")
        XCTAssertEqual(Lexicon.Finder.sourceMenuValue(FinderFilter.standard.sources, savedOnly: false), "Your fonts + Google")
    }

    func testTheModelNeverHoldsNoSource() async throws {
        let model = try await self.model()
        model.filter.sources = []
        XCTAssertEqual(model.filter.sources, FinderFilter.standard.sources, "unchecking the last source goes back to the default")
        model.filter.sources = [.system]
        XCTAssertEqual(model.filter.sources, [.system])
        model.filter.sources.remove(.system)
        XCTAssertEqual(model.filter.sources, FinderFilter.standard.sources)
        let none = AppModel(options: LaunchOptions(arguments: ["FontDrop", "--db", tempDB(), "--bench", "--sources", ""], environment: [:]), defaults: makeTestSuite("fontdrop-r9a"))
        XCTAssertEqual(none.filter.sources, FinderFilter.standard.sources)
    }

    /// The counts in the source menu are what the grid shows: with the standard filter, the sum over the chips' families
    /// matches the grid's families.
    func testTheMenuCountsMatchTheGrid() async throws {
        let model = try await self.model()
        await model.finderSettled()
        let counts = try XCTUnwrap(model.finderResults?.counts)
        let shown = model.visibleFamilies.count
        let yours = Int(counts.sources.first { $0.source == .yours }?.count ?? 0)
        let google = Int(counts.sources.first { $0.source == .google }?.count ?? 0)
        XCTAssertGreaterThan(shown, 0)
        XCTAssertTrue(shown <= yours + google && shown >= max(yours, google), "grid \(shown), Your fonts \(yours), Google \(google)")
    }

    // MARK: 7. A new brand starts with nothing selected

    func testANewBrandSelectsNothing() async throws {
        let model = try await self.model()
        _ = await model.createBrand("First")
        model.selectedFamily = model.visibleFamilies.first?.name
        XCTAssertNotNil(model.selectedFamily)
        _ = await model.createBrand("Second")
        XCTAssertNil(model.selectedFamily, "the old brand's pick is not the new brand's")
        XCTAssertNil(model.inspectedFamily(job: "display"), "so the inspector shows its empty state")
    }

    // MARK: 5. Appearance

    func testAppearanceIsASettingThatPersists() async throws {
        let defaults = makeTestSuite("fontdrop-r9a-appearance")
        defer { NSApp.appearance = nil }
        let options = LaunchOptions(arguments: ["FontDrop", "--db", tempDB(), "--bench"], environment: [:])
        let model = AppModel(options: options, defaults: defaults)
        XCTAssertEqual(model.appearance, .system, "System is the default")
        model.appearance = .dark
        XCTAssertEqual(defaults.string(forKey: AppearanceChoice.key), "dark")
        XCTAssertEqual(NSApp.appearance?.name, .darkAqua, "applied at once")
        model.appearance = .light
        XCTAssertEqual(NSApp.appearance?.name, .aqua)
        model.appearance = .system
        XCTAssertNil(NSApp.appearance, "System follows macOS again")
        let again = AppModel(options: options, defaults: { defaults.set("dark", forKey: AppearanceChoice.key); return defaults }())
        XCTAssertEqual(again.appearance, .dark, "remembered on the next launch")
        XCTAssertEqual(AppearanceChoice.light.toggled(showingDark: true), .light)
        XCTAssertEqual(AppearanceChoice.system.toggled(showingDark: false), .dark)
    }

    // MARK: 3. Set with one face

    func testSetDrawsTheDisplayStepsWithOnlyADisplayFace() async throws {
        let model = try await self.model(screen: "set")
        await model.choose("display", family: "Georgia")
        XCTAssertNil(model.readingFamily)
        let sizes = SetSizes.fromScale(model.scale)
        XCTAssertGreaterThan(sizes.size(.display), sizes.size(.body))
        XCTAssertEqual(ScaleStep.stageOrder.filter { $0.isDisplayFace }, [.display, .h1, .h2, .h3])
        XCTAssertEqual(ScaleStep.stageOrder.filter { !$0.isDisplayFace }, [.lead, .body, .caption], "these three hold the Choose a Text face row")
        for s in [Lexicon.SetScreen.chooseText, Lexicon.SetScreen.chooseDisplay, Lexicon.SetScreen.goToText, Lexicon.SetScreen.goToDisplay,
                  Lexicon.SetScreen.neitherLine, Lexicon.R4.noSelection, Lexicon.R4.noSelectionHelp, Lexicon.Reading.pickOne] {
            XCTAssertFalse(s.contains("\u{2014}") || s.contains("\u{2013}"), "dash in: \(s)")
        }
    }
}
