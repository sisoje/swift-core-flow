import XCTest

final class TestAccessibilityFocusStateUITests: XCTestCase {
    @MainActor
    func testProgrammaticWriteLogs() {
        let app = launchApp(scenario: .testAccessibilityFocusState)
        XCTAssertTrue(app.buttons["focus hint"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.log.label, "[]")

        app.buttons["focus hint"].tap()
        XCTAssertTrue(app.log.wait(for: \.label, toEqual: #"["isFocused"]"#, timeout: 5), app.log.label)
        XCTAssertEqual(app.log.logValues, ["true"])
    }
}
