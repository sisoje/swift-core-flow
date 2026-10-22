import CoreFlowUITesting
import XCTest

final class TestFocusStateUITests: XCTestCase {
    @MainActor
    func testSystemFocusIsSilentAndProgrammaticWriteLogs() {
        let app = XCUIApplication.launch(TestScenario.testFocusState)
        let status = app.staticTexts["focusStatus"]
        XCTAssertTrue(status.waitUntil(\.exists, equals: true, timeout: 5))
        XCTAssertEqual(status.valueOrLabel, "unfocused")

        app.textFields["field"].tapOrClick()
        XCTAssertTrue(status.waitUntil(\.valueOrLabel, equals: "focused", timeout: 5))
        XCTAssertEqual(app.logElement.label, "[]")

        app.buttons["toggle focus"].tapOrClick()
        XCTAssertTrue(status.waitUntil(\.valueOrLabel, equals: "unfocused", timeout: 5))
        XCTAssertTrue(app.logElement.waitUntil(\.label, equals: #"["isFocused"]"#, timeout: 5), app.logElement.label)
        XCTAssertEqual(app.logElement.logValues, ["false"])
    }
}
