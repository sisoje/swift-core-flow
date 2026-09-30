import XCTest

final class TestActionUITests: XCTestCase {
    @MainActor
    func testCallsLogBeforeForwardingSyncAndAsync() {
        let app = launchApp(scenario: .testAction)
        XCTAssertTrue(app.buttons["save"].waitUntil(\.exists, equals: true, timeout: 5))
        app.buttons["save"].tapOrClick()
        app.buttons["fetch"].tapOrClick()

        XCTAssertTrue(app.staticTexts["fetched 6"].waitUntil(\.exists, equals: true, timeout: 5))
        XCTAssertTrue(app.log.waitUntil(\.label, equals: #"["save","fetch","fetched"]"#, timeout: 5), app.log.label)
        XCTAssertEqual(app.log.logValues, ["draft", "3", "6"])
    }
}
