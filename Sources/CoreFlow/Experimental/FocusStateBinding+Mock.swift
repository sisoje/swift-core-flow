import SwiftUI

public extension FocusState.Binding {
    /// Fabricates the init-less `FocusState<Value>.Binding` over a plain
    /// binding. The type is `@frozen` with exactly one stored field,
    /// `_binding: SwiftUI.Binding<Value>` (the 27.0 swiftinterface), so the
    /// bit cast is layout-guaranteed by ABI. UNHOSTED use only: it lets a
    /// test construct a `Core` whose child field is the nominal type and
    /// observe the child's programmatic writes through the backing binding.
    /// Hosted, `.focused` ignores it — probed on the 27.0 simulator: a system
    /// tap never calls the setter, and a write through it moves no focus.
    static func mock(_ binding: SwiftUI.Binding<Value>) -> Self {
        precondition(MemoryLayout<Self>.size == MemoryLayout<SwiftUI.Binding<Value>>.size)
        return unsafeBitCast(binding, to: Self.self)
    }
}
