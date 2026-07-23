#if canImport(SwiftData)
    import CoreFlow
    import SwiftData
    import SwiftUI
    import Testing

    // Real, compiled usage of QueryCore's own surface — no live view and no
    // ModelContainer anywhere in this file.

    /// A hand-written stand-in for what `@Shell` generates: because
    /// `QueryCore.init` is callable with the wrapped value alone (both extra
    /// params default), Swift's synthesized memberwise init here takes the
    /// *bare* fetched value — `FakeCore(items: [1], title: "t")`, no
    /// `QueryCore` spelling — which is the ergonomic point of those defaults.
    private struct FakeCore {
        @QueryCore var items: [Int]
        var title: String
    }

    /// Seeding the wrapper's metadata is construction-time, use-site code: an
    /// extension init keeps the synthesized memberwise init alive and reaches
    /// the private `_items` backing (same file, same type — no macro needed;
    /// SE-0258 hardcodes that storage private, and this is the escape hatch).
    extension FakeCore {
        fileprivate init(items: QueryCore<[Int]>, title: String) {
            self._items = items
            self.title = title
        }

        fileprivate var itemsFetchError: (any Error)? { _items.fetchError }
    }

    @Suite struct QueryCoreTests {

        @Test func bothExtraFieldsDefaultSoOneArgConstructionWorks() {
            // `fetchError` defaults to nil; `modelContext` defaults to
            // `Environment(\.modelContext).wrappedValue`, evaluated outside any
            // live view — this test IS the "verified directly, no trap" claim in
            // QueryCore.swift's doc comment.
            let snap = QueryCore(wrappedValue: [1, 2, 3])
            #expect(snap.wrappedValue == [1, 2, 3])
            #expect(snap.fetchError == nil)
            _ = snap.modelContext  // reachable, real, no trap
        }

        @Test func memberwiseInitTakesTheBareFetchedValue() {
            // The flip those defaults buy: a @QueryCore field's synthesized
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
                items: QueryCore(wrappedValue: [9], fetchError: FetchBoom()), title: "t")
            #expect(core.items == [9])
            #expect(core.itemsFetchError is FetchBoom)
        }
    }
#endif
