import XCTest

final class ViewModifierCoreUITests: XCTestCase {
    @MainActor
    func testHostedViewModifierCoreWrapsContentAndLogsItsState() {
        let app = launchApp(scenario: .viewModifierCore)
        let status = app.staticTexts["dimStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "bright")
        XCTAssertTrue(app.staticTexts["content"].exists)

        app.buttons["toggle dim"].tap()
        XCTAssertTrue(status.wait(for: \.label, toEqual: "dimmed", timeout: 5))
        app.buttons["toggle dim"].tap()
        XCTAssertTrue(status.wait(for: \.label, toEqual: "bright", timeout: 5))

        XCTAssertTrue(app.log.wait(for: \.label, toEqual: #"["isDimmed","isDimmed"]"#, timeout: 5), app.log.label)
        XCTAssertEqual(app.logValues, ["true", "false"])
    }
}
