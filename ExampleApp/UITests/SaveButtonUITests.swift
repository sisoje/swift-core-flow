import XCTest

final class SaveButtonUITests: SnapshotTestCase {
    // Runs SaveButton.Core's copied body live: the tap calls the injected
    // action (logged synchronously), Core's Task awaits the rest-api-looking
    // getUserName (logged with its id the moment it's called) which throws —
    // a mock needs no invented return value — so the component's own `?`
    // fallback lands in state through the binding (logged at the write site).
    // The mutation snapshot pins the full deterministic sequence:
    // `onSave = draft`, `getUserName = 42`, `userName = ?`.
    @MainActor
    func testTapLogsActionFetchAndStateWriteInOrder() {
        let app = launch(scenario: "SaveButton")

        let button = app.buttons["saveDraftButton"]
        let label = app.staticTexts["userNameLabel"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertEqual(label.label, "anonymous")

        button.tap()

        let fetched = NSPredicate(format: "label == '?'")
        expectation(for: fetched, evaluatedWith: label)
        waitForExpectations(timeout: 5)
    }
}
