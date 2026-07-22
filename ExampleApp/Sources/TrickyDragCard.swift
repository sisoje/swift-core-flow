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

// Core component under test, mutations logged at the write site: the
// didSet-wrapped binding reports `resetsSeen` the moment Core's copied body
// writes it — exactly once per completed drag (deterministically `1` in a
// fresh process), so the snapshot is stable.
struct TrickyDragCardScenario: View {
    @Environment(\.mylog) var mylog
    @State private var resetsSeen = 0

    var body: some View {
        TrickyDragCard.Core(
            resetsSeen: $resetsSeen.didSet { val in
                mylog.mylog("resetsSeen", val)
            })
    }
}
