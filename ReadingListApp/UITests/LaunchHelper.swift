import XCTest

/// Launches the app on `scenario` via the SCENARIO launch-environment
/// variable — the app is a separate process and inherits nothing else.
@MainActor
func launchApp(scenario: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["SCENARIO"] = scenario
    app.launch()
    return app
}

extension XCUIApplication {
    /// The mutation-log element: names JSON in `label` (fixed identifiers —
    /// wait on it, `log.wait(for: \.label, toEqual: ...)`, which is also the
    /// test's finish line), values JSON in `value` (arbitrary content —
    /// `logValues` decodes it, compare as array once the names matched).
    var log: XCUIElement { otherElements["log"] }

    var logValues: [String] {
        let json = log.value as? String ?? "[]"
        return (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
    }
}
