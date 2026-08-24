@testable import CoreFlow
import SwiftData
import SwiftUI
import Testing

// Real, compiled usage of the QueryView surface — no live view anywhere in
// this file (the sectioned mock owns its throwaway in-memory container
// internally). Hosted behavior (installation, index gating, in-memory
// container mocking) is the example app's story.

@Model
private final class Track {
    var title: String
    init(title: String) {
        self.title = title
    }
}

@MainActor
struct QueryViewTests {
    @Test func sectionedMockFabricatesPlainData() {
        guard
            #available(macOS 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0,
                       macCatalyst 27.0, *)
        else { return }
        // Deliberately unsorted: order must be the caller's, not a sort's.
        let sectioned = SectionedResults<Track, String>.mock([
            (title: "Sci-Fi", elements: [Track(title: "Dune"), Track(title: "Anathem")]),
            (title: "Horror", elements: [Track(title: "It")]),
        ])
        #expect(sectioned.sectionTitles == ["Sci-Fi", "Horror"])
        #expect(sectioned.first?.map(\.title) == ["Dune", "Anathem"])
        #expect(sectioned[sectionTitle: "Horror"]?.map(\.title) == ["It"])
        // Seeds a QueryResult like any plain value — the sealed type as data.
        #expect(QueryResult(wrappedValue: sectioned).wrappedValue.count == 2)
    }

    @Test func initsAndDollarParameterTypecheckInABody() {
        struct Probe: View {
            var body: some View {
                QueryView(index: true, query: Query(sort: \Track.title)) { $tracks in
                    Text(verbatim: "\(tracks.count)")
                }
                QueryView(query: Query(sort: \Track.title)) { core in
                    Text(verbatim: "\(core.wrappedValue.count)")
                }
            }
        }
        _ = Probe()
    }

    @Test func dollarClosureParameterRepropertifiesTheCore() {
        // SE-0293: `$items` re-propertifies the QueryResult closure argument —
        // `items` reads the wrapped value, `$items` the wrapper.
        let render: (QueryResult<[Int]>) -> Int = { $items in
            items.count + ($items.fetchError == nil ? 0 : 100)
        }
        #expect(render(QueryResult(wrappedValue: [1, 2, 3])) == 3)
    }
}
