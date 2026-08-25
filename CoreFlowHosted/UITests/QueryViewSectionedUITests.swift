import XCTest

// SectionedResults exists only in the 27 SDKs (Xcode 27 = Swift 6.4).
#if compiler(>=6.4)
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
