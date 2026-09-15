import CoreFlow
import SwiftUI

/// Receiving-side focus with the REAL projection: the owner's
/// `@TestFocusState` hands `$isFocused` to a child declaring the nominal
/// `FocusState<Bool>.Binding`. Focus moves for real in both directions;
/// only the owner's property writes log — the projection wires.
struct FocusReceiver: View {
    let focus: FocusState<Bool>.Binding
    @State private var text = ""

    var body: some View {
        TextField("field", text: $text)
            .focused(focus)
            .accessibilityIdentifier("field")
        Button("focus child") { focus.wrappedValue = true }
        Button("unfocus child") { focus.wrappedValue = false }
    }
}

struct FocusBindingScenario: View {
    @TestFocusState private var isFocused: Bool

    var body: some View {
        VStack {
            Text(isFocused ? "focused" : "unfocused")
                .accessibilityIdentifier("focusStatus")
            FocusReceiver(focus: $isFocused)
            Button("focus owner") { isFocused = true }
        }
    }
}

#Preview {
    FocusBindingScenario()
}
