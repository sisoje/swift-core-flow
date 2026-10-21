import Foundation
import SwiftData

@available(iOS 27.0, macOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, macCatalyst 27.0, *)
public extension SectionedResults where SectionTitle == String {
    /// A genuine value of this init-less type for tests and previews.
    ///
    /// `SectionedResults` and `ResultsSection` have no public initializer —
    /// reported to Apple as FB24480699 — so the value comes from SwiftData
    /// itself: the elements go into a throwaway in-memory container and a
    /// public `ResultsObserver` sections them, exactly as a live
    /// `Query(sort:sectionBy:)` would. Titles are the elements' own
    /// `sectionBy` values; sections and rows follow `sortBy` (without it,
    /// title order). The caller's instances come back, managed by that
    /// throwaway container.
    @MainActor
    static func mock(
        _ elements: [Element],
        sectionBy: KeyPath<Element, String>,
        sortBy: [SortDescriptor<Element>]? = nil
    ) -> SectionedResults<Element, String> {
        let observer = try! ResultsObserver<Element, String>(
            sortBy: sortBy, sectionBy: sectionBy, modelContext: seeded(elements)
        )
        return observer.sections!
    }

    /// The same over an optional title, as `Query` takes one.
    @MainActor
    static func mock(
        _ elements: [Element],
        sectionBy: KeyPath<Element, String?>,
        sortBy: [SortDescriptor<Element>]? = nil
    ) -> SectionedResults<Element, String> {
        let observer = try! ResultsObserver<Element, String>(
            sortBy: sortBy, sectionBy: sectionBy, modelContext: seeded(elements)
        )
        return observer.sections!
    }

    /// The elements in a throwaway in-memory container.
    @MainActor
    private static func seeded(_ elements: [Element]) -> ModelContext {
        let container = try! ModelContainer(
            for: Element.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        for element in elements {
            context.insert(element)
        }
        try! context.save()
        return context
    }
}
