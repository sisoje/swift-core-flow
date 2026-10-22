import CoreFlowUITesting
import XCTest

final class TestActionUITests: XCTestCase {
    @MainActor
    func testCallsLogBeforeForwardingSyncAndAsync() {
        let app = XCUIApplication.launch(TestScenario.testAction)
        XCTAssertTrue(app.buttons["save"].waitUntil(\.exists, equals: true, timeout: 5))
        app.buttons["save"].tapOrClick()
        app.buttons["fetch"].tapOrClick()

        XCTAssertTrue(app.staticTexts["fetched 6"].waitUntil(\.exists, equals: true, timeout: 5))
        XCTAssertTrue(app.logElement.waitUntil(\.label, equals: #"["save","fetch","fetched"]"#, timeout: 5), app.logElement.label)
        XCTAssertEqual(app.logElement.logValues, ["draft", "3", "6"])
    }
}
