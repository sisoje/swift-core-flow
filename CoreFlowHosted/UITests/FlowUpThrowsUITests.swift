import CoreFlowUITesting
import XCTest

final class FlowUpThrowsUITests: XCTestCase {
    @MainActor
    func testThrowingListenerAbortsTheRest() {
        let app = XCUIApplication.launch(TestScenario.flowUpThrows)
        XCTAssertTrue(app.buttons["send"].waitUntil(\.exists, equals: true, timeout: 5))
        app.buttons["send"].tapOrClick()

        XCTAssertTrue(app.logElement.waitUntil(\.label, equals: #"["send","first","result"]"#, timeout: 5), app.logElement.label)
        XCTAssertEqual(app.logElement.logValues, ["hi", "hi", "SaveFailure()"])
    }
}
