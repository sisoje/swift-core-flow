import XCTest

final class QueryViewSortUITests: XCTestCase {
    @MainActor
    func testGatedIndexSkipsQueryConstructionOnUnrelatedWrites() {
        let app = launchApp(scenario: "QueryViewGated")
        XCTAssertTrue(app.buttons["unrelated"].waitForExistence(timeout: 5))
        for _ in 1 ... 3 {
            app.buttons["unrelated"].tap()
        }
        app.buttons["sort"].tap()

        // Three unrelated writes re-render the parent with no query
        // construction between them; only the index write constructs again.
        let names = #"["query","unrelated","unrelated","unrelated","sortDescending","query"]"#
        XCTAssertTrue(app.log.wait(for: \.label, toEqual: names, timeout: 5))
        XCTAssertEqual(app.logValues, ["forward", "1", "2", "3", "true", "reverse"])
    }

    @MainActor
    func testUngatedConstructsQueryOnEveryRender() {
        let app = launchApp(scenario: "QueryViewUngated")
        XCTAssertTrue(app.buttons["unrelated"].waitForExistence(timeout: 5))
        for _ in 1 ... 3 {
            app.buttons["unrelated"].tap()
        }
        app.buttons["sort"].tap()

        // No gate: every re-render constructs the query again — including
        // the container's own setup re-render before any tap (the doubled
        // opening `query`), which the gated scenario absorbs.
        let names = #"["query","query","unrelated","query","unrelated","query","unrelated","query","sortDescending","query"]"#
        XCTAssertTrue(app.log.wait(for: \.label, toEqual: names, timeout: 5))
        XCTAssertEqual(
            app.logValues,
            ["forward", "forward", "1", "forward", "2", "forward", "3", "forward", "true", "reverse"]
        )
    }
}
