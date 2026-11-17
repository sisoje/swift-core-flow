import CoreFlow
import SwiftData
import SwiftUI

/// A query asked from a service: `sortedBooks(sortDescending)` is called on every
/// render and answers a `LazyQuery`. Logs each `query` construction and each
/// state write, in order.
struct LazyQueryScenario: View {
    @Model
    final class Book {
        var title: String
        init(title: String) {
            self.title = title
        }
    }

    @TestState private var sortDescending = false
    @TestState private var unrelated = 0
    @TestLog private var log

    var body: some View {
        // The service member, the way a store sets one: a query expression
        // made lazy. Nothing here or below lists a dependency.
        let sortedBooks = QueryUtilities.lazyQuery { (descending: Bool) -> Query<Book, [Book]> in
            let order: SortOrder = descending ? .reverse : .forward
            log("query", "\(order)")
            return Query(sort: \Book.title, order: order)
        }
        VStack {
            Button("unrelated") { unrelated += 1 }
            // Read in body, so each unrelated write re-renders this view.
            Text(verbatim: "\(unrelated)")
            Button("sort") { sortDescending.toggle() }
            QueryView(sortedBooks(sortDescending)) { $books in
                List(books) { Text($0.title) }
            }
        }
        .modelContainer(for: Book.self, inMemory: true) { result in
            let context = try! result.get().mainContext
            context.insert(Book(title: "Dune"))
            context.insert(Book(title: "Anathem"))
        }
    }
}

#Preview {
    LazyQueryScenario()
}
