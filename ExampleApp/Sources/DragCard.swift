import SwiftUI
import CoreFlow

// The live-drag verification view: @GestureState declared on the host,
// captured whole by @Shell into Core's @GestureStateCore. The body is
// written once, right here, as ordinary SwiftUI — @Shell copies it verbatim
// into Core, where the same identifiers resolve against the substituted
// fields ($dragOffset is a GestureState<CGSize> on both sides, maxDistance
// writes through Core's @Binding). A drag must stream nonzero offsets
// (maxDistance grows — also live-verifying @State→@Binding write-through)
// and snap back to zero when it ends (GestureState's own reset). See
// UITests/DragCardUITests.swift.
@Shell
struct DragCard: View {
    @GestureState private var dragOffset: CGSize = .zero
    @State private var maxDistance: CGFloat = 0

    var body: some View {
        VStack(spacing: 24) {
            Text("max \(Int(maxDistance))")
                .accessibilityIdentifier("maxLabel")
            Text("current \(Int(hypot(dragOffset.width, dragOffset.height)))")
                .accessibilityIdentifier("currentLabel")
            RoundedRectangle(cornerRadius: 16)
                .fill(.blue)
                .frame(width: 120, height: 120)
                .offset(dragOffset)
                .gesture(
                    DragGesture().updating($dragOffset) { value, state, _ in
                        state = value.translation
                    }
                )
                .accessibilityIdentifier("dragBox")
        }
        .onChange(of: dragOffset) { _, new in
            maxDistance = max(maxDistance, hypot(new.width, new.height))
        }
    }
}

// The host's body is hand-written source, so #Preview works on it directly —
// only macro-generated names are invisible inside #Preview.
#Preview {
    DragCard()
}

// Previewing the Core directly, frozen mid-drag: the seeded GestureState
// feeds @GestureStateCore, the .constant feeds the @Binding substituted for
// the host's @State. A PreviewProvider struct, not #Preview, on purpose:
// Swift forbids one macro expansion (#Preview) from resolving names generated
// by another (@Shell's `Core` and its macro-derived memberwise init) —
// verified directly, spelled inline, through a typealias, and via a helper
// func (only the func worked). PreviewProvider is pure ordinary code — no
// macro anywhere — so it constructs the Core inline with no bridge at all.
struct DragCardCoreMidDrag: PreviewProvider {
    static var previews: some View {
        DragCard.Core(
            dragOffset: GestureStateCore(GestureState(wrappedValue: CGSize(width: 60, height: 40))),
            maxDistance: .constant(123)
        )
    }
}
