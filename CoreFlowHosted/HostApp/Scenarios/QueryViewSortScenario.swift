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
        // The query expression made lazy, in place: once as a function of the
        // value it depends on, once capturing that value.
        let sorted = LazyQuery.query { (descending: Bool) in build(descending) }
        let captured = LazyQuery.query { build(sortDescending) }
        VStack {
            Button("unrelated") { unrelated += 1 }
            // Read in body, so each unrelated write re-renders this view.
            Text(verbatim: "\(unrelated)")
            Button("sort") { sortDescending.toggle() }
            // Content must render something: SwiftUI never evaluates a gated
            // subtree whose content is `EmptyView`, so the query is never
            // even constructed.
            if gated {
                // Asked with the value, so the value is the dependency.
                QueryView(sorted(sortDescending)) { $books in
                    List(books) { Text($0.title) }
                }
            } else {
                // The expression captures the value and takes no argument:
                // no dependencies, so the query is built once and kept — it
                // does not follow the sort write.
                QueryView(captured()) { $books in
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

    private func build(_ descending: Bool) -> Query<Book, [Book]> {
        let order: SortOrder = descending ? .reverse : .forward
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
