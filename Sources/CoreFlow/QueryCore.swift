#if canImport(SwiftData)
    import SwiftData
    import SwiftUI

    /// Drop-in stand-in for SwiftData's `@Query` on a `Core` snapshot. One-to-one
    /// with the real wrapper's own instance surface — verified directly against
    /// the `_SwiftData_SwiftUI` interface: `Query<Element, Result>` exposes
    /// exactly `wrappedValue`, `fetchError`, and `modelContext`, and **no
    /// `projectedValue`** — so this carries the same three, nothing else, and no
    /// `$x` projection either.
    ///
    /// `@Shell` declares every `@Query` field on `Core` as `@QueryCore var x: T`,
    /// so `core.x` reads the fetched value directly — body code written against
    /// the live `@Query` property moves onto `Core` unchanged, and `_x.fetchError`
    /// /`_x.modelContext` keep working the same way they do on the live wrapper
    /// (via the backing storage, reachable from same-file extensions).
    ///
    /// Both extra fields default — `fetchError` to `nil`, `modelContext` to the
    /// environment's own default context (`Environment(\.modelContext)
    /// .wrappedValue`, evaluated outside any live view — verified directly, a
    /// real context, no trap) — since a test mocking a fetched result almost
    /// never cares about either: `QueryCore(wrappedValue: [item])` just works.
    ///
    /// Because `init(wrappedValue:)` is thereby callable with the wrapped value
    /// alone, Swift's synthesized memberwise init for `@QueryCore var x: T`
    /// takes the *bare* value (`x: T`), not the wrapper type — verified
    /// directly — which is exactly the ergonomic point: a test writes
    /// `Core(items: [item], title: "t")` with no `QueryCore` spelling at all.
    /// (`@Flowable`'s
    /// `outFlow` tuple still captures all three off the live wrapper.) To seed
    /// either field explicitly, construct the wrapper yourself at
    /// construction time — e.g. through a hand-written extension init that
    /// assigns the `_items` backing (see `QueryCoreTests`' `FakeCore`).
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
