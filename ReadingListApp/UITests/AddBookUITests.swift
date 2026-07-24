import XCTest

final class AddBookUITests: XCTestCase {
    // Every keystroke is a binding write, logged the moment it happens — and
    // the log exposes TextField's real behavior: it writes the binding TWICE
    // per keystroke, plus two initial "" writes on focus. Pinned as-is; the
    // submit hands the full title to the action, the clear is the final write.
    @MainActor
    func testTypingSubmittingAndClearingAllLogInOrder() {
        let app = launchApp(scenario: "AddBook")

        let field = app.textFields["titleField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Dune")
        app.buttons["addButton"].tap()

        XCTAssertTrue(
            app.log.wait(
                for: \.label,
                toEqual: #"["title","title","title","title","title","title","title","title","title","title","onSubmit","title"]"#,
                timeout: 5))
        XCTAssertEqual(
            app.logValues,
            ["", "", "D", "D", "Du", "Du", "Dun", "Dun", "Dune", "Dune", "Dune", ""])
    }
}
