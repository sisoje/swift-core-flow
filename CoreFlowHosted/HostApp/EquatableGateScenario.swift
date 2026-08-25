import CoreFlow
import SwiftUI

/// Probe: does `.equatable()` skip the body of an unchanged view under an
/// isolated (`@MainActor Equatable`) conformance, and under a nonisolated one?
struct EquatableGateScenario: View {
    @TestState private var unrelated = 0

    init() {}

    var body: some View {
        VStack {
            Button("unrelated") { unrelated += 1 }
            Text(verbatim: "\(unrelated)")
            IsolatedGate(flag: false).equatable()
            NonisolatedGate(flag: false).equatable()
        }
    }
}

struct IsolatedGate: View, @MainActor Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.flag == rhs.flag
    }

    let flag: Bool
    @TestLog private var log

    var body: some View {
        let _ = log("isolated", "body")
        Text("isolated")
    }
}

struct NonisolatedGate: View, Equatable {
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.flag == rhs.flag
    }

    nonisolated let flag: Bool
    @TestLog private var log

    var body: some View {
        let _ = log("nonisolated", "body")
        Text("nonisolated")
    }
}

#Preview {
    EquatableGateScenario()
}
