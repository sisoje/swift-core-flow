import CoreFlow
import SwiftUI

// Live @GestureState verification: dragging must stream nonzero offsets
// (maxDistance grows, written through Core's @State→@Binding substitution)
// and snap back to zero on release (GestureState's own reset). See
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

// The component under test is the CORE, not the host: the scenario owns
// maxDistance and hands Core the generated logged binding; dragOffset is
// Core's own live @GestureState. Drag distances are device/timing-dependent,
// so this scenario is verified by behavior assertions, not snapshots — the
// $maxDistance writes still flow through \.testLog, which defaults to a no-op.
struct DragCardScenario: View {
    @TestState var maxDistance: CGFloat = 0

    var body: some View {
        DragCard.Core(maxDistance: $maxDistance)
    }
}
