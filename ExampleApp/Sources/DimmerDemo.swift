import CoreFlow
import SwiftUI

// The ViewModifier verification: @Shell on a ViewModifier host —
// body(content:) is written once and copied into Core, which gets its own
// `: ViewModifier` conformance. See UITests/DimmerUITests.swift.
@Shell
struct Dimmer: ViewModifier {
    @State private var isDimmed: Bool = false

    func body(content: Content) -> some View {
        VStack(spacing: 16) {
            Text(isDimmed ? "dimmed" : "bright")
                .accessibilityIdentifier("dimStatusLabel")
            content
                .opacity(isDimmed ? 0.2 : 1)
            Button("Toggle Dim") {
                isDimmed.toggle()
            }
            .accessibilityIdentifier("toggleDimButton")
        }
    }
}

// Core component under test, mutations logged at the write site: every tap
// on the toggle (inside Core's COPIED body) writes through the
// @TestState-generated $isDimmed binding and lands in the snapshot log the
// moment it happens — deterministic, so the whole interaction is verified
// as a recorded mutation sequence.
struct DimmerScenario: View {
    @TestState var isDimmed = false

    var body: some View {
        Text("Hello")
            .accessibilityIdentifier("dimContent")
            .modifier(Dimmer.Core(isDimmed: $isDimmed))
    }
}

#Preview {
    DimmerScenario()
}
