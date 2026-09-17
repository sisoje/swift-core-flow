import Foundation
import SwiftData

/// The runtime reflection entry points Mirror itself uses — field names and
/// offsets straight from metadata, no instance involved.
private struct FieldReflectionMetadata {
    var name: UnsafePointer<CChar>? = nil
    var freeFunc: (@convention(c) (UnsafePointer<CChar>?) -> Void)? = nil
    var isStrong: Bool = false
    var isVar: Bool = false
}

@_silgen_name("swift_reflectionMirror_recursiveCount")
private func fieldCount(_ type: Any.Type) -> Int

@_silgen_name("swift_reflectionMirror_recursiveChildMetadata")
private func fieldMetadata(
    _ type: Any.Type, index: Int,
    fieldMetadata: UnsafeMutablePointer<FieldReflectionMetadata>
) -> Any.Type

@_silgen_name("swift_reflectionMirror_recursiveChildOffset")
private func fieldOffset(_ type: Any.Type, index: Int) -> Int

/// Offsets are read from runtime metadata and matched by field name, so an
/// OS that changes the private layout fails this precondition loudly
/// instead of corrupting memory.
private func offset(of name: String, in type: Any.Type) -> Int {
    for index in 0 ..< fieldCount(type) {
        var meta = FieldReflectionMetadata()
        _ = fieldMetadata(type, index: index, fieldMetadata: &meta)
        defer { meta.freeFunc?(meta.name) }
        if meta.name.map({ String(cString: $0) }) == name {
            return fieldOffset(type, index: index)
        }
    }
    preconditionFailure(
        "SectionedResults.mock: no stored field '\(name)' in \(type) — private layout changed; re-verify against this SDK"
    )
}

private func fabricate<T>(_ build: (UnsafeMutableRawPointer) -> Void) -> T {
    let raw = UnsafeMutableRawPointer.allocate(
        byteCount: MemoryLayout<T>.size, alignment: MemoryLayout<T>.alignment
    )
    defer { raw.deallocate() }
    build(raw)
    return raw.bindMemory(to: T.self, capacity: 1).move()
}

@available(iOS 27.0, macOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, macCatalyst 27.0, *)
public extension SectionedResults {
    /// Fabricates a value of this init-less type for tests and previews.
    ///
    /// `SectionedResults` and `ResultsSection` have no public initializer —
    /// reported to Apple as FB24480699 (public initializers requested;
    /// this whole file becomes deletable the day it's granted) — so this
    /// builds them by memberwise-initializing their
    /// stored fields at runtime-reported offsets — a Reflector-class,
    /// implementation-dependent technique, verified against the 27.0
    /// SDKs. The inner `FetchResultsCollection` is genuine: each
    /// section's elements are inserted into a throwaway in-memory
    /// container and fetched back through the public batched-fetch API,
    /// so element order is the caller's insertion order, instances come
    /// back identical, and the models end up managed by that throwaway
    /// container.
    static func mock(
        _ sections: [(title: SectionTitle, elements: [Element])]
    ) -> SectionedResults<Element, SectionTitle> {
        let titleOffset = offset(of: "title", in: ResultsSection<Element, SectionTitle>.self)
        let resultsOffset = offset(
            of: "_fetchResults", in: ResultsSection<Element, SectionTitle>.self
        )
        let frcType = FetchResultsCollection<Element>.self
        var built: [ResultsSection<Element, SectionTitle>] = []
        for section in sections {
            let container = try! ModelContainer(
                for: Element.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            let context = ModelContext(container)
            // One save per insert: the store numbers rows in save order, and
            // an unsorted fetch reads them back in that order — the caller's.
            for element in section.elements {
                context.insert(element)
                try! context.save()
            }
            // The fetch collection is SwiftData's own, from the public
            // batched fetch; only the two init-less shells are fabricated.
            var descriptor = FetchDescriptor<Element>()
            // Batched fetch refuses pending changes; everything is saved.
            descriptor.includePendingChanges = false
            let results = try! context.fetch(descriptor, batchSize: Swift.max(section.elements.count, 1))
            built.append(
                fabricate { raw in
                    (raw + titleOffset).initializeMemory(
                        as: SectionTitle.self, to: section.title
                    )
                    (raw + resultsOffset).initializeMemory(as: frcType, to: results)
                }
            )
        }
        let sectionsOffset = offset(of: "_sections", in: Self.self)
        let indexOffset = offset(of: "_sectionsByTitle", in: Self.self)
        let index = Dictionary(uniqueKeysWithValues: built.enumerated().map { ($1.title, $0) })
        return fabricate { raw in
            (raw + sectionsOffset).initializeMemory(
                as: [ResultsSection<Element, SectionTitle>].self, to: built
            )
            (raw + indexOffset).initializeMemory(as: [SectionTitle: Int].self, to: index)
        }
    }
}
