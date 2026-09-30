import XCTest

final class UnstructuredTaskUITests: XCTestCase {
    @MainActor
    func testHidingTheHostCancelsItsTask() {
        let app = launchApp(scenario: .unstructuredTask)
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 5))
        app.buttons["start"].tapOrClick()
        app.buttons["hide"].tapOrClick()

        let names = #"["work","showWorker","cancelled"]"#
        XCTAssertTrue(app.log.wait(for: \.label, toEqual: names, timeout: 5), app.log.label)
        XCTAssertEqual(app.log.logValues, ["task", "false", "work"])
    }

    @MainActor
    func testReassigningTheSameTaskLogsButDoesNotCancel() {
        let app = launchApp(scenario: .unstructuredTask)
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 5))
        app.buttons["start"].tapOrClick()
        app.buttons["reassign"].tapOrClick()
        app.buttons["clear"].tapOrClick()

        // One `cancelled`, from the clear — the reassignment cancelled nothing.
        let names = #"["work","work","work","cancelled"]"#
        XCTAssertTrue(app.log.wait(for: \.label, toEqual: names, timeout: 5), app.log.label)
        XCTAssertEqual(app.log.logValues, ["task", "task", "nil", "work"])
    }

    @MainActor
    func testClearingTheSlotLogsNilAndCancelsTheTask() {
        let app = launchApp(scenario: .unstructuredTask)
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 5))
        app.buttons["start"].tapOrClick()
        app.buttons["clear"].tapOrClick()

        let names = #"["work","work","cancelled"]"#
        XCTAssertTrue(app.log.wait(for: \.label, toEqual: names, timeout: 5), app.log.label)
        XCTAssertEqual(app.log.logValues, ["task", "nil", "work"])
    }
}
