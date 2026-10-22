import CoreFlowUITesting
import XCTest

final class TestStateUITests: XCTestCase {
    @MainActor
    func testDirectAndBindingWritesLogAndStayLive() {
        let app = XCUIApplication.launch(TestScenario.testState)
        XCTAssertTrue(app.buttons["increment"].waitUntil(\.exists, equals: true, timeout: 5))
        app.buttons["increment"].tapOrClick()
        app.switchOrCheckBox("switch").tapOrClick()

        XCTAssertTrue(app.staticTexts["count 1"].waitUntil(\.exists, equals: true, timeout: 5))
        XCTAssertTrue(app.staticTexts["on"].exists)
        XCTAssertTrue(app.logElement.waitUntil(\.label, equals: #"["count","isOn"]"#, timeout: 5), app.logElement.label)
        XCTAssertEqual(app.logElement.logValues, ["1", "true"])
    }
}
