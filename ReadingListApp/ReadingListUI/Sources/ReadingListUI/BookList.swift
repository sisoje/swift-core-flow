import CoreFlow
import SwiftData
import SwiftUI

// The SwiftData screen: @Query → @QueryCore on Core, so a scenario hands the
// fetched array in directly — no ModelContainer anywhere in the tests — and
// @AppStorage → @Binding, the whitelist's second row. Deleting is the
// caller's business, passed in as an action.
@Flowable
@Shell
public struct BookList: View {
    @Query private var books: [Book]
    @AppStorage("sortByAuthor") private var sortByAuthor: Bool = false
    let onDelete: (String) -> Void

    public var body: some View {
        VStack {
            Toggle("Sort by author", isOn: $sortByAuthor)
                .padding(.horizontal)
                .accessibilityIdentifier("sortToggle")
            List {
                let shown =
                    sortByAuthor
                    ? books.sorted { $0.author < $1.author }
                    : books.sorted { $0.title < $1.title }
                ForEach(shown) { book in
                    @Bindable var book = book
                    HStack {
                        BookRow.Core(
                            title: book.title, author: book.author, isFavorite: $book.isFavorite)
                        Button("Delete") {
                            onDelete(book.title)
                        }
                        .accessibilityIdentifier("delete-\(book.title)")
                    }
                }
            }
        }
    }
}

struct BookListScenario: View {
    @TestState var sortByAuthor = false
    @TestAction var onDelete: (String) -> Void = { _ in }

    var body: some View {
        BookList.Core(
            books: [
                Book(title: "Dune", author: "Herbert"),
                Book(title: "Anathem", author: "Stephenson"),
            ],
            sortByAuthor: $sortByAuthor,
            onDelete: onDelete)
    }
}

#Preview {
    BookListScenario()
}
