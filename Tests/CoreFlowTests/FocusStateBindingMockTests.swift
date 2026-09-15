import CoreFlow
import SwiftUI
import Testing

@MainActor
struct FocusStateBindingMockTests {
    @Test func readsAndWritesThroughTheBackingBinding() {
        var backing = false
        let focus = FocusState<Bool>.Binding.mock(
            Binding(get: { backing }, set: { backing = $0 })
        )
        #expect(focus.wrappedValue == false)
        focus.wrappedValue = true
        #expect(backing == true)
        #expect(focus.wrappedValue == true)
    }
}
