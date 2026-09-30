import XCTest

final class GestureStateUITests: XCTestCase {
    @MainActor
    func testCustomResetFiresOnCoreWhenTheGestureEnds() {
        let app = launchApp(scenario: .gestureState)
        let resets = app.staticTexts["resets"]
        XCTAssertTrue(resets.waitUntil(\.exists, equals: true, timeout: 5))
        XCTAssertEqual(resets.label, "resets 0")

        let box = app.otherElements["box"]
        let start = box.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let drag = { start.pressOrClick(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: 80, dy: -40))) }
        drag()
        // A CI runner sometimes discards a synthesized drag whole — nothing
        // reaches the app — so a drag that changed nothing is repeated once.
        if !resets.waitUntil(\.label, equals: "resets 1", timeout: 5) {
            drag()
        }

        XCTAssertTrue(resets.waitUntil(\.label, equals: "resets 1", timeout: 5), resets.label)
        XCTAssertTrue(app.log.waitUntil(\.label, equals: #"["resetsSeen"]"#, timeout: 5), app.log.label)
        XCTAssertEqual(app.log.logValues, ["1"])
    }
}
