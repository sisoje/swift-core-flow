import SwiftUI
import ValueFlow

/// Observable side effect for the tricky init below: the host's custom
/// `reset:` closure bumps this counter every time SwiftUI resets the gesture
/// state — so a UI test can assert whether the closure actually fired.
enum ResetProbe {
    nonisolated(unsafe) static var count = 0
}

// The tricky init: an argument-carrying @GestureState —
// `@GestureState(reset:)` is one of the wrapper's real inits, alongside
// (wrappedValue:resetTransaction:) and the initialValue spellings. The
// developer's reset behavior lives in those arguments. @Shell currently
// mirrors only the attribute NAME onto Core, silently dropping the arguments
// — so the closure below never runs when the drag ends, and the UI test
// asserting "resets 1" fails. It goes green only when the macro carries the
// full attribute onto Core.
@Flowable
@Shell
struct TrickyDragCard: View {
    @GestureState(reset: { _, _ in ResetProbe.count += 1 })
    private var dragOffset: CGSize = .zero
    @State private var resetsSeen: Int = 0
}

extension TrickyDragCard.Core {
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
