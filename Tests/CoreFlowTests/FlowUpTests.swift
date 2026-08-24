@testable import CoreFlow
import SwiftUI
import Testing

extension EnvironmentValues {
    @FlowUp var flowPing: (Int) -> Void
    @FlowUp var flowPing2: (Int) -> Void
    @FlowUp var flowSave: (String) async throws -> Void
    @FlowUp var flowRefresh: () -> Void
    @FlowUp public var flowShared: (Int) -> Void
    @FlowUp var flowMain: @MainActor (Int) -> Void
}

private struct SaveFailure: Error {}

@MainActor
struct FlowUpTests {
    @Test func mainActorAttributedFlowRidesThePipeline() {
        var received: [Int] = []
        var env = EnvironmentValues()
        env[keyPath: EnvironmentValues.flowMain.keyPath] = [
            listener { @MainActor in received.append($0) },
        ]
        env.flowMain(3)
        #expect(received == [3])
    }

    @Test func emptyDefaultCombinesToNoOp() {
        EnvironmentValues().flowPing(1)
        EnvironmentValues().flowRefresh()
    }

    @Test func combinedClosureCallsEveryListenerInOrder() {
        var received: [Int] = []
        var env = EnvironmentValues()
        env[keyPath: EnvironmentValues.flowPing.keyPath] = [
            listener { received.append($0) },
            listener { received.append($0 + 100) },
        ]
        env.flowPing(7)
        #expect(received == [7, 107])
    }

    @Test func zeroParameterListenersAllRunInOrder() {
        var received: [String] = []
        var env = EnvironmentValues()
        env[keyPath: EnvironmentValues.flowRefresh.keyPath] = [
            listener { received.append("first") },
            listener { received.append("second") },
        ]
        env.flowRefresh()
        #expect(received == ["first", "second"])
    }

    @Test func combinedClosureReadsPayloadAtCallTime() {
        var received: [Int] = []
        let wrapper = listener { received.append($0) }
        var env = EnvironmentValues()
        env[keyPath: EnvironmentValues.flowPing.keyPath] = [wrapper]
        let combined = env.flowPing
        wrapper.closures = [{ received.append($0 + 1000) }]
        combined(1)
        #expect(received == [1001])
    }

    @Test func sameSignatureFlowsStayIsolated() {
        var received: [Int] = []
        var env = EnvironmentValues()
        env[keyPath: EnvironmentValues.flowPing.keyPath] = [listener { received.append($0) }]
        env.flowPing2(5)
        #expect(received.isEmpty)
        env.flowPing(5)
        #expect(received == [5])
    }

    @Test func throwingListenerAbortsRemainingListeners() async {
        var received: [String] = []
        var env = EnvironmentValues()
        env[keyPath: EnvironmentValues.flowSave.keyPath] = [
            listener { (value: String) throws in
                received.append(value)
                throw SaveFailure()
            },
            listener { (value: String) throws in received.append("second \(value)") },
        ]
        await #expect(throws: SaveFailure.self) {
            try await env.flowSave("x")
        }
        #expect(received == ["x"])
    }

    @Test func asyncListenersRunSequentiallyInRegistrationOrder() async throws {
        var received: [String] = []
        var env = EnvironmentValues()
        env[keyPath: EnvironmentValues.flowSave.keyPath] = [
            listener { received.append("first \($0)") },
            listener { received.append("second \($0)") },
        ]
        try await env.flowSave("s")
        #expect(received == ["first s", "second s"])
    }

    @Test func registrationAndAccumulationTypecheckInABody() {
        struct Probe: View {
            var body: some View {
                Text(verbatim: "probe")
                    .onFlow(\.flowPing) { _ in }
                    .onFlow(\.flowRefresh) {}
                    .collectFlow(\.flowPing)
                    .collectFlow(\.flowRefresh)
            }
        }
        _ = Probe()
    }

    private func listener<Closure>(_ closure: Closure) -> FlowUpClosure<Closure> {
        let wrapper = FlowUpClosure<Closure>()
        wrapper.closures = [closure]
        return wrapper
    }
}
