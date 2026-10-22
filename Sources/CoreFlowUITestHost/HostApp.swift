import CoreFlow
import CoreFlowUITestShared
import SwiftUI

public struct HostApp<Scenario: Decodable & View>: App {
    private let scenario: Scenario? = ProcessInfo.processInfo.environment[UITestNames.launchPayloadEnvironmentVariable].map(JsonUtils.decode)

    public init() {}

    public var body: some Scene {
        WindowGroup {
            scenario?.uiTestLog()
        }
    }
}
