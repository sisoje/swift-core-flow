#if canImport(SwiftData)
    import CoreFlow
    import SwiftData
    import SwiftUI
    import Testing

    // Real, compiled usage of QueryResult's own surface — no live view and no
    // ModelContainer anywhere in this file.

    /// A hand-written stand-in for what `@Shell` generates: because
    /// `QueryResult.init` is callable with the wrapped value alone (`fetchError`
    /// defaults), Swift's synthesized memberwise init here takes the
    /// *bare* fetched value — `FakeCore(items: [1], title: "t")`, no
    /// `QueryResult` spelling — which is the ergonomic point of that default.
    private struct FakeCore {
        @QueryResult var items: [Int]
        var title: String
    }

    /// Seeding the wrapper's metadata is construction-time, use-site code: an
    /// extension init keeps the synthesized memberwise init alive and reaches
    /// the private `_items` backing (same file, same type — no macro needed;
    /// SE-0258 hardcodes that storage private, and this is the escape hatch).
    extension FakeCore {
        init(items: QueryResult<[Int]>, title: String) {
            _items = items
            self.title = title
        }

        var itemsFetchError: (any Error)? {
            _items.fetchError
        }
    }

    struct QueryResultTests {
        @Test func fetchErrorDefaultsSoOneArgConstructionWorks() {
            // `fetchError` defaults to nil, so the wrapper constructs from the
            // value alone; `modelContext` is environment-fed and installs only
            // hosted — nothing to read here.
            let snap = QueryResult(wrappedValue: [1, 2, 3])
            #expect(snap.wrappedValue == [1, 2, 3])
            #expect(snap.fetchError == nil)
        }

        @Test func memberwiseInitTakesTheBareFetchedValue() {
            // The flip those defaults buy: a @QueryResult field's synthesized
            // memberwise init parameter is the wrapped type itself.
            let core = FakeCore(items: [4, 5], title: "t")
            #expect(core.items == [4, 5])
            #expect(core.title == "t")
        }

        @Test func fetchErrorSeedsAtConstructionThroughTheExplicitWrapper() {
            // A test that cares about the metadata constructs the wrapper
            // explicitly — mocking happens at construction, nothing is swapped
            // on a live value.
            struct FetchBoom: Error {}
            let core = FakeCore(
                items: QueryResult(wrappedValue: [9], fetchError: FetchBoom()), title: "t"
            )
            #expect(core.items == [9])
            #expect(core.itemsFetchError is FetchBoom)
        }
    }
#endif
