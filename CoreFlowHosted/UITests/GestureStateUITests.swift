import CoreFlowUITesting
import XCTest

final class GestureStateUITests: XCTestCase {
    @MainActor
    func testCustomResetFiresOnCoreWhenTheGestureEnds() {
        let app = XCUIApplication.launch(TestScenario.gestureState)
        let resets = app.staticTexts["resets"]
        XCTAssertTrue(resets.waitUntil(\.exists, equals: true, timeout: 5))
        XCTAssertEqual(resets.valueOrLabel, "resets 0")

        let box = app.otherElements["box"]
        let start = box.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        app.buttons["read"].tapOrClick()
        start.pressOrClick(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: 80, dy: -40)))
        app.buttons["read"].tapOrClick()

        XCTAssertTrue(resets.waitUntil(\.valueOrLabel, equals: "resets 1", timeout: 5), resets.valueOrLabel)
        XCTAssertTrue(app.logElement.waitUntil(\.label, equals: #"["resetsSeen","resetsSeen"]"#, timeout: 5), app.logElement.label)
        XCTAssertEqual(app.logElement.logValues, ["0", "1"])
    }
}
