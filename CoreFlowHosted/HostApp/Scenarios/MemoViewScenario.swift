import CoreFlow
import Observation
import SwiftUI

/// A parent value handed to a child that builds an `@Observable` model from
/// it: `@State` builds the model once and keeps showing the first value,
/// `MemoView` rebuilds it when the value changes and keeps it otherwise.
struct MemoViewScenario: View {
    @Observable
    final class Doubler {
        let seed: Int
        var taps = 0
        init(seed: Int) {
            self.seed = seed
        }

        var doubled: Int {
            seed * 2
        }
    }

    struct StateChild: View {
        @State private var doubler: Doubler
        init(seed: Int) {
            _doubler = State(wrappedValue: Doubler(seed: seed))
        }

        var body: some View {
            Text(verbatim: "state \(doubler.doubled)")
        }
    }

    struct MemoChild: View {
        let seed: Int
        @TestLog private var log

        var body: some View {
            MemoView(build(), dependencies: [seed]) { doubler in
                Text(verbatim: "memo \(doubler.doubled) taps \(doubler.taps)")
                Button("tap") { doubler.taps += 1 }
            }
        }

        private func build() -> Doubler {
            log("doubler", "\(seed)")
            return Doubler(seed: seed)
        }
    }

    @TestState private var seed = 1
    @TestState private var unrelated = 0

    var body: some View {
        VStack {
            Button("seed") { seed += 1 }
            Button("unrelated") { unrelated += 1 }
            // Read in body, so each unrelated write re-renders this view.
            Text(verbatim: "unrelated \(unrelated)")
            StateChild(seed: seed)
            MemoChild(seed: seed)
        }
    }
}

#Preview {
    MemoViewScenario()
}
