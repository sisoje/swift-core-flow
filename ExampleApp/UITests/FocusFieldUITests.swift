import XCTest

final class FocusFieldUITests: XCTestCase {
    // FocusState's projected value, substituted verbatim onto Core, is the
    // SAME handle the host's own $isFocused already is — not a captured
    // copy — so both directions genuinely write through, live: tapping the
    // field moves the OS's real focus into our read (system → Core), and the
    // toggle button (executed from Core's own body) writes back out to the
    // host's real storage (Core → system), moving focus away.
    @MainActor
    func testTappingFieldFocusesAndToggleButtonUnfocuses() {
        let app = launchExampleApp(scenario: "FocusState")

        let field = app.textFields["focusTextField"]
        let status = app.staticTexts["focusStatusLabel"]
        let toggle = app.buttons["toggleFocusButton"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "unfocused")

        field.tap()
        let focusedPredicate = NSPredicate(format: "label == 'focused'")
        expectation(for: focusedPredicate, evaluatedWith: status)
        waitForExpectations(timeout: 5)

        toggle.tap()
        let unfocusedPredicate = NSPredicate(format: "label == 'unfocused'")
        expectation(for: unfocusedPredicate, evaluatedWith: status)
        waitForExpectations(timeout: 5)
    }
}
