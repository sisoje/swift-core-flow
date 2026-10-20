import XCTest

final class TestFocusStateUITests: XCTestCase {
    @MainActor
    func testSystemFocusIsSilentAndProgrammaticWriteLogs() {
        let app = launchApp(scenario: .testFocusState)
        let status = app.staticTexts["focusStatus"]
        XCTAssertTrue(status.waitUntil(\.exists, equals: true, timeout: 5))
        XCTAssertEqual(status.text, "unfocused")

        app.textFields["field"].tapOrClick()
        XCTAssertTrue(status.waitUntil(\.text, equals: "focused", timeout: 5))
        XCTAssertEqual(app.log.label, "[]")

        app.buttons["toggle focus"].tapOrClick()
        XCTAssertTrue(status.waitUntil(\.text, equals: "unfocused", timeout: 5))
        XCTAssertTrue(app.log.waitUntil(\.label, equals: #"["isFocused"]"#, timeout: 5), app.log.label)
        XCTAssertEqual(app.log.logValues, ["false"])
    }
}
