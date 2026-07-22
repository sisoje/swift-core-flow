import XCTest

final class DragCardUITests: XCTestCase {
    // The scenario hosts DragCard.Core via Core.make — maxDistance wired to
    // the CoreModel, dragOffset is Core's own live @GestureState. One real
    // drag proves the whole story: mid-drag the offset streams nonzero
    // values (maxLabel grows, written through the @State→@Binding
    // substitution into the model), and on release GestureState's own reset
    // snaps the offset back to zero. Behavior-asserted, no snapshot: drag
    // distances are device/timing-dependent.
    @MainActor
    func testDragUpdatesGestureStateAndResetsOnRelease() {
        let app = launchExampleApp(scenario: "DragCard")

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
