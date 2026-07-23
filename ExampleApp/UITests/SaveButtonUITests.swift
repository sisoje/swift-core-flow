import XCTest

final class SaveButtonUITests: XCTestCase {
    // One tap: the sync action fires, Core's Task awaits getUserName (the
    // mock throws — no invented values), the component's own error fallback
    // lands in state.
    @MainActor
    func testTapLogsActionFetchAndStateWriteInOrder() {
        let app = launchExampleApp(scenario: "SaveButton")

        let button = app.buttons["saveDraftButton"]
        let userName = app.staticTexts["userNameLabel"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertEqual(userName.label, "anonymous")

        button.tap()
        XCTAssertTrue(userName.wait(for: \.label, toEqual: "Error fetching user", timeout: 5))

        XCTAssertTrue(app.log.wait(for: \.label, toEqual: #"["onSave","getUserName","userName"]"#, timeout: 5))
        XCTAssertEqual(app.logValues, ["draft", "42", "Error fetching user"])
    }
}
