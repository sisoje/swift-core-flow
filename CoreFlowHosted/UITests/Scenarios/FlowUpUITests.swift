import XCTest

final class FlowUpUITests: XCTestCase {
    @MainActor
    func testSendReachesEveryListenerIncludingOneShownLater() {
        let app = launchApp(scenario: .flowUp)
        XCTAssertTrue(app.buttons["send"].waitUntil(\.exists, equals: true, timeout: 5))

        app.buttons["send"].tapOrClick()
        app.buttons["show second"].tapOrClick()
        app.buttons["send"].tapOrClick()

        let names = #"["send","first","showSecond","send","first","second"]"#
        XCTAssertTrue(app.log.waitUntil(\.label, equals: names, timeout: 5), app.log.label)
        XCTAssertEqual(app.log.logValues, ["hi", "hi", "true", "hi", "hi", "hi"])
    }
}
