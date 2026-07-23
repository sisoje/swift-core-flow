import XCTest

/// Launches the app, forwarding `scenario` into the app-under-test's
/// `launchEnvironment` as `EXAMPLE_SCENARIO` — a separate process that
/// doesn't see this one's environment unless told to (verified directly).
/// Every test states the scenario it needs explicitly; nothing is inherited
/// from the shell that invoked xcodebuild.
func launchExampleApp(scenario: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["EXAMPLE_SCENARIO"] = scenario
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
