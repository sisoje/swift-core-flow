import XCTest

final class FocusBindingUITests: XCTestCase {
    @MainActor
    func testRealProjectionMovesFocusAndOnlyOwnerWritesLog() {
        let app = launchApp(scenario: .focusBinding)
        let field = app.textFields["field"]
        let status = app.staticTexts["focusStatus"]
        XCTAssertTrue(field.waitUntil(\.exists, equals: true, timeout: 5))
        XCTAssertEqual(status.label, "unfocused")

        // System tap: focus moves, nothing logs.
        field.tapOrClick()
        XCTAssertTrue(status.waitUntil(\.label, equals: "focused", timeout: 5), status.label)
        XCTAssertEqual(app.log.label, "[]")

        // Child writes through the binding: focus moves, nothing logs.
        app.buttons["unfocus child"].tapOrClick()
        XCTAssertTrue(status.waitUntil(\.label, equals: "unfocused", timeout: 5), status.label)
        app.buttons["focus child"].tapOrClick()
        XCTAssertTrue(status.waitUntil(\.label, equals: "focused", timeout: 5), status.label)
        app.typeText("x")
        XCTAssertEqual(field.value as? String, "x")
        XCTAssertEqual(app.log.label, "[]")

        // Owner writes the property: focus moves, and it logs.
        app.buttons["unfocus child"].tapOrClick()
        XCTAssertTrue(status.waitUntil(\.label, equals: "unfocused", timeout: 5), status.label)
        app.buttons["focus owner"].tapOrClick()
        XCTAssertTrue(status.waitUntil(\.label, equals: "focused", timeout: 5), status.label)
        XCTAssertTrue(app.log.waitUntil(\.label, equals: #"["isFocused"]"#, timeout: 5), app.log.label)
        XCTAssertEqual(app.log.logValues, ["true"])
    }
}
