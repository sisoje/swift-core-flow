import SwiftData
import SwiftUI

/// Storing the property in a view is what makes SwiftUI install it when it is
/// a `DynamicProperty` — passed straight into a closure it would never update.
/// A `Query` is one, and so is a `QueryResult`, whose `modelContext` reads
/// the environment.
struct PropertyHostView<Property, Content: View>: View {
    let property: Property
    @ViewBuilder let content: (Property) -> Content

    var body: some View {
        content(property)
    }
}

public struct QueryView<Element: PersistentModel, Result, Content: View>: View {
    /// A query from the store is built when a value it was asked with changes
    /// and at no other time. A result is handed to `content` as it is, and no
    /// `Query` is built. `content` is not gated and reads whatever state it
    /// wants.
    public init(_ query: LazyQuery<Element, Result>, @ViewBuilder content: @escaping (QueryResult<Result>) -> Content) {
        self.query = query
        self.content = content
    }

    let query: LazyQuery<Element, Result>
    let content: (QueryResult<Result>) -> Content

    public var body: some View {
        switch query.source {
        case let .query(dependencies, query):
            MemoView(query(), dependencies: dependencies) { builtQuery in
                PropertyHostView(property: builtQuery) {
                    content(
                        QueryResult(
                            wrappedValue: $0.wrappedValue,
                            fetchError: $0.fetchError,
                            givenModelContext: $0.modelContext
                        )
                    )
                }
            }
        case let .result(result):
            PropertyHostView(property: result, content: content)
        }
    }
}
