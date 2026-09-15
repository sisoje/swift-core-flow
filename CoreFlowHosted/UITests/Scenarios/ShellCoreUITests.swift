import XCTest

final class ShellCoreUITests: XCTestCase {
    @MainActor
    func testHostedCoreSubstitutionsLogAndRender() {
        let app = launchApp(scenario: .shellCore)
        XCTAssertTrue(app.buttons["toggle"].waitForExistence(timeout: 5))
        app.buttons["toggle"].tap()
        app.buttons["rename"].tap()
        app.buttons["focus"].tap()

        XCTAssertTrue(app.staticTexts["mocked greeting"].exists)
        XCTAssertTrue(app.staticTexts["Dune"].exists)
        XCTAssertTrue(app.staticTexts["on"].exists)
        XCTAssertTrue(app.staticTexts["renamed"].exists)
        XCTAssertTrue(app.log.wait(for: \.label, toEqual: #"["isOn","name","isFocused"]"#, timeout: 5), app.log.label)
        XCTAssertEqual(app.log.logValues, ["true", "renamed", "true"])
    }
}
