import XCTest

final class TestStateUITests: XCTestCase {
    @MainActor
    func testDirectAndBindingWritesLogAndStayLive() {
        let app = launchApp(scenario: .testState)
        XCTAssertTrue(app.buttons["increment"].waitForExistence(timeout: 5))
        app.buttons["increment"].tap()
        app.switches["switch"].switches.firstMatch.tap()

        XCTAssertTrue(app.staticTexts["count 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["on"].exists)
        XCTAssertTrue(app.log.wait(for: \.label, toEqual: #"["count","isOn"]"#, timeout: 5), app.log.label)
        XCTAssertEqual(app.logValues, ["1", "true"])
    }
}
