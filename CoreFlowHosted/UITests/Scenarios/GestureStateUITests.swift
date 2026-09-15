import XCTest

final class GestureStateUITests: XCTestCase {
    @MainActor
    func testCustomResetFiresOnCoreWhenTheGestureEnds() {
        let app = launchApp(scenario: .gestureState)
        let resets = app.staticTexts["resets"]
        XCTAssertTrue(resets.waitForExistence(timeout: 5))
        XCTAssertEqual(resets.label, "resets 0")

        let box = app.otherElements["box"]
        let start = box.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: 80, dy: -40)))

        XCTAssertTrue(resets.wait(for: \.label, toEqual: "resets 1", timeout: 5))
        XCTAssertTrue(app.log.wait(for: \.label, toEqual: #"["resetsSeen"]"#, timeout: 5), app.log.label)
        XCTAssertEqual(app.log.logValues, ["1"])
    }
}
