import CoreFlow
import SwiftUI

// One row, one piece of view-owned state: the favorite star. @Shell maps the
// @State to @Binding on Core, so a scenario (or a list) mocks it per row —
// many independently-mocked Core instances of the same component.
@Shell
struct BookRow: View {
    let title: String
    let author: String
    @State private var isFavorite: Bool = false

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title)
                    .accessibilityIdentifier("bookTitle")
                Text(author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(isFavorite ? "★" : "☆") {
                isFavorite.toggle()
            }
            .accessibilityIdentifier("favoriteButton")
        }
        .padding(.horizontal)
    }
}

struct BookRowScenario: View {
    @TestState var isFavorite = false

    var body: some View {
        BookRow.Core(title: "Dune", author: "Herbert", isFavorite: $isFavorite)
    }
}

#Preview {
    BookRowScenario()
}
