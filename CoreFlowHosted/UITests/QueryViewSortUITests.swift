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

        // Three unrelated writes re-render the parent with no query
        // construction between them; only the index write constructs again.
        // How many times the first appearance constructs is build-dependent
        // (1 on the release simulator, 3 on the 27 beta 6 runner), so only the
        // tail after launch is exact.
        let names = #""unrelated","unrelated","unrelated","sortDescending","query"]"#
        let values = #""1","2","3","true","reverse"]"#
        XCTAssertTrue(app.log.label.hasPrefix(#"["query""#), app.log.label)
        XCTAssertTrue(app.log.label.hasSuffix(names), app.log.label)
        XCTAssertTrue((app.log.value as? String ?? "").hasSuffix(values))
    }

    @MainActor
    func testUngatedConstructsQueryOnEveryRender() {
        let app = launchApp(scenario: .queryViewUngated)
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
