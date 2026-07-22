import CoreFlow
import SwiftUI

/// Counts firings of the host's custom `reset:` closure, so a test can
/// observe that the closure actually ran.
enum ResetProbe {
    nonisolated(unsafe) static var count = 0
}

// The tricky part: an argument-carrying @GestureState — the developer's
// reset behavior lives in the attribute's own arguments, and @Shell copies
// the declaration onto Core byte-for-byte, so the closure rides along. See
// UITests/TrickyDragCardUITests.swift.
@Shell
struct TrickyDragCard: View {
    @GestureState(reset: { _, _ in ResetProbe.count += 1 })
    private var dragOffset: CGSize = .zero
    @State private var resetsSeen: Int = 0

    var body: some View {
        VStack(spacing: 16) {
            Text("resets \(resetsSeen)")
                .accessibilityIdentifier("trickyResetsLabel")
            RoundedRectangle(cornerRadius: 16)
                .fill(.orange)
                .frame(width: 100, height: 100)
                .offset(dragOffset)
                .gesture(
                    DragGesture().updating($dragOffset) { value, state, _ in
                        state = value.translation
                    }
                )
                .accessibilityIdentifier("trickyDragBox")
        }
        .onChange(of: dragOffset) { _, new in
            if new == .zero {
                resetsSeen = ResetProbe.count
            }
        }
    }
}

// Core component under test, with mutation-snapshot logging: `resetsSeen`
// is written exactly once per completed drag (deterministically `1` in a
// fresh process), so the model's history is snapshot-stable.
struct TrickyDragCardScenario: View {
    @State private var model = TrickyDragCard.CoreModel()

    var body: some View {
        TrickyDragCard.Core.make(model: model)
            .loggingMutations(of: model.history)
    }
}
