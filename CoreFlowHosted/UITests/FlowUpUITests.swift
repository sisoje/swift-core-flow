import XCTest

final class FlowUpUITests: XCTestCase {
    @MainActor
    func testSendReachesEveryListenerIncludingOneShownLater() {
        let app = launchApp(scenario: "FlowUp")
        XCTAssertTrue(app.buttons["send"].waitForExistence(timeout: 5))

        app.buttons["send"].tap()
        app.buttons["show second"].tap()
        app.buttons["send"].tap()

        let names = #"["send","first","showSecond","send","first","second"]"#
        XCTAssertTrue(app.log.wait(for: \.label, toEqual: names, timeout: 5), app.log.label)
        XCTAssertEqual(app.logValues, ["hi", "hi", "true", "hi", "hi", "hi"])
    }
}
