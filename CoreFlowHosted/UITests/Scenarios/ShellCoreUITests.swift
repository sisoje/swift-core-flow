import XCTest

final class ShellCoreUITests: XCTestCase {
    @MainActor
    func testHostedCoreSubstitutionsLogAndRender() {
        let app = launchApp(scenario: .shellCore)
        XCTAssertTrue(app.buttons["toggle"].waitUntil(\.exists, equals: true, timeout: 5))
        app.buttons["toggle"].tapOrClick()
        app.buttons["rename"].tapOrClick()
        app.buttons["focus"].tapOrClick()

        XCTAssertTrue(app.staticTexts["mocked greeting"].exists)
        XCTAssertTrue(app.staticTexts["Dune"].exists)
        XCTAssertTrue(app.staticTexts["on"].exists)
        XCTAssertTrue(app.staticTexts["renamed"].exists)
        XCTAssertTrue(app.log.waitUntil(\.label, equals: #"["isOn","name","isFocused"]"#, timeout: 5), app.log.label)
        XCTAssertEqual(app.log.logValues, ["true", "renamed", "true"])
    }
}
