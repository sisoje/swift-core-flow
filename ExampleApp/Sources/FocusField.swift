import SwiftUI
import ValueFlow

// The live-focus verification view: @FocusState declared on the host,
// substituted into Core as `@FocusState<Bool>.Binding`. Both directions are
// exercised live: tapping the field moves the OS's real focus into our read
// (system → view), and the toggle button writes back out (view → system).
// See UITests/FocusFieldUITests.swift.
@Shell
struct FocusField: View {
    @FocusState private var isFocused: Bool

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
