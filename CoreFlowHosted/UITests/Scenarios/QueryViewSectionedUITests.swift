import XCTest

final class QueryViewSectionedUITests: XCTestCase {
    @MainActor
    func testLiveSectionedQueryRendersSectionsAndRows() {
        let app = launchApp(scenario: .queryViewSectionedLive)
        XCTAssertTrue(app.staticTexts["Dune"].waitUntil(\.exists, equals: true, timeout: 5))
        XCTAssertTrue(app.staticTexts["Anathem"].exists)
        XCTAssertTrue(app.staticTexts["It"].exists)
        XCTAssertTrue(app.staticTexts["Sci-Fi"].exists)
        XCTAssertTrue(app.staticTexts["Horror"].exists)
    }

    @MainActor
    func testFabricatedSectionedResultsRenderThroughRealSwiftUI() {
        let app = launchApp(scenario: .queryViewSectionedMocked)
        XCTAssertTrue(app.staticTexts["Dune"].waitUntil(\.exists, equals: true, timeout: 5))
        XCTAssertTrue(app.staticTexts["Anathem"].exists)
        XCTAssertTrue(app.staticTexts["It"].exists)
        XCTAssertTrue(app.staticTexts["Sci-Fi"].exists)
        XCTAssertTrue(app.staticTexts["Horror"].exists)
    }
}
