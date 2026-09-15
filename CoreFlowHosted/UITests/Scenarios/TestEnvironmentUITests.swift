import XCTest

final class TestEnvironmentUITests: XCTestCase {
    @MainActor
    func testDismissLogsAndReallyDismisses() {
        let app = launchApp(scenario: .testEnvironment)
        XCTAssertTrue(app.buttons["present"].waitForExistence(timeout: 5))
        app.buttons["present"].tap()
        XCTAssertTrue(app.buttons["close"].waitForExistence(timeout: 5))

        app.buttons["close"].tap()
        // The real DismissAction ran: the sheet's binding write comes back
        // through the scenario's @TestState, after the logged call.
        XCTAssertTrue(
            app.log.wait(for: \.label, toEqual: #"["isPresented","dismiss","isPresented"]"#, timeout: 5),
            app.log.label
        )
        XCTAssertEqual(app.log.logValues, ["true", "", "false"])
        XCTAssertFalse(app.buttons["close"].exists)
    }
}
