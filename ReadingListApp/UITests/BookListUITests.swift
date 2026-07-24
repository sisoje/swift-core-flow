import XCTest

final class BookListUITests: XCTestCase {
    // The fetched array is handed to Core directly — no ModelContainer in
    // this process. The sort toggle writes through @AppStorage's @Binding
    // substitution; delete is the injected action, logged with its payload.
    @MainActor
    func testSortWritesStorageAndDeleteLogsTheTitle() {
        let app = launchApp(scenario: "BookList")

        let firstTitle = app.staticTexts.matching(identifier: "bookTitle").firstMatch
        XCTAssertTrue(firstTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(firstTitle.label, "Anathem")  // sorted by title

        app.switches["sortToggle"].switches.firstMatch.tap()
        XCTAssertTrue(firstTitle.wait(for: \.label, toEqual: "Dune", timeout: 5))  // by author

        app.buttons["delete-Anathem"].tap()

        XCTAssertTrue(
            app.log.wait(for: \.label, toEqual: #"["sortByAuthor","onDelete"]"#, timeout: 5))
        XCTAssertEqual(app.logValues, ["true", "Anathem"])
    }
}
