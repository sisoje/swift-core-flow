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
        // construction between them; only the index write constructs again.
        let names = #"["query","unrelated","unrelated","unrelated","sortDescending","query"]"#
        XCTAssertTrue(app.log.wait(for: \.label, toEqual: names, timeout: 5), app.log.label)
        XCTAssertEqual(app.log.logValues, ["forward", "1", "2", "3", "true", "reverse"])
    }

    @MainActor
    func testNoIndexConstructsTheQueryOnce() {
        let app = launchApp(scenario: .queryViewUngated)
        XCTAssertTrue(app.buttons["unrelated"].waitForExistence(timeout: 5))
        for _ in 1 ... 3 {
            app.buttons["unrelated"].tap()
        }
        app.buttons["sort"].tap()

        // No index means no parameters: one construction, kept for good — even
        // the sort write, which the expression reads, rebuilds nothing.
        let names = #"["query","unrelated","unrelated","unrelated","sortDescending"]"#
        XCTAssertTrue(app.log.wait(for: \.label, toEqual: names, timeout: 5), app.log.label)
        XCTAssertEqual(app.log.logValues, ["forward", "1", "2", "3", "true"])
    }
}
