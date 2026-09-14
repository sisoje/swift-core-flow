import CoreFlow
import SwiftUI
import Testing

extension EnvironmentValues {
    @FlowUp var flowPing: (Int) -> Void
    @FlowUp var flowSave: (String) async throws -> Void
    @FlowUp var flowRefresh: () -> Void
    @FlowUp public var flowShared: (Int) -> Void
    @FlowUp var flowMain: @MainActor (Int) -> Void
}

/// Public surface only: the accessor's empty default and the two View
/// modifiers typechecking. Behavior (order, isolation, a throwing listener) is
/// hosted — CoreFlowHosted's FlowUp scenarios.
@MainActor
struct FlowUpTests {
    @Test func emptyDefaultCombinesToNoOp() async throws {
        EnvironmentValues().flowPing(1)
        EnvironmentValues().flowRefresh()
        try await EnvironmentValues().flowSave("x")
        EnvironmentValues().flowMain(2)
        EnvironmentValues().flowShared(3)
    }

    @Test func registrationAndAccumulationTypecheckInABody() {
        struct Probe: View {
            var body: some View {
                Text(verbatim: "probe")
                    .onFlow(\.flowPing) { _ in }
                    .onFlow(\.flowRefresh) {}
                    .onFlow(\.flowSave) { _ in }
                    .onFlow(\.flowMain) { _ in }
                    .onFlow(\.flowShared) { _ in }
                    .collectFlow(\.flowPing)
                    .collectFlow(\.flowRefresh)
                    .collectFlow(\.flowSave)
                    .collectFlow(\.flowMain)
                    .collectFlow(\.flowShared)
            }
        }
        _ = Probe()
    }
}
