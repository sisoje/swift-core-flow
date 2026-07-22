import XCTest

final class FocusFieldUITests: XCTestCase {
    // The scenario hosts FocusField.Core() directly — its verbatim-copied
    // @FocusState is Core's own live storage. Both directions run for real:
    // tapping the field moves the OS's focus into Core's read, the toggle
    // button (in Core's copied body) writes back out, moving focus away.
    // Behavior-asserted, no snapshot: focus isn't in the model (no
    // Binding-typed fields → no CoreModel).
    @MainActor
    func testTappingFieldFocusesAndToggleButtonUnfocuses() {
        let app = launchExampleApp(scenario: "FocusField")

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
