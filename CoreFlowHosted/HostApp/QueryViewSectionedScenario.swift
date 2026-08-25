import CoreFlow
import SwiftData
import SwiftUI

// SectionedResults exists only in the 27 SDKs (Xcode 27 = Swift 6.4).
#if compiler(>=6.4)
    /// The same content over a real `sectionBy:` query or a `SectionedResults.mock`.
    @available(iOS 27.0, *)
    struct QueryViewSectionedScenario: View {
        let mocked: Bool

        var body: some View {
            if mocked {
                sections.mockQuery(
                    QueryResult(
                        wrappedValue: SectionedResults<Novel, String>.mock([
                            (title: "Sci-Fi", elements: [novel("Dune"), novel("Anathem")]),
                            (title: "Horror", elements: [novel("It")]),
                        ])
                    )
                )
            } else {
                sections.modelContainer(for: Novel.self, inMemory: true) { result in
                    let context = try! result.get().mainContext
                    context.insert(novel("Dune"))
                    context.insert(novel("Anathem"))
                    context.insert(novel("It"))
                }
            }
        }

        private var sections: some View {
            QueryView(query: Query(sort: \Novel.genre, sectionBy: \Novel.genre)) { $sections in
                List {
                    ForEach(sections, id: \.title) { section in
                        Section(section.title) {
                            ForEach(section) { Text($0.title) }
                        }
                    }
                }
            }
        }

        private func novel(_ title: String) -> Novel {
            Novel(title: title, genre: title == "It" ? "Horror" : "Sci-Fi")
        }
    }

    @available(iOS 27.0, *)
    #Preview("Mocked") {
        QueryViewSectionedScenario(mocked: true)
    }
#endif
