#if canImport(SwiftData)
    import SwiftData
    import SwiftUI

    /// Drop-in stand-in for SwiftData's `@Query` on a `Core`. Read-surface
    /// parity with the live wrapper — verified directly against the
    /// `_SwiftData_SwiftUI` interface: `wrappedValue`, `fetchError`, and
    /// `modelContext`, **no `projectedValue`** — so the host's copied `body`
    /// text (`x.isEmpty`, `ForEach(x)`) compiles on `Core` unchanged; a bare
    /// `(wrappedValue:, fetchError:)` tuple field would force `.wrappedValue`
    /// onto every copied read. `_x.fetchError` spells the same on both sides
    /// (backing storage, reachable from same-file extensions).
    ///
    /// `modelContext` is the live wrapper's shape taken literally: an
    /// environment read (`DynamicProperty`, so it installs when `Core` is
    /// hosted — mock it via `.modelContainer`/`.environment`, the native
    /// story), private, not an init parameter, never read unhosted.
    /// `fetchError` defaults to `nil`, so `init(wrappedValue:)` is callable
    /// with the value alone — which makes the synthesized memberwise init for
    /// `@QueryCore var x: T` take the *bare* value (verified directly):
    /// `Core(items: [item], title: "t")`, no `QueryCore` spelling. To seed
    /// `fetchError`, assign the `_x` backing from a same-file extension init
    /// (see `QueryCoreTests`' `FakeCore`).
    @propertyWrapper
    public struct QueryCore<Value>: DynamicProperty {
        @Environment(\.modelContext) private var modelContext
        public let wrappedValue: Value
        public let fetchError: (any Error)?

        public init(
            wrappedValue: Value,
            fetchError: (any Error)? = nil
        ) {
            self.wrappedValue = wrappedValue
            self.fetchError = fetchError
        }
    }
#endif
