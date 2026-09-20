import CoreFlow
import SwiftData
import SwiftUI
import Testing

@Model
private final class Book {
    var title: String
    var genre: String
    init(title: String, genre: String) {
        self.title = title
        self.genre = genre
    }
}

/// The mock owns its throwaway in-memory container internally — no host.
@MainActor
struct SectionedResultsMockTests {
    @Test func sectionedMockIsAGenuineValue() {
        guard
            #available(macOS 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0,
                       macCatalyst 27.0, *)
        else { return }
        // Titles are the elements' own; sections and rows follow the sort.
        let dune = Book(title: "Dune", genre: "Sci-Fi")
        let sectioned = SectionedResults.mock(
            [dune, Book(title: "It", genre: "Horror"), Book(title: "Anathem", genre: "Sci-Fi")],
            sectionBy: \.genre,
            sortBy: [SortDescriptor(\.genre, order: .reverse), SortDescriptor(\.title)]
        )
        #expect(sectioned.sectionTitles == ["Sci-Fi", "Horror"])
        #expect(sectioned.first?.map(\.title) == ["Anathem", "Dune"])
        #expect(sectioned[sectionTitle: "Horror"]?.map(\.title) == ["It"])
        // The caller's instances come back, not copies.
        #expect(sectioned.first?.last === dune)
        // Seeds a QueryResult like any plain value — the sealed type as data.
        #expect(QueryResult(wrappedValue: sectioned).wrappedValue.count == 2)
    }
}
