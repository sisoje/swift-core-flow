import CoreFlow
import SwiftUI

/// A direct write and a `$` binding write — from a real `Toggle` — log
/// through the same setter, and both values stay live.
struct TestStateScenario: View {
    @TestState private var count = 0
    @TestState private var isOn = false

    var body: some View {
        VStack {
            Button("increment") { count += 1 }
            Text(verbatim: "count \(count)")
            Toggle("switch", isOn: $isOn)
            Text(isOn ? "on" : "off")
        }
    }
}

#Preview {
    TestStateScenario()
}
