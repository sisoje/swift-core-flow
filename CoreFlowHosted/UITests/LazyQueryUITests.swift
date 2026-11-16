import CoreFlowUITesting
import XCTest

final class LazyQueryUITests: XCTestCase {
    @MainActor
    func testCallingTheMemberBuildsNothingAndItsArgumentGatesTheQuery() {
        let app = XCUIApplication.launch(TestScenario.lazyQuery)
        XCTAssertTrue(app.buttons["unrelated"].waitUntil(\.exists, equals: true, timeout: 5))
        for _ in 1 ... 3 {
            app.buttons["unrelated"].tapOrClick()
        }
        app.buttons["sort"].tapOrClick()

        // The member is called on every render and builds nothing: one
        // construction at first appearance, none across three unrelated
        // writes, one more when the argument changes. No dependency list was
        // written anywhere; the argument is the dependency.
        let names = #"["query","unrelated","unrelated","unrelated","sortDescending","query"]"#
        XCTAssertTrue(app.logElement.waitUntil(\.label, equals: names, timeout: 5), app.logElement.label)
        XCTAssertEqual(app.logElement.logValues, ["forward", "1", "2", "3", "true", "reverse"])
    }
}
