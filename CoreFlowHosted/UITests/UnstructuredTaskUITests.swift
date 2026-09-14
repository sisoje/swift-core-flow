import XCTest

final class UnstructuredTaskUITests: XCTestCase {
    @MainActor
    func testHidingTheHostCancelsItsTask() {
        let app = launchApp(scenario: .unstructuredTask)
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 5))
        app.buttons["start"].tap()
        app.buttons["hide"].tap()

        let names = #"["work","showWorker","cancelled"]"#
        XCTAssertTrue(app.log.wait(for: \.label, toEqual: names, timeout: 5), app.log.label)
        XCTAssertEqual(app.logValues, ["task", "false", "work"])
    }

    @MainActor
    func testReassigningTheSameTaskLogsButDoesNotCancel() {
        let app = launchApp(scenario: .unstructuredTask)
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 5))
        app.buttons["start"].tap()
        app.buttons["reassign"].tap()
        app.buttons["clear"].tap()

        // One `cancelled`, from the clear — the reassignment cancelled nothing.
        let names = #"["work","work","work","cancelled"]"#
        XCTAssertTrue(app.log.wait(for: \.label, toEqual: names, timeout: 5), app.log.label)
        XCTAssertEqual(app.logValues, ["task", "task", "nil", "work"])
    }

    @MainActor
    func testClearingTheSlotLogsNilAndCancelsTheTask() {
        let app = launchApp(scenario: .unstructuredTask)
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 5))
        app.buttons["start"].tap()
        app.buttons["clear"].tap()

        let names = #"["work","work","cancelled"]"#
        XCTAssertTrue(app.log.wait(for: \.label, toEqual: names, timeout: 5), app.log.label)
        XCTAssertEqual(app.logValues, ["task", "nil", "work"])
    }
}
