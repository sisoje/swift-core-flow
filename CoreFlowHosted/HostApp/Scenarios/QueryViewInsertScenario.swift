import CoreFlow
import SwiftData
import SwiftUI

struct QueryViewInsertScenario: View {
    @TestState private var unrelated = 0

    var body: some View {
        VStack {
            Button("unrelated") { unrelated += 1 }
            // Read in body, so each unrelated write re-renders this view and
            // hands the memoized query to `QueryView` again.
            Text(verbatim: "unrelated \(unrelated)")
            QueryView(query: Query(sort: \Novel.title)) { $novels in
                List {
                    Button("insert") {
                        _novels.modelContext.insert(Novel(title: "Novel \(novels.count + 1)", genre: "Sci-Fi"))
                    }
                    ForEach(novels) { Text($0.title) }
                }
            }
        }
        .modelContainer(for: Novel.self, inMemory: true)
    }
}

#Preview {
    QueryViewInsertScenario()
}
