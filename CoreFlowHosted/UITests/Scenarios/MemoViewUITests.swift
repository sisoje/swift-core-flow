import XCTest

final class MemoViewUITests: XCTestCase {
    @MainActor
    func testMemoizedModelFollowsItsInputAndIsKeptOtherwise() {
        let app = launchApp(scenario: .memoView)
        XCTAssertTrue(app.staticTexts["memo 2 taps 0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["state 2"].exists)

        // The model holds its own state, and an unrelated parent re-render
        // keeps the instance: the tap is still there.
        app.buttons["tap"].tap()
        XCTAssertTrue(app.staticTexts["memo 2 taps 1"].waitForExistence(timeout: 5))
        app.buttons["unrelated"].tap()
        XCTAssertTrue(app.staticTexts["unrelated 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["memo 2 taps 1"].exists)

        // The input changes: MemoView builds a new model from it; the @State
        // child built its model once and still shows the first value.
        app.buttons["seed"].tap()
        XCTAssertTrue(app.staticTexts["memo 4 taps 0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["state 2"].exists)

        let names = #"["doubler","unrelated","seed","doubler"]"#
        XCTAssertTrue(app.log.wait(for: \.label, toEqual: names, timeout: 5), app.log.label)
        XCTAssertEqual(app.log.logValues, ["1", "1", "2", "2"])
    }
}
