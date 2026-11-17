import CoreFlow
import SwiftData
import SwiftUI

struct TagsUnavailable: Error {}

/// What the shelves ask the store for. Two of the queries answer the same
/// result type.
@LazyQueries
struct ShelfQueries {
    var sciFi: () -> LazyQuery<Novel, [Novel]>
    var horror: () -> LazyQuery<Novel, [Novel]>
    var tags: () -> LazyQuery<Tag, [Tag]>
}

extension EnvironmentValues {
    @Entry var shelfQueries = ShelfQueries.defaultQueries
}

struct Shelves: View {
    @Environment(\.shelfQueries) private var queries

    var body: some View {
        VStack {
            QueryView(queries.sciFi()) { $novels in
                Text(verbatim: "sciFi \(novels.map(\.title).joined(separator: ", "))")
            }
            QueryView(queries.horror()) { $novels in
                Text(verbatim: "horror \(novels.map(\.title).joined(separator: ", "))")
            }
            // swiftformat:disable:next unusedArguments — `_tags` IS a use
            QueryView(queries.tags()) { $tags in
                if let error = _tags.fetchError {
                    Text(verbatim: "\(error)")
                }
            }
        }
    }
}

/// No container anywhere: each query the shelves ask is set to a result by
/// name, two results of one type and one fetch error.
struct MockQueryResultsScenario: View {
    let dune = Novel(title: "Dune", genre: "Sci-Fi")
    let it = Novel(title: "It", genre: "Horror")

    var body: some View {
        Shelves()
            .environment(\.shelfQueries.sciFi) { .result(QueryResult(wrappedValue: [dune])) }
            .environment(\.shelfQueries.horror) { .result(QueryResult(wrappedValue: [it])) }
            .environment(\.shelfQueries.tags) { .result(QueryResult(wrappedValue: [], fetchError: TagsUnavailable())) }
    }
}

#Preview {
    MockQueryResultsScenario()
}
