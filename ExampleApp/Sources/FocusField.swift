import CoreFlow
import SwiftUI

// Live @FocusState verification: the wrapper is unmapped, so Core carries
// its own verbatim copy — tapping the field moves the OS's real focus into
// Core's read, the toggle button writes back out. See
// UITests/FocusFieldUITests.swift.
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

// Core component under test. No Binding-typed fields → no state to own,
// nothing to log: Core() constructs bare, behavior is asserted live.
struct FocusFieldScenario: View {
    var body: some View {
        FocusField.Core()
    }
}
