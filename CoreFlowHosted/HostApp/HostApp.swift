import CoreFlow
import SwiftUI

@main
struct CoreFlowHostApp: App {
    private let scenario: TestScenario

    init() {
        guard let raw = ProcessInfo.processInfo.environment[TestPayload.testPayloadEnvironmentKey] else {
            fatalError("\(TestPayload.testPayloadEnvironmentKey) not set")
        }
        scenario = TestPayload.decode(raw).scenario
    }

    var body: some Scene {
        WindowGroup {
            scenario
                .uiTestLog(accessibilityIdentifier: TestPayload.logAccessibilityIdentifier)
        }
    }
}
