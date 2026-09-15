import CoreFlow
import SwiftUI
import Testing

/// Public surface only: the two whitelisted shapes typecheck on a View, and reading a
/// property yields a callable that forwards to the environment's default
/// unhosted. Logging and the real action are hosted — CoreFlowHosted's
/// TestEnvironment scenario.
@MainActor
struct TestEnvironmentTests {
    struct Host: View {
        @TestEnvironment(\.dismiss) private var dismiss: () -> Void
        @TestEnvironment(\.openURL) private var openURL: (URL) -> Void

        var body: some View {
            Button("close") { dismiss() }
        }

        func callBoth() {
            dismiss()
            openURL(URL(string: "https://example.com")!)
        }
    }

    @Test func shapesTypecheckAndForwardUnhosted() {
        Host().callBoth()
    }
}
