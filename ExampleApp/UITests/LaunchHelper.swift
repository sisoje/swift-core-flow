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
