import XCTest

final class TestEnvironmentUITests: XCTestCase {
    @MainActor
    func testDismissLogsAndReallyDismisses() {
        let app = launchApp(scenario: .testEnvironment)
        XCTAssertTrue(app.buttons["present"].waitUntil(\.exists, equals: true, timeout: 5))
        app.buttons["present"].tapOrClick()
        XCTAssertTrue(app.buttons["close"].waitUntil(\.exists, equals: true, timeout: 5))

        app.buttons["close"].tapOrClick()
        // The real DismissAction ran: SwiftUI writes the sheet binding back
        // through the scenario's @TestState — twice, as the sheet finishes.
        let names = #"["isPresented","dismiss","isPresented","isPresented"]"#
        XCTAssertTrue(app.log.waitUntil(\.label, equals: names, timeout: 5), app.log.label)
        XCTAssertEqual(app.log.logValues, ["true", "", "false", "false"])
        XCTAssertFalse(app.buttons["close"].exists)
    }
}
