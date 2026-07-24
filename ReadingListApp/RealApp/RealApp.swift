import ReadingListUI
import SwiftData
import SwiftUI

// The REAL app: normal import, public hosts running their own live wrappers —
// @Query fetches from the real container, @AppStorage persists the sort.
// The closures are where data flow leaves the components: inserting and
// deleting are this app's business, done on the real ModelContext.
@main
struct ReadingListApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Book.self)
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack {
            AddBookField(onSubmit: { title in
                context.insert(Book(title: title, author: "Unknown"))
            })
            BookList(onDelete: { title in
                try? context.delete(model: Book.self, where: #Predicate { $0.title == title })
            })
        }
    }
}
