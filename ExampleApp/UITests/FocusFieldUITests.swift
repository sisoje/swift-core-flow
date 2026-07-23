import XCTest

final class FocusFieldUITests: XCTestCase {
    // Core's verbatim-copied @FocusState is live: tapping the field moves
    // the OS's real focus in, the toggle button writes it back out.
    @MainActor
    func testTappingFieldFocusesAndToggleButtonUnfocuses() {
        let app = launchExampleApp(scenario: "FocusField")

        let field = app.textFields["focusTextField"]
        let status = app.staticTexts["focusStatusLabel"]
        let toggle = app.buttons["toggleFocusButton"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "unfocused")

        field.tap()
        XCTAssertTrue(status.wait(for: \.label, toEqual: "focused", timeout: 5))

        toggle.tap()
        XCTAssertTrue(status.wait(for: \.label, toEqual: "unfocused", timeout: 5))
    }
}
