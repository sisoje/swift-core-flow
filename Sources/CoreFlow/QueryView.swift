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

public struct QueryView<Index: Equatable, Element: PersistentModel, Result, Content: View>: View {
    /// `index` is the query's parameter set: it must cover every input of
    /// `query`; a value left out is a parameter change the memoized query will
    /// not follow. `content` is not gated and reads whatever state it wants.
    public init(
        index: Index,
        query: @autoclosure @escaping () -> Query<Element, Result>,
        @ViewBuilder content: @escaping (QueryResult<Result>) -> Content
    ) {
        self.index = index
        self.query = query
        self.content = content
    }

    public init(
        query: @autoclosure @escaping () -> Query<Element, Result>,
        @ViewBuilder content: @escaping (QueryResult<Result>) -> Content
    ) where Index == Never {
        self.query = query
        self.content = content
    }

    /// The gate: the built `Query` memoized by index, so an unchanged index
    /// never runs the autoclosure — our decision, not `.equatable()`'s (whose
    /// skipping a beta can flip). A plain class in `@State`: a render-phase
    /// write to a plain object, no SwiftUI state write. Handing the same
    /// `Query` value to `PropertyHostView` each render is what any view holding
    /// a `@Query` does, so the installed property keeps updating.
    private final class Memo {
        var index: Index?
        var query: Query<Element, Result>?

        func query(for index: Index, build: () -> Query<Element, Result>) -> Query<Element, Result> {
            if let query, index == self.index {
                return query
            }
            self.index = index
            let built = build()
            query = built
            return built
        }
    }

    @Environment(\.queryTransform) private var queryTransform
    @State private var memo = Memo()
    // nil means ungated: the Index == Never init cannot supply a value, and
    // body skips the memo — the query is rebuilt every render.
    var index: Index?
    let query: () -> Query<Element, Result>
    let content: (QueryResult<Result>) -> Content

    public var body: some View {
        if let index {
            PropertyHostView(property: memo.query(for: index, build: query)) {
                content(queryTransform.toResult($0))
            }
        } else {
            PropertyHostView(property: query()) {
                content(queryTransform.toResult($0))
            }
        }
    }
}
