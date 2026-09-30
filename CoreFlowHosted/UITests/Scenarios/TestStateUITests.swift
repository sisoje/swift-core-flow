import XCTest

final class TestStateUITests: XCTestCase {
    @MainActor
    func testDirectAndBindingWritesLogAndStayLive() {
        let app = launchApp(scenario: .testState)
        XCTAssertTrue(app.buttons["increment"].waitUntil(\.exists, equals: true, timeout: 5))
        app.buttons["increment"].tapOrClick()
        app.switches["switch"].switches.firstMatch.tapOrClick()

        XCTAssertTrue(app.staticTexts["count 1"].waitUntil(\.exists, equals: true, timeout: 5))
        XCTAssertTrue(app.staticTexts["on"].exists)
        XCTAssertTrue(app.log.waitUntil(\.label, equals: #"["count","isOn"]"#, timeout: 5), app.log.label)
        XCTAssertEqual(app.log.logValues, ["1", "true"])
    }
}
