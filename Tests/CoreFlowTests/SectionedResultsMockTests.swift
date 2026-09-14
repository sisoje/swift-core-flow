import CoreFlow
import SwiftData
import SwiftUI
import Testing

@Model
private final class Book {
    var title: String
    init(title: String) {
        self.title = title
    }
}

/// The mock owns its throwaway in-memory container internally — no host.
@MainActor
struct SectionedResultsMockTests {
    #if canImport(SwiftData, _version: 180)
        @Test func sectionedMockFabricatesPlainData() {
            guard
                #available(macOS 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0,
                           macCatalyst 27.0, *)
            else { return }
            // Deliberately unsorted: order must be the caller's, not a sort's.
            let sectioned = SectionedResults<Book, String>.mock([
                (title: "Sci-Fi", elements: [Book(title: "Dune"), Book(title: "Anathem")]),
                (title: "Horror", elements: [Book(title: "It")]),
            ])
            #expect(sectioned.sectionTitles == ["Sci-Fi", "Horror"])
            #expect(sectioned.first?.map(\.title) == ["Dune", "Anathem"])
            #expect(sectioned[sectionTitle: "Horror"]?.map(\.title) == ["It"])
            // Seeds a QueryResult like any plain value — the sealed type as data.
            #expect(QueryResult(wrappedValue: sectioned).wrappedValue.count == 2)
        }
    #endif
}
