import SwiftData
import SwiftUI

protocol QueryTransforming {
    @MainActor func toResult<E: PersistentModel, R>(_ q: Query<E, R>) -> QueryResult<R>
}

struct DefaultQueryTransform: QueryTransforming {
    func toResult<R>(_ q: Query<some PersistentModel, R>) -> QueryResult<R> {
        QueryResult(
            wrappedValue: q.wrappedValue,
            fetchError: q.fetchError,
            givenModelContext: q.modelContext
        )
    }
}

/// The canned test transform: a per-result-type registry, so ONE value
/// serves a subtree with queries over any mix of model types, fully typed
/// at the registration site. A registry hit is returned; an unregistered
/// shape still succeeds with the empty result of the shape the query
/// declared, so a mocked subtree renders whatever it wasn't seeded for.
struct MockQueryTransform: QueryTransforming {
    var resmap: [ObjectIdentifier: Any]

    init(resmap: [ObjectIdentifier: Any] = [:]) {
        self.resmap = resmap
    }

    init<each R>(_ results: repeat QueryResult<each R>) {
        resmap = [:]
        repeat insert(each results)
    }

    mutating func insert<R>(_ result: QueryResult<R>) {
        resmap[ObjectIdentifier(R.self)] = result
    }

    func toResult<E: PersistentModel, R>(_: Query<E, R>) -> QueryResult<R> {
        if let result = resmap[ObjectIdentifier(R.self)] as? QueryResult<R> {
            return result
        }
        // `Query`'s initializers fix `Result` to exactly these two shapes.
        if let empty = [E]() as? R {
            return QueryResult(wrappedValue: empty)
        }
        if #available(iOS 27.0, macOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, macCatalyst 27.0, *),
           let empty = SectionedResults<E, String>.mock([]) as? R
        {
            return QueryResult(wrappedValue: empty)
        }
        fatalError("MockQueryTransform: no mock registered and no empty result for \(R.self)")
    }
}

extension EnvironmentValues {
    @Entry var queryTransform: QueryTransforming = DefaultQueryTransform()
}

public extension View {
    func mockQuery<each R>(_ results: repeat QueryResult<each R>) -> some View {
        environment(\.queryTransform, MockQueryTransform(repeat each results))
    }
}

/// Storing the property in a view is what makes SwiftUI install it when it is
/// a `DynamicProperty` (`Query` here) — passed straight into a closure it would
/// never update.
struct PropertyHostView<Property, Content: View>: View {
    let property: Property
    @ViewBuilder let content: (Property) -> Content

    var body: some View {
        content(property)
    }
}

/// A value memoized by dependencies: `value(for:build:)` runs `build` only when
/// they differ from the last ones. A plain class meant to live in `@State` — a
/// render-phase write to a plain object, no SwiftUI state write. `QueryView`
/// keys the built `Query` by `dependencies`, so unchanged ones never run the
/// autoclosure — our decision, not `.equatable()`'s (whose skipping a beta can
/// flip); handing the same `Query` value to `PropertyHostView` each render is
/// what any view holding a `@Query` does, so the installed property keeps
/// updating.
final class Memo<Value> {
    private var dependencies: [any Equatable] = []
    private var value: Value?

    func value(for dependencies: [any Equatable], build: () -> Value) -> Value {
        if let value, Self.isSame(dependencies, self.dependencies) {
            return value
        }
        self.dependencies = dependencies
        let built = build()
        value = built
        return built
    }

    /// Pairwise equality; two values of different types are different.
    private static func isSame(_ lhs: [any Equatable], _ rhs: [any Equatable]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (element, other) in zip(lhs, rhs) where !isSame(element, other) {
            return false
        }
        return true
    }

    private static func isSame<Element: Equatable>(_ element: Element, _ other: Any) -> Bool {
        (other as? Element) == element
    }
}

public struct QueryView<Element: PersistentModel, Result, Content: View>: View {
    /// `dependencies` are the values that take part in the `Query` init, those
    /// and only those; a value left out is a change the memoized query will
    /// not follow. `content` is not gated and reads whatever state it wants.
    public init(
        query: @autoclosure @escaping () -> Query<Element, Result>,
        dependencies: [any Equatable] = [],
        @ViewBuilder content: @escaping (QueryResult<Result>) -> Content
    ) {
        self.dependencies = dependencies
        self.query = query
        self.content = content
    }

    @Environment(\.queryTransform) private var queryTransform
    @State private var memo = Memo<Query<Element, Result>>()
    let dependencies: [any Equatable]
    let query: () -> Query<Element, Result>
    let content: (QueryResult<Result>) -> Content

    public var body: some View {
        PropertyHostView(property: memo.value(for: dependencies, build: query)) {
            content(queryTransform.toResult($0))
        }
    }
}
