import CoreFlow
import SwiftUI

extension EnvironmentValues {
    @FlowUp var scenarioFlow: (String) -> Void
    /// Same closure shape, different flow: its leaf must stay silent.
    @FlowUp var scenarioOtherFlow: (String) -> Void
}

struct FlowUpScenario: View {
    @TestState private var showSecond = false

    var body: some View {
        VStack {
            FlowCaller()
            FlowLeaf(name: "first")
            if showSecond {
                FlowLeaf(name: "second")
            }
            OtherLeaf()
            Button("show second") { showSecond = true }
        }
        .collectFlow(\.scenarioFlow)
        .collectFlow(\.scenarioOtherFlow)
    }
}

struct FlowCaller: View {
    @Environment(\.scenarioFlow) private var flow
    @TestLog private var log

    var body: some View {
        Button("send") {
            log("send", "hi")
            flow("hi")
        }
    }
}

struct FlowLeaf: View {
    let name: String
    @TestLog private var log

    var body: some View {
        Text(name)
            .onFlow(\.scenarioFlow) { log(name, $0) }
    }
}

struct OtherLeaf: View {
    @TestLog private var log

    var body: some View {
        Text("other")
            .onFlow(\.scenarioOtherFlow) { log("other", $0) }
    }
}

#Preview {
    FlowUpScenario()
}
