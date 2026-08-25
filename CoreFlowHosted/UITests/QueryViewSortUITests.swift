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

        // No gate: every re-render constructs the query again. How many times
        // the first appearance renders is build-dependent (2 on 27A5252f, 3 on
        // the 27 beta 4 simulator), so only the tail after launch is exact.
        let names = #""unrelated","query","unrelated","query","unrelated","query","sortDescending","query"]"#
        let values = #""1","forward","2","forward","3","forward","true","reverse"]"#
        XCTAssertTrue(app.log.label.hasPrefix(#"["query""#))
        XCTAssertTrue(app.log.label.hasSuffix(names), app.log.label)
        XCTAssertTrue((app.log.value as? String ?? "").hasSuffix(values))
    }
}
