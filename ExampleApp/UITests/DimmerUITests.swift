import XCTest

final class DimmerUITests: XCTestCase {
    // Dimmer.Core's copied body(content:) runs live; each toggle tap writes
    // through the substituted @Binding.
    @MainActor
    func testToggleDimWritesThroughCoreViewModifier() {
        let app = launchExampleApp(scenario: "Dimmer")

        let status = app.staticTexts["dimStatusLabel"]
        let toggle = app.buttons["toggleDimButton"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "bright")
        XCTAssertTrue(app.staticTexts["dimContent"].exists)

        toggle.tap()
        XCTAssertTrue(status.wait(for: \.label, toEqual: "dimmed", timeout: 5))

        toggle.tap()
        XCTAssertTrue(status.wait(for: \.label, toEqual: "bright", timeout: 5))

        XCTAssertTrue(app.log.wait(for: \.label, toEqual: #"["isDimmed","isDimmed"]"#, timeout: 5))
        XCTAssertEqual(app.logValues, ["true", "false"])
    }
}
