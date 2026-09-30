import XCTest

final class ViewModifierCoreUITests: XCTestCase {
    @MainActor
    func testHostedViewModifierCoreWrapsContentAndLogsItsState() {
        let app = launchApp(scenario: .viewModifierCore)
        let status = app.staticTexts["dimStatus"]
        XCTAssertTrue(status.waitUntil(\.exists, equals: true, timeout: 5))
        XCTAssertEqual(status.label, "bright")
        XCTAssertTrue(app.staticTexts["content"].exists)

        app.buttons["toggle dim"].tapOrClick()
        XCTAssertTrue(status.waitUntil(\.label, equals: "dimmed", timeout: 5))
        app.buttons["toggle dim"].tapOrClick()
        XCTAssertTrue(status.waitUntil(\.label, equals: "bright", timeout: 5))

        XCTAssertTrue(app.log.waitUntil(\.label, equals: #"["isDimmed","isDimmed"]"#, timeout: 5), app.log.label)
        XCTAssertEqual(app.log.logValues, ["true", "false"])
    }
}
