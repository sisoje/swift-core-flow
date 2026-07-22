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
        @RawProperty @QueryCore var items: [Int]
        var title: String
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

        @Test func fetchErrorAndModelContextSeedViaTheRawAccessor() {
            // Seeding the metadata fields goes through @RawProperty's raw_
            // accessor — construct the wrapper explicitly and swap it in, the
            // same re-mocking path every wrapper field on Core supports.
            struct FetchBoom: Error {}
            var core = FakeCore(items: [], title: "t")
            core.raw_items = QueryCore(wrappedValue: [9], fetchError: FetchBoom())
            #expect(core.items == [9])
            #expect(core.raw_items.fetchError is FetchBoom)
        }
    }
#endif
