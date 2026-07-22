import XCTest

final class DimmerUITests: XCTestCase {
    // DimmerDemo applies Dimmer.CORE directly (not the Dimmer host), so this
    // runs the COPIED body(content:) live: tapping the toggle inside Core's
    // body writes through its substituted @Binding to DimmerDemo's @State,
    // and the status label re-renders.
    @MainActor
    func testToggleDimFlipsStateInsideCoreViewModifier() {
        let app = launchExampleApp(scenario: "ViewModifier")

        let status = app.staticTexts["dimStatusLabel"]
        let toggle = app.buttons["toggleDimButton"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "bright")
        XCTAssertTrue(app.staticTexts["dimContent"].exists)

        toggle.tap()
        let dimmedPredicate = NSPredicate(format: "label == 'dimmed'")
        expectation(for: dimmedPredicate, evaluatedWith: status)
        waitForExpectations(timeout: 5)
    }
}
