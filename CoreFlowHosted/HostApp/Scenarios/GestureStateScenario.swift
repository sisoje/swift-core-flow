import CoreFlow
import SwiftUI

enum ResetProbe {
    nonisolated(unsafe) static var count = 0
}

/// `@GestureState(reset:)` rides onto `Core` verbatim, custom reset included.
@Shell
struct DragBox: View {
    @GestureState(reset: { _, _ in ResetProbe.count += 1 })
    private var dragOffset: CGSize = .zero
    @State private var resetsSeen = 0

    var body: some View {
        VStack(spacing: 16) {
            Text(verbatim: "resets \(resetsSeen)")
                .accessibilityIdentifier("resets")
            Rectangle()
                .fill(.orange)
                .frame(width: 100, height: 100)
                .offset(dragOffset)
                .gesture(
                    DragGesture().updating($dragOffset) { value, state, _ in
                        state = value.translation
                    }
                )
                .accessibilityIdentifier("box")
        }
        .onChange(of: dragOffset) { _, new in
            if new == .zero {
                resetsSeen = ResetProbe.count
            }
        }
    }
}

struct GestureStateScenario: View {
    var body: some View {
        DragBox.Core()
    }
}

#Preview {
    GestureStateScenario()
}
