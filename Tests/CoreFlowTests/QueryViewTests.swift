@testable import CoreFlow
import SwiftData
import SwiftUI
import Testing

// Real, compiled usage of the QueryView surface — no live view anywhere in
// this file. Hosted behavior (installation, dependency gating, in-memory
// container mocking) is CoreFlowHosted's story.

@Model
private final class Track {
    var title: String
    init(title: String) {
        self.title = title
    }
}

@MainActor
struct QueryViewTests {
    @Test func aQueryMadeInPlaceAResultAndTheDollarParameterTypecheckInABody() {
        struct Probe: View {
            var descending = false

            var body: some View {
                let sorted = LazyQuery.query { (descending: Bool) in
                    Query(sort: \Track.title, order: descending ? .reverse : .forward)
                }
                let all = LazyQuery.query { Query(sort: \Track.title) }
                QueryView(sorted(descending)) { $tracks in
                    Text(verbatim: "\(tracks.count)")
                }
                QueryView(all()) { result in
                    Text(verbatim: "\(result.wrappedValue.count)")
                }
                QueryView(LazyQuery<Track, [Track]>.result(QueryResult(wrappedValue: [Track(title: "Dune")]))) { $tracks in
                    Text(verbatim: "\(tracks.count)")
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
