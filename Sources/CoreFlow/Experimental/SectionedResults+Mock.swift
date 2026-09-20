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
    /// `sectionBy` values; sections and rows follow `sortBy` (by default the
    /// section key path). The caller's instances come back, managed by that
    /// throwaway container.
    @MainActor
    static func mock(
        _ elements: [Element],
        sectionBy: KeyPath<Element, String> & Sendable,
        sortBy: [SortDescriptor<Element>]? = nil
    ) -> SectionedResults<Element, String> {
        let container = try! ModelContainer(
            for: Element.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        for element in elements {
            context.insert(element)
        }
        try! context.save()
        let observer = try! ResultsObserver<Element, String>(
            sortBy: sortBy ?? [SortDescriptor(sectionBy)], sectionBy: sectionBy, modelContext: context
        )
        return observer.sections!
    }
}
