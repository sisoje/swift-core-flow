import SwiftUI
import ValueFlow

// The live-drag verification view: @GestureState declared on the host,
// mirrored by @Shell onto Core as a real `@GestureState var`, gesture wired in
// Core's hand-written body. A drag must stream nonzero offsets (maxDistance
// grows — also live-verifying @State→@Binding write-through from Core) and
// snap back to zero when it ends (GestureState's own reset). See
// UITests/DragCardUITests.swift.
@Flowable
@Shell
struct DragCard: View {
    @GestureState private var dragOffset: CGSize = .zero
    @State private var maxDistance: CGFloat = 0
}

extension DragCard.Core {
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
