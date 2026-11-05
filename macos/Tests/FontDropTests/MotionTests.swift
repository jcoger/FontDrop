import XCTest
@testable import FontDrop

/// R9b: the motion tokens stay short, and a screen change knows which way it travelled.
@MainActor
final class MotionTests: XCTestCase {
    func testScreenTravelFollowsTheSidebarOrder() {
        let defaults = UserDefaults(suiteName: "motion-\(UUID().uuidString)")!
        let model = AppModel(options: LaunchOptions(arguments: ["FontDrop", "--bench"], environment: [:]), defaults: defaults)
        model.screen = .reading
        XCTAssertEqual(model.screenTravel, 1, "Display to Text moves right")
        model.screen = .set
        XCTAssertEqual(model.screenTravel, 1, "Text to Set moves right")
        model.screen = .display
        XCTAssertEqual(model.screenTravel, -1, "Set back to Display moves left")
    }

    func testTravelIsSmall() {
        XCTAssertLessThanOrEqual(Motion.travel, 8)
        XCTAssertGreaterThanOrEqual(Motion.travel, 6)
    }

    func testInspectorFadeKeyChangesWithSelection() {
        let defaults = UserDefaults(suiteName: "motion-\(UUID().uuidString)")!
        let model = AppModel(options: LaunchOptions(arguments: ["FontDrop", "--bench"], environment: [:]), defaults: defaults)
        let before = model.inspectorFadeKey
        model.selectedFamily = "Example"
        XCTAssertNotEqual(model.inspectorFadeKey, before)
    }
}
