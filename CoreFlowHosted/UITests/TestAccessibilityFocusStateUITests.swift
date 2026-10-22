import CoreFlowUITesting
import XCTest

final class TestAccessibilityFocusStateUITests: XCTestCase {
    @MainActor
    func testProgrammaticWriteLogs() {
        let app = XCUIApplication.launch(TestScenario.testAccessibilityFocusState)
        XCTAssertTrue(app.buttons["focus hint"].waitUntil(\.exists, equals: true, timeout: 5))
        XCTAssertEqual(app.logElement.label, "[]")

        app.buttons["focus hint"].tapOrClick()
        XCTAssertTrue(app.logElement.waitUntil(\.label, equals: #"["isFocused"]"#, timeout: 5), app.logElement.label)
        XCTAssertEqual(app.logElement.logValues, ["true"])
    }
}
