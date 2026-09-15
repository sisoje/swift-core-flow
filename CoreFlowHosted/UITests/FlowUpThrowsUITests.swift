import XCTest

final class FlowUpThrowsUITests: XCTestCase {
    @MainActor
    func testThrowingListenerAbortsTheRest() {
        let app = launchApp(scenario: .flowUpThrows)
        XCTAssertTrue(app.buttons["send"].waitForExistence(timeout: 5))
        app.buttons["send"].tap()

        XCTAssertTrue(app.log.wait(for: \.label, toEqual: #"["send","first","result"]"#, timeout: 5), app.log.label)
        XCTAssertEqual(app.log.logValues, ["hi", "hi", "SaveFailure()"])
    }
}
