import CoreFlow
import SwiftUI

extension EnvironmentValues {
    @FlowUp var scenarioFlow: (String) -> Void
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
            Button("show second") { showSecond = true }
        }
        .collectFlow(\.scenarioFlow)
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

#Preview {
    FlowUpScenario()
}
