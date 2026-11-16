import SwiftData
import SwiftUI

/// A query not built yet, with the values it is built from. It cannot be
/// opened or made by hand: it comes only from calling a member that
/// `QueryUtilities.lazy` made, with that member's arguments, and it goes only
/// into `QueryView`.
public struct LazyQuery<Element: PersistentModel, Result> {
    let dependencies: [any Equatable]
    let query: () -> Query<Element, Result>
}

public enum QueryUtilities {
    /// Makes a member of a query service out of a query expression. Whoever
    /// calls the member with its arguments gets the `LazyQuery` back, and the
    /// arguments are its dependencies: there is no list to write and none to
    /// get wrong. An argument that is not `Equatable` does not compile.
    public static func lazy<each Argument: Equatable, Element: PersistentModel, Result>(
        _ query: @escaping (repeat each Argument) -> Query<Element, Result>
    ) -> (repeat each Argument) -> LazyQuery<Element, Result> {
        { (argument: repeat each Argument) in
            var dependencies: [any Equatable] = []
            repeat dependencies.append(each argument)
            return LazyQuery(dependencies: dependencies) { query(repeat each argument) }
        }
    }
}

public extension QueryView {
    /// A `LazyQuery` carries both of the other initializer's arguments, so the
    /// query is built when a value it was asked with changes and at no other
    /// time.
    init(_ lazy: LazyQuery<Element, Result>, @ViewBuilder content: @escaping (QueryResult<Result>) -> Content) {
        self.init(query: lazy.query(), dependencies: lazy.dependencies, content: content)
    }
}

/// The initializer of a query service and its default value. Every stored
/// property is a query, a function answering `LazyQuery`. The initializer
/// takes each one as its query expression, a function of the same arguments
/// returning the `Query`, and makes it lazy with `QueryUtilities.lazy`:
///
/// ```swift
/// @LazyQueries
/// struct BookQueries {
///     let sorted: (_ byAuthor: Bool, _ descending: Bool) -> LazyQuery<Book, [Book]>
///     // generates:
///     // init(
///     //     sorted: @escaping (_ byAuthor: Bool, _ descending: Bool) -> Query<Book, [Book]>
///     // ) {
///     //     self.sorted = QueryUtilities.lazy(sorted)
///     // }
///     //
///     // @MainActor static var defaultQueries: Self {
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
///   whatever a member is asked with. It is `@MainActor`, since its closures
///   build a `Query`, and it is what an environment entry defaults to in a
///   module whose default isolation is the main actor. It is written only
///   when every query answers an array, spelled `[Element]`: a sectioned
///   query has to name its section, so a service holding one gets the
///   initializer alone.
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
