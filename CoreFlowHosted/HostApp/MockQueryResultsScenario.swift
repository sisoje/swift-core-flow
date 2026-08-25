import CoreFlow
import SwiftData
import SwiftUI

struct TagsUnavailable: Error {}

/// No container anywhere: one canned result, one canned fetch error.
struct MockQueryResultsScenario: View {
    var body: some View {
        VStack {
            QueryView(query: Query(sort: \Novel.title)) { $novels in
                List(novels) { Text($0.title) }
            }
            QueryView(query: Query(sort: \Tag.name)) { $tags in
                if let error = $tags.fetchError {
                    Text(verbatim: "\(error)")
                }
            }
        }
        .mockQuery(
            QueryResult(wrappedValue: [Novel(title: "Dune", genre: "Sci-Fi")]),
            QueryResult<[Tag]>(wrappedValue: [], fetchError: TagsUnavailable())
        )
    }
}

#Preview {
    MockQueryResultsScenario()
}
