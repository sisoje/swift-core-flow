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
