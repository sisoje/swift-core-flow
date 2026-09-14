import XCTest

final class TestFocusStateUITests: XCTestCase {
    @MainActor
    func testSystemFocusIsSilentAndProgrammaticWriteLogs() {
        let app = launchApp(scenario: .testFocusState)
        let status = app.staticTexts["focusStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "unfocused")

        app.textFields["field"].tap()
        XCTAssertTrue(status.wait(for: \.label, toEqual: "focused", timeout: 5))
        XCTAssertEqual(app.log.label, "[]")

        app.buttons["toggle focus"].tap()
        XCTAssertTrue(status.wait(for: \.label, toEqual: "unfocused", timeout: 5))
        XCTAssertTrue(app.log.wait(for: \.label, toEqual: #"["isFocused"]"#, timeout: 5), app.log.label)
        XCTAssertEqual(app.logValues, ["false"])
    }
}
