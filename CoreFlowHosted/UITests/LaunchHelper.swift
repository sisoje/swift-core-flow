import CoreFlowUITesting
import XCTest

/// The app is a separate process and inherits nothing from the shell that
/// invoked xcodebuild, so every test hands it a `TestPayload`.
@MainActor
func launchApp(scenario: TestScenario) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment[TestPayload.testPayloadEnvironmentKey] = TestPayload(scenario: scenario).encoded
    app.launch()
    return app
}

extension XCUIApplication {
    var log: XCUIElement {
        uiTestLog(accessibilityIdentifier: TestPayload.logAccessibilityIdentifier)
    }
}
