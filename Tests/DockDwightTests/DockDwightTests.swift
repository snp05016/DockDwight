import XCTest
@testable import DockDwightLib

final class DockDwightTests: XCTestCase {
    func testPatrolMovesAndTurnsAtRightEdge() {
        let moved = PatrolEngine.step(state: .init(x: 100, direction: .right), deltaTime: 1, speed: 25, bounds: 100...200)
        XCTAssertEqual(moved.x, 125)
        XCTAssertEqual(moved.direction, .right)
        let turned = PatrolEngine.step(state: .init(x: 195, direction: .right), deltaTime: 1, speed: 25, bounds: 100...200)
        XCTAssertEqual(turned.x, 200)
        XCTAssertEqual(turned.direction, .left)
    }

    func testPatrolTurnsAtLeftEdge() {
        let result = PatrolEngine.step(state: .init(x: 105, direction: .left), deltaTime: 1, speed: 20, bounds: 100...200)
        XCTAssertEqual(result.x, 100)
        XCTAssertEqual(result.direction, .right)
    }

    func testQuoteSelectionAvoidsImmediateRepeat() {
        let first = DwightQuoteBook.quote(at: 2)
        XCTAssertNotEqual(DwightQuoteBook.quote(at: 2, excluding: first), first)
    }

    func testCharacterHeightUsesConfiguredDockTileSize() {
        XCTAssertEqual(
            DockGeometry.characterHeight(
                screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                visibleFrame: CGRect(x: 0, y: 70, width: 1920, height: 1010),
                configuredTileSize: 56
            ),
            56
        )
    }

    func testCharacterHeightInfersBottomDockWhenPreferenceUnavailable() {
        XCTAssertEqual(
            DockGeometry.characterHeight(
                screenFrame: CGRect(x: -1920, y: -120, width: 1920, height: 1080),
                visibleFrame: CGRect(x: -1920, y: -42, width: 1920, height: 1002),
                configuredTileSize: nil
            ),
            66
        )
    }

    func testFocusModeFlagsConfiguredDistraction() {
        let reaction = ContextualReactionEngine.reaction(
            bundleIdentifier: "com.valvesoftware.steam",
            appName: "Steam",
            focusMode: true,
            distractingApps: ["Steam", "Discord"]
        )
        XCTAssertEqual(reaction?.state, .focusWarning)
        XCTAssertTrue(reaction?.message.contains("FOCUS BREACH") == true)
    }

    func testXcodeGetsBuildInspectionReaction() {
        let reaction = ContextualReactionEngine.reaction(
            bundleIdentifier: "com.apple.dt.Xcode",
            appName: "Xcode",
            focusMode: false,
            distractingApps: []
        )
        XCTAssertEqual(reaction?.state, .inspecting)
        XCTAssertEqual(reaction?.source, "Xcode")
    }

    func testUnknownAppDoesNotInterruptPatrol() {
        XCTAssertNil(ContextualReactionEngine.reaction(
            bundleIdentifier: "com.example.tool",
            appName: "Tool",
            focusMode: false,
            distractingApps: []
        ))
    }

    func testWeatherClassification() {
        XCTAssertEqual(WeatherMood.classify(code: 0), .clear)
        XCTAssertEqual(WeatherMood.classify(code: 63), .rain)
        XCTAssertEqual(WeatherMood.classify(code: 75), .snow)
        XCTAssertEqual(WeatherMood.classify(code: 96), .storm)
    }

    func testQuartzWindowBoundsConvertToAppKitCoordinates() {
        let rect = WindowAwareness.appKitRect(
            fromQuartzBounds: CGRect(x: 80, y: 120, width: 640, height: 480),
            desktopTop: 1_080
        )
        XCTAssertEqual(rect, CGRect(x: 80, y: 480, width: 640, height: 480))
    }
}
