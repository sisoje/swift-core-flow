import CoreFlow
import SwiftUI

extension EnvironmentValues {
    @FlowUp var scenarioHeldFlow: (String) -> Void
}

/// A closure held longer than one pass: the sender's task takes the flow's
/// closure once, before any listener has registered, and calls it for as
/// long as the scenario lives. The listeners are taken out and put back.
struct FlowUpHeldScenario: View {
    @TestState private var shown = true

    var body: some View {
        VStack {
            HeldSender()
            if shown {
                HeldLeaf(name: "first")
                HeldLeaf(name: "second")
            }
            Button("toggle") { shown.toggle() }
        }
        .collectFlow(\.scenarioHeldFlow)
    }
}

struct HeldSender: View {
    @Environment(\.scenarioHeldFlow) private var flow
    @State private var pipe = AsyncStream<String>.makeStream()
    @TestLog private var log

    var body: some View {
        Button("send") {
            log("send", "hi")
            pipe.continuation.yield("hi")
        }
        .task {
            for await value in pipe.stream {
                flow(value)
            }
        }
    }
}

struct HeldLeaf: View {
    let name: String
    @TestLog private var log

    var body: some View {
        Text(name)
            .onFlow(\.scenarioHeldFlow) { log(name, $0) }
    }
}

#Preview {
    FlowUpHeldScenario()
}
