import CoreFlow
import SwiftUI

extension EnvironmentValues {
    @FlowUp var scenarioSave: (String) async throws -> Void
}

struct SaveFailure: Error {}

/// The first listener logs and throws; the second is never called.
struct FlowUpThrowsScenario: View {
    var body: some View {
        VStack {
            ThrowsCaller()
            ThrowsLeaf(name: "first", fails: true)
            ThrowsLeaf(name: "second", fails: false)
        }
        .collectFlow(\.scenarioSave)
    }
}

struct ThrowsCaller: View {
    @Environment(\.scenarioSave) private var save
    @TestLog private var log

    var body: some View {
        Button("send") {
            Task {
                log("send", "hi")
                do {
                    try await save("hi")
                } catch {
                    log("result", "\(error)")
                }
            }
        }
    }
}

struct ThrowsLeaf: View {
    let name: String
    let fails: Bool
    @TestLog private var log

    var body: some View {
        Text(name)
            .onFlow(\.scenarioSave) { value in
                log(name, value)
                if fails {
                    throw SaveFailure()
                }
            }
    }
}

#Preview {
    FlowUpThrowsScenario()
}
