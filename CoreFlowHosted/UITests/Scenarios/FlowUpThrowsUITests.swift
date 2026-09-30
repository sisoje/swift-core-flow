import XCTest

final class FlowUpThrowsUITests: XCTestCase {
    @MainActor
    func testThrowingListenerAbortsTheRest() {
        let app = launchApp(scenario: .flowUpThrows)
        XCTAssertTrue(app.buttons["send"].waitUntil(\.exists, equals: true, timeout: 5))
        app.buttons["send"].tapOrClick()

        XCTAssertTrue(app.log.waitUntil(\.label, equals: #"["send","first","result"]"#, timeout: 5), app.log.label)
        XCTAssertEqual(app.log.logValues, ["hi", "hi", "SaveFailure()"])
    }
}
