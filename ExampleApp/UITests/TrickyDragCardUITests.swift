import XCTest

final class TrickyDragCardUITests: XCTestCase {
    // The host declares @GestureState(reset:) — an argument-carrying init whose
    // custom closure must fire when the gesture state resets on release; the
    // probe label counts those firings. FAILS today: @Shell mirrors only the
    // attribute name onto Core, silently dropping the reset closure, so the
    // label stays "resets 0". Goes green when the macro carries the full
    // attribute onto Core.
    @MainActor
    func testCustomResetClosureFiresWhenGestureEnds() {
        let app = XCUIApplication()
        app.launch()

        let box = app.otherElements["trickyDragBox"]
        let resets = app.staticTexts["trickyResetsLabel"]
        XCTAssertTrue(box.waitForExistence(timeout: 5))
        XCTAssertEqual(resets.label, "resets 0")

        let start = box.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: 80, dy: -40)))

        let firedPredicate = NSPredicate(format: "label == 'resets 1'")
        expectation(for: firedPredicate, evaluatedWith: resets)
        waitForExpectations(timeout: 5)
    }
}
