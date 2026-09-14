import CoreFlow
import SwiftUI

struct TestFocusStateScenario: View {
    @TestFocusState private var isFocused: Bool

    var body: some View {
        VStack {
            Text(isFocused ? "focused" : "unfocused")
                .accessibilityIdentifier("focusStatus")
            TextField("field", text: .constant(""))
                .focused($isFocused)
                .accessibilityIdentifier("field")
            Button("toggle focus") { isFocused.toggle() }
        }
    }
}

#Preview {
    TestFocusStateScenario()
}
