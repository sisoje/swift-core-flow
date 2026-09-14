import XCTest

final class TestActionUITests: XCTestCase {
    @MainActor
    func testCallsLogBeforeForwardingSyncAndAsync() {
        let app = launchApp(scenario: "TestAction")
        XCTAssertTrue(app.buttons["save"].waitForExistence(timeout: 5))
        app.buttons["save"].tap()
        app.buttons["fetch"].tap()

        XCTAssertTrue(app.staticTexts["fetched 6"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.log.wait(for: \.label, toEqual: #"["save","fetch","fetched"]"#, timeout: 5), app.log.label)
        XCTAssertEqual(app.logValues, ["draft", "3", "6"])
    }
}
