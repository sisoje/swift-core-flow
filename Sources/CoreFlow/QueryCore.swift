#if canImport(SwiftData)
    import SwiftData

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
    /// The init deliberately has no defaults: a wrapper init callable with
    /// `wrappedValue` alone would make Swift's synthesized memberwise init take
    /// the bare value and drop `fetchError`/`modelContext` — with all three
    /// required, the synthesized init takes the wrapper *type* itself
    /// (`x: QueryCore<T>`), the same mechanism `@Binding`'s fields already rely
    /// on (verified directly).
    @propertyWrapper
    public struct QueryCore<Value> {
        public let wrappedValue: Value
        public let fetchError: (any Error)?
        public let modelContext: ModelContext

        public init(wrappedValue: Value, fetchError: (any Error)?, modelContext: ModelContext) {
            self.wrappedValue = wrappedValue
            self.fetchError = fetchError
            self.modelContext = modelContext
        }
    }
#endif
