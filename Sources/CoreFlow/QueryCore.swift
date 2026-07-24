#if canImport(SwiftData)
    import SwiftData
    import SwiftUI

    /// Drop-in stand-in for SwiftData's `@Query` on a `Core`. One-to-one with
    /// the live wrapper's instance surface — verified directly against the
    /// `_SwiftData_SwiftUI` interface: exactly `wrappedValue`, `fetchError`,
    /// and `modelContext`, **no `projectedValue`** — so the host's copied
    /// `body` text (`x.isEmpty`, `ForEach(x)`) compiles on `Core` unchanged;
    /// a bare `(wrappedValue:, fetchError:)` tuple field would force
    /// `.wrappedValue` onto every copied read. `_x.fetchError`/
    /// `_x.modelContext` spell the same on both sides (backing storage,
    /// reachable from same-file extensions).
    ///
    /// Both extra params default — `fetchError` to `nil`, `modelContext` to
    /// the environment's default context (evaluated outside any live view: a
    /// real context, no trap — verified directly) — so `init(wrappedValue:)`
    /// is callable with the value alone, which makes the synthesized
    /// memberwise init for `@QueryCore var x: T` take the *bare* value
    /// (verified directly): `Core(items: [item], title: "t")`, no `QueryCore`
    /// spelling. To seed the extras, assign the `_x` backing from a same-file
    /// extension init (see `QueryCoreTests`' `FakeCore`).
    @propertyWrapper
    public struct QueryCore<Value> {
        public let wrappedValue: Value
        public let fetchError: (any Error)?
        public let modelContext: ModelContext

        public init(
            wrappedValue: Value,
            fetchError: (any Error)? = nil,
            modelContext: ModelContext = Environment(\.modelContext).wrappedValue
        ) {
            self.wrappedValue = wrappedValue
            self.fetchError = fetchError
            self.modelContext = modelContext
        }
    }
#endif
