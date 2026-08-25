import CoreFlow
import SwiftUI

struct UnstructuredTaskScenario: View {
    @TestState private var showWorker = true

    var body: some View {
        VStack {
            Button("hide") { showWorker = false }
            if showWorker {
                Worker()
            }
        }
    }
}

struct Worker: View {
    @UnstructuredTask private var work: Task<Void, Never>?
    @TestLog private var log

    var body: some View {
        Button("start") {
            work = Task { [log] in
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    log("cancelled", "work")
                }
            }
        }
    }
}

#Preview {
    UnstructuredTaskScenario()
}
