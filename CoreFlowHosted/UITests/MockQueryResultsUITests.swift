import CoreFlowUITesting
import XCTest

final class MockQueryResultsUITests: XCTestCase {
    @MainActor
    func testQueriesMockedByNameRenderTheirOwnResultAndFetchError() {
        let app = XCUIApplication.launch(TestScenario.mockQueryResults)
        // Two queries of one result type, each with the rows its own member
        // was mocked with, and no container anywhere.
        XCTAssertTrue(app.staticTexts["sciFi Dune"].waitUntil(\.exists, equals: true, timeout: 5))
        XCTAssertTrue(app.staticTexts["horror It"].exists)
        XCTAssertTrue(app.staticTexts["TagsUnavailable()"].exists)
    }
}
