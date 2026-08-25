import XCTest

final class QueryViewSectionedUITests: XCTestCase {
    @MainActor
    func testLiveSectionedQueryRendersSectionsAndRows() throws {
        try XCTSkipIf(ProcessInfo.processInfo.operatingSystemVersionString < "Version 27.0 (Build 24A5423a)")
        let app = launchApp(scenario: "QueryViewSectionedLive")
        XCTAssertTrue(app.staticTexts["Dune"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Anathem"].exists)
        XCTAssertTrue(app.staticTexts["It"].exists)
        XCTAssertTrue(app.staticTexts["Sci-Fi"].exists)
        XCTAssertTrue(app.staticTexts["Horror"].exists)
    }

    @MainActor
    func testFabricatedSectionedResultsRenderThroughRealSwiftUI() throws {
        try XCTSkipIf(ProcessInfo.processInfo.operatingSystemVersionString < "Version 27.0 (Build 24A5423a)")
        let app = launchApp(scenario: "QueryViewSectionedMocked")
        XCTAssertTrue(app.staticTexts["Dune"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Anathem"].exists)
        XCTAssertTrue(app.staticTexts["It"].exists)
        XCTAssertTrue(app.staticTexts["Sci-Fi"].exists)
        XCTAssertTrue(app.staticTexts["Horror"].exists)
    }
}
