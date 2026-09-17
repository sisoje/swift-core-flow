import XCTest

final class QueryViewSortUITests: XCTestCase {
    @MainActor
    func testGatedIndexSkipsQueryConstructionOnUnrelatedWrites() {
        let app = launchApp(scenario: .queryViewGated)
        XCTAssertTrue(app.buttons["unrelated"].waitForExistence(timeout: 5))
        for _ in 1 ... 3 {
            app.buttons["unrelated"].tap()
        }
        app.buttons["sort"].tap()

        // The memo constructs once at first appearance whatever the build
        // re-renders; three unrelated writes re-render the parent with no
        // construction between them; only the dependency write constructs again.
        let names = #"["query","unrelated","unrelated","unrelated","sortDescending","query"]"#
        XCTAssertTrue(app.log.wait(for: \.label, toEqual: names, timeout: 5), app.log.label)
        XCTAssertEqual(app.log.logValues, ["forward", "1", "2", "3", "true", "reverse"])
    }

    @MainActor
    func testEmptyDependenciesBuildTheQueryOnceAndKeepIt() {
        let app = launchApp(scenario: .queryViewUngated)
        XCTAssertTrue(app.buttons["unrelated"].waitForExistence(timeout: 5))
        for _ in 1 ... 3 {
            app.buttons["unrelated"].tap()
        }
        app.buttons["sort"].tap()

        // No dependencies are always equal: one construction at first
        // appearance, none after — not even for the sort write the query
        // expression reads, since it was left out of the dependencies.
        let names = #"["query","unrelated","unrelated","unrelated","sortDescending"]"#
        XCTAssertTrue(app.log.wait(for: \.label, toEqual: names, timeout: 5), app.log.label)
        XCTAssertEqual(app.log.logValues, ["forward", "1", "2", "3", "true"])
    }
}
