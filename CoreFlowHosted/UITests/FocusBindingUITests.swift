import CoreFlowUITesting
import XCTest

final class FocusBindingUITests: XCTestCase {
    @MainActor
    func testRealProjectionMovesFocusAndOnlyOwnerWritesLog() {
        let app = XCUIApplication.launch(TestScenario.focusBinding)
        let field = app.textFields["field"]
        let status = app.staticTexts["focusStatus"]
        XCTAssertTrue(field.waitUntil(\.exists, equals: true, timeout: 5))
        XCTAssertEqual(status.valueOrLabel, "unfocused")

        // System tap: focus moves, nothing logs.
        field.tapOrClick()
        XCTAssertTrue(status.waitUntil(\.valueOrLabel, equals: "focused", timeout: 5), status.valueOrLabel)
        XCTAssertEqual(app.logElement.label, "[]")

        // Child writes through the binding: focus moves, nothing logs.
        app.buttons["unfocus child"].tapOrClick()
        XCTAssertTrue(status.waitUntil(\.valueOrLabel, equals: "unfocused", timeout: 5), status.valueOrLabel)
        app.buttons["focus child"].tapOrClick()
        XCTAssertTrue(status.waitUntil(\.valueOrLabel, equals: "focused", timeout: 5), status.valueOrLabel)
        app.typeText("x")
        XCTAssertEqual(field.value as? String, "x")
        XCTAssertEqual(app.logElement.label, "[]")

        // Owner writes the property: focus moves, and it logs.
        app.buttons["unfocus child"].tapOrClick()
        XCTAssertTrue(status.waitUntil(\.valueOrLabel, equals: "unfocused", timeout: 5), status.valueOrLabel)
        app.buttons["focus owner"].tapOrClick()
        XCTAssertTrue(status.waitUntil(\.valueOrLabel, equals: "focused", timeout: 5), status.valueOrLabel)
        XCTAssertTrue(app.logElement.waitUntil(\.label, equals: #"["isFocused"]"#, timeout: 5), app.logElement.label)
        XCTAssertEqual(app.logElement.logValues, ["true"])
    }
}
