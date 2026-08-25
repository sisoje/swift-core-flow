import XCTest

final class QueryViewInsertUITests: XCTestCase {
    @MainActor
    func testInsertThroughTheQueryContextUpdatesTheList() {
        let app = launchApp(scenario: "QueryViewInsert")
        XCTAssertTrue(app.buttons["insert"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Dune"].exists)
        app.buttons["insert"].tap()
        XCTAssertTrue(app.staticTexts["Dune"].exists)
    }
}
