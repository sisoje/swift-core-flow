import XCTest

final class ShellCoreUITests: XCTestCase {
    @MainActor
    func testHostedCoreLogsStateAndWritesStorageThroughTheBinding() {
        let app = launchApp(scenario: "ShellCore")
        XCTAssertTrue(app.buttons["toggle"].waitForExistence(timeout: 5))
        app.buttons["toggle"].tap()
        app.buttons["rename"].tap()

        XCTAssertTrue(app.staticTexts["on"].exists)
        XCTAssertTrue(app.staticTexts["renamed"].exists)
        XCTAssertTrue(app.log.wait(for: \.label, toEqual: #"["isOn","name"]"#, timeout: 5), app.log.label)
        XCTAssertEqual(app.logValues, ["true", "renamed"])
    }
}
