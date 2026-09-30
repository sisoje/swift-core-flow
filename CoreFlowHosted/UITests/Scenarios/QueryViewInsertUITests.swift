import XCTest

final class QueryViewInsertUITests: XCTestCase {
    @MainActor
    func testInsertThroughTheQueryContextUpdatesTheList() {
        let app = launchApp(scenario: .queryViewInsert)
        XCTAssertTrue(app.buttons["insert"].waitUntil(\.exists, equals: true, timeout: 5))
        XCTAssertFalse(app.staticTexts["Novel 1"].exists)
        app.buttons["insert"].tapOrClick()
        XCTAssertTrue(app.staticTexts["Novel 1"].exists)
    }

    @MainActor
    func testMemoizedQueryKeepsItsLiveResultsAcrossUnrelatedRenders() {
        let app = launchApp(scenario: .queryViewInsert)
        XCTAssertTrue(app.buttons["insert"].waitUntil(\.exists, equals: true, timeout: 5))
        let rows = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Novel '"))
        for _ in 1 ... 5 {
            app.buttons["insert"].tapOrClick()
        }
        XCTAssertTrue(app.staticTexts["Novel 5"].waitUntil(\.exists, equals: true, timeout: 5))
        XCTAssertEqual(rows.count, 5)

        // The parent re-renders and hands `QueryView` the query it memoized
        // when the store was empty: the five inserts are still there.
        app.buttons["unrelated"].tapOrClick()
        XCTAssertTrue(app.staticTexts["unrelated 1"].waitUntil(\.exists, equals: true, timeout: 5))
        XCTAssertEqual(rows.count, 5)

        // And it still observes: a sixth insert lands after the re-render.
        app.buttons["insert"].tapOrClick()
        XCTAssertTrue(app.staticTexts["Novel 6"].waitUntil(\.exists, equals: true, timeout: 5))
        XCTAssertEqual(rows.count, 6)
    }

    @MainActor
    func testMemoizedQueryKeepsItsAnimationAcrossUnrelatedRenders() {
        let app = launchApp(scenario: .queryViewInsert)
        XCTAssertTrue(app.buttons["insert"].waitUntil(\.exists, equals: true, timeout: 5))
        app.buttons["insert"].tapOrClick()
        XCTAssertTrue(app.staticTexts["Novel 1"].waitUntil(\.exists, equals: true, timeout: 5))
        app.buttons["unrelated"].tapOrClick()
        XCTAssertTrue(app.staticTexts["unrelated 1"].waitUntil(\.exists, equals: true, timeout: 5))
        app.buttons["insert"].tapOrClick()
        XCTAssertTrue(app.staticTexts["Novel 2"].waitUntil(\.exists, equals: true, timeout: 5))

        // Each insert reaches the content with the query's animation — also
        // after the parent re-rendered and handed the memoized query back;
        // the unrelated write itself carries none.
        let names = #"["animated","unrelated","animated"]"#
        XCTAssertTrue(app.log.waitUntil(\.label, equals: names, timeout: 5), app.log.label)
        XCTAssertEqual(app.log.logValues, ["1", "1", "2"])
    }
}
