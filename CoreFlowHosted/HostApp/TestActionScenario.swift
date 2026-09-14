import CoreFlow
import SwiftUI

struct TestActionScenario: View {
    @TestAction private var save: (String) -> Void = { _ in }
    @TestAction private var fetch: @Sendable (Int) async throws -> Int = { $0 * 2 }
    @TestState private var fetched = 0

    var body: some View {
        VStack {
            Button("save") { save("draft") }
            Button("fetch") {
                Task { fetched = try await fetch(3) }
            }
            Text(verbatim: "fetched \(fetched)")
        }
    }
}

#Preview {
    TestActionScenario()
}
