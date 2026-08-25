import CoreFlow
import SwiftData
import SwiftUI

/// Logs each `query` construction and each state write, in order.
struct QueryViewSortScenario: View {
    @Model
    final class Book {
        var title: String
        init(title: String) {
            self.title = title
        }
    }

    let gated: Bool
    @TestState private var sortDescending = false
    @TestState private var unrelated = 0
    @TestLog private var log

    var body: some View {
        VStack {
            Button("unrelated") { unrelated += 1 }
            // Read in body, so each unrelated write re-renders this view.
            Text(verbatim: "\(unrelated)")
            Button("sort") { sortDescending.toggle() }
            // Content must render something: SwiftUI never evaluates a gated
            // subtree whose content is `EmptyView`, so the query is never
            // even constructed.
            if gated {
                QueryView(index: sortDescending, query: build()) { $books in
                    List(books) { Text($0.title) }
                }
            } else {
                QueryView(query: build()) { $books in
                    List(books) { Text($0.title) }
                }
            }
        }
        .modelContainer(for: Book.self, inMemory: true) { result in
            let context = try! result.get().mainContext
            context.insert(Book(title: "Dune"))
            context.insert(Book(title: "Anathem"))
        }
    }

    private func build() -> Query<Book, [Book]> {
        let order: SortOrder = sortDescending ? .reverse : .forward
        log("query", "\(order)")
        return Query(sort: \Book.title, order: order)
    }
}

#Preview("Gated") {
    QueryViewSortScenario(gated: true)
}

#Preview("Ungated") {
    QueryViewSortScenario(gated: false)
}
