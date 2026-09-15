import Foundation

/// The one value a test hands the app, JSON in `launchEnvironment`; both
/// targets compile this file, so the key, the log element's name, and the
/// scenario set exist once. Test-only code: encoding failures are `try!`.
nonisolated struct TestPayload: Codable {
    static let testPayloadEnvironmentKey = "testPayloadEnvironmentKey"
    static let logAccessibilityIdentifier = "logAccessibilityIdentifier"

    let scenario: TestScenario

    var encoded: String {
        String(decoding: try! JSONEncoder().encode(self), as: UTF8.self)
    }

    static func decode(_ string: String) -> TestPayload {
        try! JSONDecoder().decode(TestPayload.self, from: Data(string.utf8))
    }
}
