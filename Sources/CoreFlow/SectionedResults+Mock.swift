import Foundation
import SwiftData

// SectionedResults exists only in SwiftData >= 180 (the 27 SDKs).
#if canImport(SwiftData, _version: 180)
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
            let elementsOffset = offset(of: "elements", in: frcType)
            let contextOffset = offset(of: "modelContext", in: frcType)
            let batchSizeOffset = offset(of: "batchSize", in: frcType)
            let totalOffset = offset(of: "totalElements", in: frcType)
            var built: [ResultsSection<Element, SectionTitle>] = []
            for section in sections {
                let container = try! ModelContainer(
                    for: Element.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
                let context = ModelContext(container)
                for element in section.elements {
                    context.insert(element)
                }
                try! context.save()
                // Store order is unspecified, so caller order is enforced by
                // fetching each element alone (batchSize 1 → its dict is
                // [0: batch]) and reassembling the batches at the caller's
                // positions. The batch arrays hold the internal element
                // wrapper type; they are moved around under an [Element]
                // spelling — layout-compatible pointer moves, never
                // element-accessed under the wrong type.
                var batches: [Int: [Element]] = [:]
                for (position, element) in section.elements.enumerated() {
                    let id = element.persistentModelID
                    var descriptor = FetchDescriptor<Element>(
                        predicate: #Predicate { $0.persistentModelID == id }
                    )
                    // Batched fetch refuses pending changes; everything is saved.
                    descriptor.includePendingChanges = false
                    let single = try! context.fetch(descriptor, batchSize: 1)
                    precondition(
                        single.count == 1, "SectionedResults.mock: element fetch-back failed"
                    )
                    withUnsafeBytes(of: single) { rawSingle in
                        batches[position] = (rawSingle.baseAddress! + elementsOffset)
                            .load(as: [Int: [Element]].self)[0]!
                    }
                }
                let results: FetchResultsCollection<Element> = fabricate { raw in
                    (raw + elementsOffset).initializeMemory(as: [Int: [Element]].self, to: batches)
                    (raw + contextOffset).initializeMemory(as: ModelContext.self, to: context)
                    (raw + batchSizeOffset).initializeMemory(as: Int.self, to: 1)
                    (raw + totalOffset).initializeMemory(as: Int.self, to: section.elements.count)
                }
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
#endif
