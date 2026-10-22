import CoreFlowUITesting
import XCTest

final class ViewModifierCoreUITests: XCTestCase {
    @MainActor
    func testHostedViewModifierCoreWrapsContentAndLogsItsState() {
        let app = XCUIApplication.launch(TestScenario.viewModifierCore)
        let status = app.staticTexts["dimStatus"]
        XCTAssertTrue(status.waitUntil(\.exists, equals: true, timeout: 5))
        XCTAssertEqual(status.valueOrLabel, "bright")
        XCTAssertTrue(app.staticTexts["content"].exists)

        app.buttons["toggle dim"].tapOrClick()
        XCTAssertTrue(status.waitUntil(\.valueOrLabel, equals: "dimmed", timeout: 5))
        app.buttons["toggle dim"].tapOrClick()
        XCTAssertTrue(status.waitUntil(\.valueOrLabel, equals: "bright", timeout: 5))

        XCTAssertTrue(app.logElement.waitUntil(\.label, equals: #"["isDimmed","isDimmed"]"#, timeout: 5), app.logElement.label)
        XCTAssertEqual(app.logElement.logValues, ["true", "false"])
    }
}
