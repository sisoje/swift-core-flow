import SwiftUI
import ValueFlow

// The live-focus verification view: @FocusState declared on the host,
// projected into Core as its own substituted `@FocusState<Bool>.Binding` —
// the SAME projected handle the host's real $isFocused already is, not a
// captured copy — so writes through it move real focus, live. Both
// directions are exercised: tapping the field moves the OS's real focus into
// our read (system → Core), and the toggle button — executed from Core's own
// body — writes back out to the host's real storage (Core → system). See
// UITests/FocusFieldUITests.swift.
@Shell
struct FocusField: View {
    @FocusState private var isFocused: Bool
}

extension FocusField.Core {
    var body: some View {
        VStack(spacing: 16) {
            Text(isFocused ? "focused" : "unfocused")
                .accessibilityIdentifier("focusStatusLabel")
            TextField("Type here", text: .constant(""))
                .focused($isFocused)
                .accessibilityIdentifier("focusTextField")
            Button("Toggle Focus") {
                isFocused.toggle()
            }
            .accessibilityIdentifier("toggleFocusButton")
        }
    }
}
