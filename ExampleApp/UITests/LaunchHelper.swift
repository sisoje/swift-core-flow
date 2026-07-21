import XCTest

/// Launches the app, forwarding EXAMPLE_SCENARIO from this test process's own
/// environment into the app-under-test's `launchEnvironment` — a separate
/// process that doesn't see this one's environment unless told to (verified
/// directly). The shell sets it as `TEST_RUNNER_EXAMPLE_SCENARIO`; xcodebuild
/// strips that prefix when handing it to this process (also verified
/// directly — see testGestureState.sh).
func launchExampleApp() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["EXAMPLE_SCENARIO"] = ProcessInfo.processInfo.environment["EXAMPLE_SCENARIO"]
    app.launch()
    return app
}
