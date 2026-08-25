import CoreFlow
import SwiftData
import SwiftUI

struct QueryViewInsertScenario: View {
    var body: some View {
        QueryView(query: Query(sort: \Novel.title)) { $novels in
            List {
                Button("insert") {
                    $novels.modelContext.insert(Novel(title: "Dune", genre: "Sci-Fi"))
                }
                ForEach(novels) { Text($0.title) }
            }
        }
        .modelContainer(for: Novel.self, inMemory: true)
    }
}

#Preview {
    QueryViewInsertScenario()
}
