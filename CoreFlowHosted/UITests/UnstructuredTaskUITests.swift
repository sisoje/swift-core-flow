import CoreFlowUITesting
import XCTest

final class UnstructuredTaskUITests: XCTestCase {
    @MainActor
    func testHidingTheHostCancelsItsTask() {
        let app = XCUIApplication.launch(TestScenario.unstructuredTask)
        XCTAssertTrue(app.buttons["start"].waitUntil(\.exists, equals: true, timeout: 5))
        app.buttons["start"].tapOrClick()
        app.buttons["hide"].tapOrClick()
        // Mac Catalyst releases the hidden view's storage on the app's next
        // event, so a second press: it cancels, then logs its own write.
        app.buttons["hide"].tapOrClick()

        let names = #"["work","showWorker","cancelled","showWorker"]"#
        XCTAssertTrue(app.logElement.waitUntil(\.label, equals: names, timeout: 5), app.logElement.label)
        XCTAssertEqual(app.logElement.logValues, ["task", "false", "work", "false"])
    }

    @MainActor
    func testReassigningTheSameTaskLogsButDoesNotCancel() {
        let app = XCUIApplication.launch(TestScenario.unstructuredTask)
        XCTAssertTrue(app.buttons["start"].waitUntil(\.exists, equals: true, timeout: 5))
        app.buttons["start"].tapOrClick()
        app.buttons["reassign"].tapOrClick()
        app.buttons["clear"].tapOrClick()

        // One `cancelled`, from the clear — the reassignment cancelled nothing.
        let names = #"["work","work","work","cancelled"]"#
        XCTAssertTrue(app.logElement.waitUntil(\.label, equals: names, timeout: 5), app.logElement.label)
        XCTAssertEqual(app.logElement.logValues, ["task", "task", "nil", "work"])
    }

    @MainActor
    func testClearingTheSlotLogsNilAndCancelsTheTask() {
        let app = XCUIApplication.launch(TestScenario.unstructuredTask)
        XCTAssertTrue(app.buttons["start"].waitUntil(\.exists, equals: true, timeout: 5))
        app.buttons["start"].tapOrClick()
        app.buttons["clear"].tapOrClick()

        let names = #"["work","work","cancelled"]"#
        XCTAssertTrue(app.logElement.waitUntil(\.label, equals: names, timeout: 5), app.logElement.label)
        XCTAssertEqual(app.logElement.logValues, ["task", "nil", "work"])
    }
}
