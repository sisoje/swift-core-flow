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

    /// Mac Catalyst releases a removed view's storage when the app handles
    /// its NEXT event, and an idle test sends none: a test waiting on a
    /// teardown moves the pointer. Nothing to do on an iPhone.
    func movePointer() {
        #if targetEnvironment(macCatalyst)
            windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.25)).hover()
        #endif
    }
}

extension XCUIElement {
    /// One spelling for both destinations: on Mac Catalyst `tap()` sends
    /// nothing, on an iPhone `click()` fails ("Pointer events are not
    /// supported for this device").
    func tapOrClick() {
        #if targetEnvironment(macCatalyst)
            click()
        #else
            tap()
        #endif
    }
}

extension XCUICoordinate {
    /// The drag, under the same split as `tapOrClick()`.
    func pressOrClick(forDuration duration: TimeInterval, thenDragTo other: XCUICoordinate) {
        #if targetEnvironment(macCatalyst)
            click(forDuration: duration, thenDragTo: other)
        #else
            press(forDuration: duration, thenDragTo: other)
        #endif
    }
}
