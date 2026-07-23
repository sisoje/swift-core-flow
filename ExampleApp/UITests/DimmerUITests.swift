import XCTest

final class DimmerUITests: SnapshotTestCase {
    // Runs Dimmer.Core's COPIED body(content:) live: every tap on the toggle
    // inside Core's body writes through the substituted @Binding into the
    // CoreModel, and the mutation snapshot pins the exact sequence —
    // `isDimmed = true` then `isDimmed = false`, nothing more, nothing less.
    @MainActor
    func testToggleDimWritesThroughCoreViewModifier() {
        let app = launch(scenario: "Dimmer")

        let status = app.staticTexts["dimStatusLabel"]
        let toggle = app.buttons["toggleDimButton"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "bright")
        XCTAssertTrue(app.staticTexts["dimContent"].exists)

        toggle.tap()
        let dimmedPredicate = NSPredicate(format: "label == 'dimmed'")
        expectation(for: dimmedPredicate, evaluatedWith: status)
        waitForExpectations(timeout: 5)

        toggle.tap()
        let brightPredicate = NSPredicate(format: "label == 'bright'")
        expectation(for: brightPredicate, evaluatedWith: status)
        waitForExpectations(timeout: 5)

        // The finish line: one logged write per tap, nothing else.
        expectLogNames(app, "isDimmed,isDimmed")
    }
}
