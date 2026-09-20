import XCTest

final class MockQueryResultsUITests: XCTestCase {
    @MainActor
    func testCannedResultAndCannedFetchErrorRender() {
        let app = launchApp(scenario: .mockQueryResults)
        XCTAssertTrue(app.staticTexts["Dune"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["TagsUnavailable()"].exists)
        // An unregistered shape renders the query's own value: empty, and no
        // trap, with no container anywhere.
        XCTAssertTrue(app.staticTexts["unregistered sections 0"].exists)
    }
}
