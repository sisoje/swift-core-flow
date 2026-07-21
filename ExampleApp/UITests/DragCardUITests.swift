import XCTest

final class DragCardUITests: XCTestCase {
    // One real drag proves the whole @GestureState story live: mid-drag the
    // offset streams nonzero values (maxLabel grows — written back through
    // Core's substituted @State→@Binding, so that mechanism is live-verified
    // too), and on release GestureState's own reset snaps the offset back to
    // zero (currentLabel).
    @MainActor
    func testDragUpdatesGestureStateAndResetsOnRelease() {
        let app = XCUIApplication()
        app.launch()

        let box = app.otherElements["dragBox"]
        let maxLabel = app.staticTexts["maxLabel"]
        let currentLabel = app.staticTexts["currentLabel"]
        XCTAssertTrue(box.waitForExistence(timeout: 5))
        XCTAssertEqual(maxLabel.label, "max 0")
        XCTAssertEqual(currentLabel.label, "current 0")

        let start = box.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 120, dy: 80))
        start.press(forDuration: 0.2, thenDragTo: end)

        // The gesture streamed nonzero offsets while the finger was down...
        let movedPredicate = NSPredicate(format: "label != 'max 0'")
        expectation(for: movedPredicate, evaluatedWith: maxLabel)
        waitForExpectations(timeout: 5)

        // ...and snapped back to zero when it lifted (GestureState's reset).
        let resetPredicate = NSPredicate(format: "label == 'current 0'")
        expectation(for: resetPredicate, evaluatedWith: currentLabel)
        waitForExpectations(timeout: 5)
    }
}
