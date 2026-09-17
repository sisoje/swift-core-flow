import CoreFlow
import SwiftData
import SwiftUI

struct QueryViewInsertScenario: View {
    @TestState private var unrelated = 0
    @TestLog private var log

    var body: some View {
        VStack {
            Button("unrelated") { unrelated += 1 }
            // Read in body, so each unrelated write re-renders this view and
            // hands the memoized query to `QueryView` again.
            Text(verbatim: "unrelated \(unrelated)")
            QueryView(query: Query(sort: \Novel.title, animation: .default)) { $novels in
                List {
                    Button("insert") {
                        _novels.modelContext.insert(Novel(title: "Novel \(novels.count + 1)", genre: "Sci-Fi"))
                    }
                    ForEach(novels) { Text($0.title) }
                }
                // Logs when an update reaches the content carrying the
                // query's animation.
                .transaction { transaction in
                    let isAnimated = transaction.animation != nil
                    let count = novels.count
                    MainActor.assumeIsolated {
                        if isAnimated {
                            log("animated", "\(count)")
                        }
                    }
                }
            }
        }
        .modelContainer(for: Novel.self, inMemory: true)
    }
}

#Preview {
    QueryViewInsertScenario()
}
