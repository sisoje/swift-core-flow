import XCTest

final class UnstructuredTaskUITests: XCTestCase {
    @MainActor
    func testHidingTheHostCancelsItsTask() {
        let app = launchApp(scenario: "UnstructuredTask")
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 5))
        app.buttons["start"].tap()
        app.buttons["hide"].tap()

        let names = #"["work","showWorker","cancelled"]"#
        XCTAssertTrue(app.log.wait(for: \.label, toEqual: names, timeout: 5), app.log.label)
        XCTAssertEqual(app.logValues, ["task", "false", "work"])
    }
}
