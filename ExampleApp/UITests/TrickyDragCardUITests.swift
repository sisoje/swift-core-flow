import XCTest

final class TrickyDragCardUITests: XCTestCase {
    // The host declares @GestureState(reset:) — an argument-carrying init whose
    // custom closure must fire when the gesture state resets on release; the
    // probe label counts those firings. This test drove @Shell's verbatim-copy
    // design for this field: it was red under an earlier revision that
    // reconstructed a fresh @GestureState var on Core from just the bare
    // wrapper name (closure silently swapped for the default reset, label stuck
    // at "resets 0"), and went green once @Shell instead copied the host's own
    // declaration onto Core byte-for-byte, attribute arguments included.
    @MainActor
    func testCustomResetClosureFiresWhenGestureEnds() {
        let app = launchExampleApp(scenario: "GestureState")

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
