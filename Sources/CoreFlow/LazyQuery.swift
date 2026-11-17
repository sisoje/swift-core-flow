import SwiftData
import SwiftUI

/// A query not built yet, with the values it is built from, or a result
/// with no query behind it. It cannot be opened, and the query cannot be made
/// by hand: it comes only from calling a member that `LazyQuery.query` made,
/// with that member's arguments. Either one goes only into `QueryView`.
public struct LazyQuery<Element: PersistentModel, Result> {
    enum Source {
        case query(dependencies: [any Equatable], query: @MainActor () -> Query<Element, Result>)
        case result(QueryResult<Result>)
    }

    let source: Source

    /// Makes a member of a query service out of a query expression. Whoever
    /// calls the member with its arguments gets the `LazyQuery` back, and the
    /// arguments are its dependencies: there is no list to write and none to
    /// get wrong. An argument that is not `Equatable` and `Sendable` does not
    /// compile. The expression is `@MainActor`, since it builds a `Query`,
    /// and what comes back is not, so a service is made in any context.
    public static func query<each Argument: Equatable & Sendable>(
        _ query: @escaping @MainActor (repeat each Argument) -> Query<Element, Result>
    ) -> (repeat each Argument) -> LazyQuery {
        { (argument: repeat each Argument) in
            var dependencies: [any Equatable] = []
            repeat dependencies.append(each argument)
            return LazyQuery(source: .query(dependencies: dependencies) { query(repeat each argument) })
        }
    }

    /// The result itself: `QueryView` hands it to content and builds no `Query`.
    public static func result(_ result: QueryResult<Result>) -> LazyQuery {
        LazyQuery(source: .result(result))
    }
}

/// The initializer of a query service and its default value. Every stored
/// property is a query, a function answering `LazyQuery`. The initializer
/// takes each one as its query expression, a function of the same arguments
/// returning the `Query`, and makes it lazy with `LazyQuery.query`:
///
/// ```swift
/// @LazyQueries
/// struct BookQueries {
///     var sorted: (_ byAuthor: Bool, _ descending: Bool) -> LazyQuery<Book, [Book]>
///     // generates:
///     // init(
///     //     sorted: @escaping @MainActor (_ byAuthor: Bool, _ descending: Bool) -> Query<Book, [Book]>
///     // ) {
///     //     self.sorted = LazyQuery.query(sorted)
///     // }
///     //
///     // static var defaultQueries: Self {
///     //     Self(
///     //         sorted: { _, _ in
///     //             Query()
///     //         }
///     //     )
///     // }
/// }
///
/// // defined with plain query expressions, asked with arguments:
/// // BookQueries(sorted: { byAuthor, descending in Query(sort: …) })
/// // QueryView(queries.sorted(sortByAuthor, descending)) { $books in … }
/// ```
///
/// So a query is written once in the contract, as the member, and the
/// initializer cannot hand one member another member's query.
///
/// - `defaultQueries` answers the default query, every element, unsorted,
///   whatever a member is asked with. It is what an environment entry
///   defaults to, in a module of any default isolation: a query expression
///   is typed `@MainActor`, so the closure that builds the `Query` is
///   isolated and the service that holds it is not. It is written only
///   when every query answers an array, spelled `[Element]`: a sectioned
///   query has to name its section, so a service holding one gets the
///   initializer alone.
/// - A member is a `var`, so a test or a scenario sets one alone to a result,
///   `queries.sorted = { _, _ in .result(QueryResult(wrappedValue: [dune])) }`,
///   and the others keep their queries.
/// - A stored property that is not a function type with no attributes whose
///   result is spelled `LazyQuery<…>` is a compile error (the macro is
///   syntax-only, and a query service holds nothing else).
/// - Both members have the type's own access level. They name `Query`, so
///   the file imports SwiftData and SwiftUI: `Query` is declared where the
///   two meet, and with either import missing the expansion reports `cannot
///   find type 'Query' in scope`.
@attached(member, names: named(init), named(defaultQueries))
public macro LazyQueries() =
    #externalMacro(
        module: "CoreFlowMacros",
        type: "LazyQueriesMacro"
    )
