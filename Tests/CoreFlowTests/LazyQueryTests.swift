@testable import CoreFlow
import SwiftData
import SwiftUI
import Testing

// Real, compiled usage of the LazyQuery surface and of what `@LazyQueries`
// writes — no live view anywhere in this file. That the query is rebuilt only
// when an argument changes is CoreFlowHosted's story (`LazyQueryUITests`).

@Model
final class Song {
    var title: String
    var artist: String
    init(title: String, artist: String) {
        self.title = title
        self.artist = artist
    }
}

/// A query service the way an app declares one: each member answers a
/// `LazyQuery`, written once, and the initializer takes plain query
/// expressions.
@LazyQueries
struct SongQueries {
    let sorted: (_ byArtist: Bool, _ descending: Bool) -> LazyQuery<Song, [Song]>
    let by: (_ artist: String) -> LazyQuery<Song, [Song]>
    let all: () -> LazyQuery<Song, [Song]>
}

/// A sectioned query names its section, so it has no default and this
/// service has no `defaultQueries`.
@available(macOS 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, macCatalyst 27.0, *)
@LazyQueries
struct SongSections {
    let byArtist: (_ descending: Bool) -> LazyQuery<Song, SectionedResults<Song, String>>
}

@MainActor
struct LazyQueryTests {
    @Test func theArgumentsAreTheDependenciesAndNothingIsBuiltUntilAsked() {
        var built = 0
        let queries = SongQueries(
            sorted: { byArtist, descending in
                built += 1
                return Query(sort: byArtist ? \Song.artist : \Song.title, order: descending ? .reverse : .forward)
            },
            by: { artist in Query(filter: #Predicate<Song> { $0.artist == artist }, sort: \Song.title) },
            all: { Query() }
        )

        let lazy = queries.sorted(true, false)
        #expect(lazy.dependencies.count == 2)
        #expect(lazy.dependencies[0] as? Bool == true)
        #expect(lazy.dependencies[1] as? Bool == false)
        // Calling the member builds nothing: the expression runs when
        // `QueryView` asks for the query.
        #expect(built == 0)
        _ = lazy.query()
        #expect(built == 1)

        #expect(queries.by("Björk").dependencies.first as? String == "Björk")
        // A query with no arguments has no dependencies: built once and kept.
        #expect(queries.all().dependencies.isEmpty)
    }

    @Test func aServiceMemberTypechecksInABody() {
        struct Probe: View {
            let queries: SongQueries
            var descending = false

            var body: some View {
                QueryView(queries.sorted(false, descending)) { $songs in
                    Text(verbatim: "\(songs.count)")
                }
                QueryView(queries.all()) { result in
                    Text(verbatim: "\(result.wrappedValue.count)")
                }
            }
        }
        _ = Probe(queries: SongQueries(sorted: { _, _ in Query() }, by: { _ in Query() }, all: { Query() }))
    }

    @Test func defaultQueriesAnswersTheDefaultQueryWhateverItIsAskedWith() {
        let queries = SongQueries.defaultQueries
        // Still asked with arguments, and they are still the dependencies.
        let lazy = queries.sorted(true, false)
        #expect(lazy.dependencies.count == 2)
        #expect(lazy.dependencies[0] as? Bool == true)
        #expect(queries.by("Björk").dependencies.first as? String == "Björk")
        #expect(queries.all().dependencies.isEmpty)
        _ = lazy.query()
    }

    @Test @available(macOS 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, macCatalyst 27.0, *)
    func aSectionedQueryGoesThroughTheGeneratedInitializer() {
        let sections = SongSections(byArtist: { descending in
            Query(sort: \Song.title, order: descending ? .reverse : .forward, sectionBy: \Song.artist)
        })
        #expect(sections.byArtist(true).dependencies.first as? Bool == true)
    }
}
