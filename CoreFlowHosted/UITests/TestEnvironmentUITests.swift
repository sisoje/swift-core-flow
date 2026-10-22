import CoreFlowUITesting
import XCTest

final class TestEnvironmentUITests: XCTestCase {
    @MainActor
    func testDismissLogsAndReallyDismisses() {
        let app = XCUIApplication.launch(TestScenario.testEnvironment)
        XCTAssertTrue(app.buttons["present"].waitUntil(\.exists, equals: true, timeout: 5))
        app.buttons["present"].tapOrClick()
        XCTAssertTrue(app.buttons["close"].waitUntil(\.exists, equals: true, timeout: 5))

        app.buttons["close"].tapOrClick()
        // The real DismissAction ran: SwiftUI writes the sheet binding back
        // through the scenario's @TestState.
        #if os(macOS)
            XCTAssertTrue(app.logElement.waitUntil(\.label, equals: #"["isPresented","dismiss","isPresented"]"#, timeout: 5), app.logElement.label)
            XCTAssertEqual(app.logElement.logValues, ["true", "", "false"])
        #else
            // Twice on UIKit, as the sheet finishes.
            XCTAssertTrue(app.logElement.waitUntil(\.label, equals: #"["isPresented","dismiss","isPresented","isPresented"]"#, timeout: 5), app.logElement.label)
            XCTAssertEqual(app.logElement.logValues, ["true", "", "false", "false"])
        #endif
        XCTAssertFalse(app.buttons["close"].exists)
    }
}
