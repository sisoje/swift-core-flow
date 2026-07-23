import XCTest

final class DragCardUITests: XCTestCase {
    // dragOffset is Core's own live @GestureState: mid-drag it streams
    // nonzero offsets (maxDistance grows through the binding), on release
    // GestureState resets to zero. Values are timing-dependent — behavior
    // asserts only.
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
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: 120, dy: 80)))

        XCTAssertTrue(currentLabel.wait(for: \.label, toEqual: "current 0", timeout: 5))
        XCTAssertNotEqual(maxLabel.label, "max 0")
    }
}
