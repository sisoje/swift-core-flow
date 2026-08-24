import SwiftData
import SwiftUI

/// Drop-in stand-in for SwiftData's `@Query` on a `Core`. Read-surface
/// parity with the live wrapper — verified directly against the
/// `_SwiftData_SwiftUI` interface, its instance surface is exactly
/// `wrappedValue`, `fetchError`, and `modelContext` — so the host's copied
/// `body` text (`x.isEmpty`, `ForEach(x)`) compiles on `Core` unchanged; a
/// bare `(wrappedValue:, fetchError:)` tuple field would force
/// `.wrappedValue` onto every copied read. `_x.fetchError` spells the same
/// on both sides (backing storage, reachable from same-file extensions).
///
/// The live wrapper has **no `projectedValue`**; ours is a deliberate
/// superset (copied bodies never spell `$x`, so parity holds): projecting
/// `self` with `init(projectedValue:)` is what lets an SE-0293 `$` closure
/// parameter re-propertify the value — `QueryView { $books in
/// ForEach(books) … } `, `@Query` ergonomics without the wrapper.
///
/// `modelContext` resolves seeded-then-environment
/// (`givenModelContext ?? defaultModelContext`): a live transform seeds
/// the real query's context; otherwise the private
/// `@Environment(\.modelContext)` read answers (`DynamicProperty`, so it
/// installs when `Core` is hosted — mock it via
/// `.modelContainer`/`.environment`, the native story; unseeded it is
/// never read unhosted).
/// `fetchError` defaults to `nil`, so `init(wrappedValue:)` is callable
/// with the value alone — which makes the synthesized memberwise init for
/// `@QueryResult var x: T` take the *bare* value (verified directly):
/// `Core(items: [item], title: "t")`, no `QueryResult` spelling. To seed
/// `fetchError`, assign the `_x` backing from a same-file extension init
/// (see `QueryResultTests`' `FakeCore`).
@propertyWrapper
public struct QueryResult<Value>: DynamicProperty {
    @Environment(\.modelContext) private var defaultModelContext
    public let wrappedValue: Value
    public let fetchError: (any Error)?
    private let givenModelContext: ModelContext?
    public var modelContext: ModelContext {
        givenModelContext ?? defaultModelContext
    }

    public var projectedValue: QueryResult<Value> {
        self
    }

    public init(
        wrappedValue: Value,
        fetchError: (any Error)? = nil,
        givenModelContext: ModelContext? = nil
    ) {
        self.wrappedValue = wrappedValue
        self.fetchError = fetchError
        self.givenModelContext = givenModelContext
    }

    public init(projectedValue: QueryResult<Value>) {
        self = projectedValue
    }
}
