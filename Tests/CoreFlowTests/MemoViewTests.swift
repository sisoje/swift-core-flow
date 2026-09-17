import CoreFlow
import Observation
import SwiftUI
import Testing

// Compiled usage of the MemoView surface; rebuild-on-change and
// keep-across-renders are hosted, in CoreFlowHosted.

@Observable
private final class Doubler {
    let seed: Int
    init(seed: Int) {
        self.seed = seed
    }

    var doubled: Int {
        seed * 2
    }
}

@MainActor
struct MemoViewTests {
    @Test func initTypechecksInABody() {
        struct Probe: View {
            var seed = 1

            var body: some View {
                MemoView(Doubler(seed: seed), dependencies: [seed]) { doubler in
                    Text(verbatim: "\(doubler.doubled)")
                }
                MemoView(DateFormatter()) { formatter in
                    Text(verbatim: formatter.string(from: .distantPast))
                }
            }
        }
        _ = Probe()
    }
}
