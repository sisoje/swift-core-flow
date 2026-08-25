import XCTest

// SectionedResults exists only in SwiftData >= 180 (the 27 SDKs).
#if canImport(SwiftData, _version: 180)
    final class QueryViewSectionedUITests: XCTestCase {
        @MainActor
        func testLiveSectionedQueryRendersSectionsAndRows() {
            let app = launchApp(scenario: "QueryViewSectionedLive")
            XCTAssertTrue(app.staticTexts["Dune"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Anathem"].exists)
            XCTAssertTrue(app.staticTexts["It"].exists)
            XCTAssertTrue(app.staticTexts["Sci-Fi"].exists)
            XCTAssertTrue(app.staticTexts["Horror"].exists)
        }

        @MainActor
        func testFabricatedSectionedResultsRenderThroughRealSwiftUI() {
            let app = launchApp(scenario: "QueryViewSectionedMocked")
            XCTAssertTrue(app.staticTexts["Dune"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Anathem"].exists)
            XCTAssertTrue(app.staticTexts["It"].exists)
            XCTAssertTrue(app.staticTexts["Sci-Fi"].exists)
            XCTAssertTrue(app.staticTexts["Horror"].exists)
        }
    }
#endif
