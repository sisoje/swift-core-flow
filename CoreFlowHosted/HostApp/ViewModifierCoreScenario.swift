import CoreFlow
import SwiftUI

@Shell
struct Dimmer: ViewModifier {
    @State private var isDimmed = false

    func body(content: Content) -> some View {
        VStack(spacing: 16) {
            Text(isDimmed ? "dimmed" : "bright")
                .accessibilityIdentifier("dimStatus")
            content
                .opacity(isDimmed ? 0.2 : 1)
            Button("toggle dim") { isDimmed.toggle() }
        }
    }
}

/// A `ViewModifier` host's `Core` hosted: the copied `body(content:)` wraps
/// real content, and its `@State` logs as `@TestState`.
struct ViewModifierCoreScenario: View {
    var body: some View {
        Text("content")
            .modifier(Dimmer.Core())
    }
}

#Preview {
    ViewModifierCoreScenario()
}
