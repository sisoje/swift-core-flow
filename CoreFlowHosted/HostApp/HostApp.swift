import CoreFlow
import SwiftUI

@main
struct CoreFlowHostApp: App {
    /// Optional: previews and Cmd-R launch without a payload and show nothing.
    private var payload: TestPayload? = ProcessInfo.processInfo.environment[TestPayload.testPayloadEnvironmentKey].map(TestPayload.decode)

    var body: some Scene {
        WindowGroup {
            payload?.scenario
                .uiTestLog(accessibilityIdentifier: TestPayload.logAccessibilityIdentifier)
        }
    }
}
