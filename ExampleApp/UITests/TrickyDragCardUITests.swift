import XCTest

final class TrickyDragCardUITests: SnapshotTestCase {
    // The host declares @GestureState(reset:) — the custom closure must fire
    // when the gesture resets on release. @Shell copies the declaration onto
    // Core byte-for-byte, closure included; the drag runs against Core, and
    // the mutation snapshot pins the outcome: exactly one `resetsSeen = 1`
    // write, nothing else.
    @MainActor
    func testCustomResetClosureFiresWhenGestureEnds() {
        let app = launch(scenario: "TrickyDragCard")

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
