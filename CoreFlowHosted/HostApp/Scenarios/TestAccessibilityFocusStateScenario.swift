import CoreFlow
import SwiftUI

struct TestAccessibilityFocusStateScenario: View {
    @TestAccessibilityFocusState private var isFocused: Bool

    var body: some View {
        VStack {
            Text("hint")
                .accessibilityFocused($isFocused)
            Button("focus hint") { isFocused = true }
        }
    }
}

#Preview {
    TestAccessibilityFocusStateScenario()
}
