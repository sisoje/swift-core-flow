import CoreFlowUITesting
import XCTest

final class FlowUpHeldUITests: XCTestCase {
    /// The sender's task holds the flow's closure from its first pass. It
    /// reaches the listeners that are there when it calls: both, then none
    /// while they are out of the tree, then the two that came back.
    @MainActor
    func testAHeldClosureReachesTheListenersThatAreThereWhenItCalls() {
        let app = XCUIApplication.launch(TestScenario.flowUpHeld)
        XCTAssertTrue(app.buttons["send"].waitUntil(\.exists, equals: true, timeout: 5))

        app.buttons["send"].tapOrClick()
        app.buttons["toggle"].tapOrClick()
        app.buttons["send"].tapOrClick()
        app.buttons["toggle"].tapOrClick()
        app.buttons["send"].tapOrClick()

        let names = #"["send","first","second","shown","send","shown","send","first","second"]"#
        XCTAssertTrue(app.logElement.waitUntil(\.label, equals: names, timeout: 5), app.logElement.label)
        XCTAssertEqual(app.logElement.logValues, ["hi", "hi", "hi", "false", "hi", "true", "hi", "hi", "hi"])
    }
}
