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
    var sorted: (_ byArtist: Bool, _ descending: Bool) -> LazyQuery<Song, [Song]>
    var by: (_ artist: String) -> LazyQuery<Song, [Song]>
    var all: () -> LazyQuery<Song, [Song]>
}

/// A sectioned query names its section, so it has no default and this
/// service has no `defaultQueries`.
@available(macOS 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, macCatalyst 27.0, *)
@LazyQueries
struct SongSections {
    var byArtist: (_ descending: Bool) -> LazyQuery<Song, SectionedResults<Song, String>>
}

struct Unavailable: Error {}

extension LazyQuery {
    /// What a query asked from a service is built from; nil for a result.
    var query: (dependencies: [any Equatable], query: @MainActor () -> Query<Element, Result>)? {
        guard case let .query(dependencies, query) = source else { return nil }
        return (dependencies, query)
    }

    /// The result a member was set to; nil for a query asked from a service.
    var result: QueryResult<Result>? {
        guard case let .result(result) = source else { return nil }
        return result
    }
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

        let lazy = queries.sorted(true, false).query
        #expect(lazy?.dependencies.count == 2)
        #expect(lazy?.dependencies[0] as? Bool == true)
        #expect(lazy?.dependencies[1] as? Bool == false)
        // Calling the member builds nothing: the expression runs when
        // `QueryView` asks for the query.
        #expect(built == 0)
        _ = lazy?.query()
        #expect(built == 1)

        #expect(queries.by("Björk").query?.dependencies.first as? String == "Björk")
        // A query with no arguments has no dependencies: built once and kept.
        #expect(queries.all().query?.dependencies.isEmpty == true)
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
        let lazy = queries.sorted(true, false).query
        #expect(lazy?.dependencies.count == 2)
        #expect(lazy?.dependencies[0] as? Bool == true)
        #expect(queries.by("Björk").query?.dependencies.first as? String == "Björk")
        #expect(queries.all().query?.dependencies.isEmpty == true)
        _ = lazy?.query()
    }

    @Test func aMemberSetToAResultCarriesItAndTheOthersKeepTheirQueries() {
        let song = Song(title: "Hyperballad", artist: "Björk")
        var queries = SongQueries.defaultQueries
        queries.by = { _ in .result([song]) }
        queries.all = { .result([], fetchError: Unavailable()) }

        // Two members of one result type, each with its own answer.
        #expect(queries.by("Björk").result?.wrappedValue.first === song)
        #expect(queries.by("Björk").result?.fetchError == nil)
        #expect(queries.all().result?.wrappedValue.isEmpty == true)
        #expect(queries.all().result?.fetchError is Unavailable)
        // A result has no query and no dependencies.
        #expect(queries.by("Björk").query == nil)
        // The member that was not set still answers its query.
        #expect(queries.sorted(true, false).result == nil)
        #expect(queries.sorted(true, false).query?.dependencies.count == 2)
    }

    @Test func aResultIsSetAsAMemberThroughTheEnvironmentKeyPath() {
        struct Probe: View {
            var body: some View {
                Text(verbatim: "")
                    .environment(\.songQueries.sorted) { _, _ in .result([]) }
                    .environment(\.songQueries.all) { .result([], fetchError: Unavailable()) }
            }
        }
        _ = Probe()
    }

    @Test @available(macOS 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, macCatalyst 27.0, *)
    func aSectionedQueryGoesThroughTheGeneratedInitializer() {
        let sections = SongSections(byArtist: { descending in
            Query(sort: \Song.title, order: descending ? .reverse : .forward, sectionBy: \Song.artist)
        })
        #expect(sections.byArtist(true).query?.dependencies.first as? Bool == true)
    }

    @Test @available(macOS 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, macCatalyst 27.0, *)
    func aResultIsOfAnyTypeTheQueryAnswers() {
        var sections = SongSections(byArtist: { _ in Query(sort: \Song.title, sectionBy: \Song.artist) })
        let sectioned = SectionedResults.mock([Song(title: "Hyperballad", artist: "Björk")], sectionBy: \.artist)
        sections.byArtist = { _ in .result(sectioned) }
        #expect(sections.byArtist(true).result?.wrappedValue.sectionTitles == ["Björk"])
    }
}

/// This module has no default isolation, so this entry is the proof that
/// `defaultQueries` is reachable from a nonisolated context.
extension EnvironmentValues {
    @Entry var songQueries = SongQueries.defaultQueries
}
