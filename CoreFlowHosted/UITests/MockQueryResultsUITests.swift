import XCTest

final class MockQueryResultsUITests: XCTestCase {
    @MainActor
    func testCannedResultAndCannedFetchErrorRender() {
        let app = launchApp(scenario: "MockQueryResults")
        XCTAssertTrue(app.staticTexts["Dune"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["TagsUnavailable()"].exists)
    }
}
