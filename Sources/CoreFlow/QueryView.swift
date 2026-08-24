import SwiftData
import SwiftUI

protocol QueryTransforming {
    @MainActor func toCore<E: PersistentModel, R>(_ q: Query<E, R>) -> QueryResult<R>
}

struct DefaultQueryTransform: QueryTransforming {
    func toCore<R>(_ q: Query<some PersistentModel, R>) -> QueryResult<R> {
        QueryResult(
            wrappedValue: q.wrappedValue,
            fetchError: q.fetchError,
            givenModelContext: q.modelContext
        )
    }
}

/// The canned test transform: a per-result-type registry, so ONE value
/// serves a subtree with queries over any mix of model types, fully typed
/// at the registration site. No logic: a registry hit is returned, an
/// unregistered shape traps loudly.
struct MockQueryTransform: QueryTransforming {
    var resmap: [ObjectIdentifier: Any]

    init(resmap: [ObjectIdentifier: Any] = [:]) {
        self.resmap = resmap
    }

    init<each R>(_ cores: repeat QueryResult<each R>) {
        resmap = [:]
        repeat insert(each cores)
    }

    mutating func insert<R>(_ core: QueryResult<R>) {
        resmap[ObjectIdentifier(R.self)] = core
    }

    func toCore<E: PersistentModel, R>(_: Query<E, R>) -> QueryResult<R> {
        guard let core = resmap[ObjectIdentifier(R.self)] as? QueryResult<R> else {
            fatalError("MockQueryTransform: no mock registered for \(R.self)")
        }
        return core
    }
}

extension EnvironmentValues {
    @Entry var queryTransform: QueryTransforming = DefaultQueryTransform()
}

public extension View {
    func mockQuery<each R>(_ cores: repeat QueryResult<each R>) -> some View {
        environment(\.queryTransform, MockQueryTransform(repeat each cores))
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

/// Equality ignores `content`, so under `.equatable()` an unchanged index skips
/// body re-evaluation entirely — captured state in `content` stays frozen until
/// the index changes.
struct EquatableByParameterView<Index: Equatable, Content: View>: View, @MainActor Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.index == rhs.index
    }

    let index: Index
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
    }
}

public struct QueryView<Index: Equatable, Element: PersistentModel, Result, Content: View>: View {
    /// `index` must cover every input of BOTH `query` and `content`; a value
    /// left out is a state change the gated body will not see.
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

    @Environment(\.queryTransform) private var queryTransform
    // nil means ungated: the Index == Never init cannot supply a value.
    var index: Index?
    let query: () -> Query<Element, Result>
    let content: (QueryResult<Result>) -> Content

    public var body: some View {
        if let index {
            EquatableByParameterView(index: index) {
                PropertyHostView(property: query()) {
                    content(queryTransform.toCore($0))
                }
            }
            .equatable()
        } else {
            PropertyHostView(property: query()) {
                content(queryTransform.toCore($0))
            }
        }
    }
}

struct QueryViewScenario: View {
    @Model
    final class PreviewBook {
        var title: String
        init(title: String) {
            self.title = title
        }
    }

    @State private var sortDescending = false

    var body: some View {
        VStack {
            Toggle("Sort Z–A", isOn: $sortDescending)
                .padding(.horizontal)
            QueryView(
                index: sortDescending,
                query: Query(sort: \PreviewBook.title, order: sortDescending ? .reverse : .forward)
            ) { $books in
                List(books) { book in
                    Text(book.title)
                }
            }
        }
        // Mocking IS a seeded in-memory container: the real query runs, so
        // the sort is genuinely the query's own.
        .modelContainer(for: PreviewBook.self, inMemory: true) { result in
            let context = try! result.get().mainContext
            context.insert(PreviewBook(title: "Dune"))
            context.insert(PreviewBook(title: "Anathem"))
        }
    }
}

#Preview {
    QueryViewScenario()
}
