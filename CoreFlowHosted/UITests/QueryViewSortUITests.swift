import CoreFlowUITesting
import XCTest

final class QueryViewSortUITests: XCTestCase {
    @MainActor
    func testGatedIndexSkipsQueryConstructionOnUnrelatedWrites() {
        let app = XCUIApplication.launch(TestScenario.queryViewGated)
        XCTAssertTrue(app.buttons["unrelated"].waitUntil(\.exists, equals: true, timeout: 5))
        for _ in 1 ... 3 {
            app.buttons["unrelated"].tapOrClick()
        }
        app.buttons["sort"].tapOrClick()

        // The memo constructs once at first appearance whatever the build
        // re-renders; three unrelated writes re-render the parent with no
        // construction between them; only the dependency write constructs again.
        let names = #"["query","unrelated","unrelated","unrelated","sortDescending","query"]"#
        XCTAssertTrue(app.logElement.waitUntil(\.label, equals: names, timeout: 5), app.logElement.label)
        XCTAssertEqual(app.logElement.logValues, ["forward", "1", "2", "3", "true", "reverse"])
    }

    @MainActor
    func testEmptyDependenciesBuildTheQueryOnceAndKeepIt() {
        let app = XCUIApplication.launch(TestScenario.queryViewUngated)
        XCTAssertTrue(app.buttons["unrelated"].waitUntil(\.exists, equals: true, timeout: 5))
        for _ in 1 ... 3 {
            app.buttons["unrelated"].tapOrClick()
        }
        app.buttons["sort"].tapOrClick()

        // No dependencies are always equal: one construction at first
        // appearance, none after — not even for the sort write the query
        // expression reads, since it was left out of the dependencies.
        let names = #"["query","unrelated","unrelated","unrelated","sortDescending"]"#
        XCTAssertTrue(app.logElement.waitUntil(\.label, equals: names, timeout: 5), app.logElement.label)
        XCTAssertEqual(app.logElement.logValues, ["forward", "1", "2", "3", "true"])
    }
}
