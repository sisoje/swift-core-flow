import XCTest

final class TrickyDragCardUITests: XCTestCase {
    // @GestureState(reset:) — the custom closure rides verbatim onto Core
    // and must fire when the gesture resets on release.
    @MainActor
    func testCustomResetClosureFiresWhenGestureEnds() {
        let app = launchExampleApp(scenario: "TrickyDragCard")

        let box = app.otherElements["trickyDragBox"]
        let resets = app.staticTexts["trickyResetsLabel"]
        XCTAssertTrue(box.waitForExistence(timeout: 5))
        XCTAssertEqual(resets.label, "resets 0")

        let start = box.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: 80, dy: -40)))

        XCTAssertTrue(resets.wait(for: \.label, toEqual: "resets 1", timeout: 5))

        XCTAssertTrue(app.log.wait(for: \.label, toEqual: #"["resetsSeen"]"#, timeout: 5))
        XCTAssertEqual(app.logValues, ["1"])
    }
}
