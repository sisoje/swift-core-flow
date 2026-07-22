import SwiftUI
import ValueFlow

// The ViewModifier verification: @Shell on a ViewModifier host, body(content:)
// written once as ordinary SwiftUI and copied into Core (which gets its own
// `: ViewModifier` conformance — its Content is a different concrete type
// than the host's, each satisfies the protocol independently).
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

// Deliberately applies Dimmer.CORE, not Dimmer — same module, so the internal
// Core is directly reachable, no import needed. The demo view owns the state;
// Core's substituted @Binding writes through to it, so the live test proves
// the COPIED body works end-to-end: tap the toggle inside Core's body →
// write through the @Binding → re-render. See UITests/DimmerUITests.swift.
struct DimmerDemo: View {
    @State private var isDimmed = false

    var body: some View {
        Text("Hello")
            .accessibilityIdentifier("dimContent")
            .modifier(Dimmer.Core(isDimmed: $isDimmed))
    }
}
