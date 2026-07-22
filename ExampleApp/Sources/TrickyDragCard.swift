import SwiftUI
import CoreFlow

/// Observable side effect for the tricky init below: the host's custom
/// `reset:` closure bumps this counter every time SwiftUI resets the gesture
/// state — so a UI test can assert whether the closure actually fired.
enum ResetProbe {
    nonisolated(unsafe) static var count = 0
}

// The tricky init: an argument-carrying @GestureState —
// `@GestureState(reset:)` is one of the wrapper's real inits, alongside
// (wrappedValue:resetTransaction:) and the initialValue spellings. The
// developer's reset behavior lives in those arguments. This test drove
// @Shell's verbatim-copy design for this field: an earlier revision
// reconstructed a fresh `@GestureState var` on Core from just the bare
// wrapper name, silently swapping this closure for the default reset (the
// test was red). @Shell now copies the whole declaration onto Core
// byte-for-byte — attribute arguments included — so the closure comes along
// with nothing to reconstruct, and the test is green.
@Shell
struct TrickyDragCard: View {
    @GestureState(reset: { _, _ in ResetProbe.count += 1 })
    private var dragOffset: CGSize = .zero
    @State private var resetsSeen: Int = 0
    var coma = 0

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
