@testable import CoreFlowMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

final class LazyQueriesExpansionTests: XCTestCase {
    let macros: [String: Macro.Type] = ["LazyQueries": LazyQueriesMacro.self]

    func testEachMemberTakesItsQueryExpressionAndDefaultQueriesAnswersTheDefaultQuery() {
        // The README's sample: the member keeps its argument labels, the
        // parameter is the same function answering `Query`, and the default
        // ignores every argument.
        assertMacroExpansion(
            """
            @LazyQueries
            struct BookQueries {
                let sorted: (_ byAuthor: Bool, _ descending: Bool) -> LazyQuery<Book, [Book]>
                let by: (_ author: String) -> LazyQuery<Book, [Book]>
            }
            """,
            expandedSource: """
            struct BookQueries {
                let sorted: (_ byAuthor: Bool, _ descending: Bool) -> LazyQuery<Book, [Book]>
                let by: (_ author: String) -> LazyQuery<Book, [Book]>

                init(
                    sorted: @escaping @MainActor (_ byAuthor: Bool, _ descending: Bool) -> Query<Book, [Book]>,
                    by: @escaping @MainActor (_ author: String) -> Query<Book, [Book]>
                ) {
                    self.sorted = QueryUtilities.lazy(sorted)
                    self.by = QueryUtilities.lazy(by)
                }

                static var defaultQueries: Self {
                    Self(
                        sorted: { _, _ in
                            Query()
                        },
                        by: { _ in
                            Query()
                        }
                    )
                }
            }
            """,
            macros: macros
        )
    }

    func testAccessMirrorsTheTypeAndAQueryWithNoArgumentsTakesNone() {
        assertMacroExpansion(
            """
            @LazyQueries
            public struct Queries {
                public var all: () -> LazyQuery<Book, [Book]>
            }
            """,
            expandedSource: """
            public struct Queries {
                public var all: () -> LazyQuery<Book, [Book]>

                public init(
                    all: @escaping @MainActor () -> Query<Book, [Book]>
                ) {
                    self.all = QueryUtilities.lazy(all)
                }

                public static var defaultQueries: Self {
                    Self(
                        all: {
                            Query()
                        }
                    )
                }
            }
            """,
            macros: macros
        )
    }

    func testASectionedQueryHasNoDefaultSoTheServiceGetsTheInitializerAlone() {
        // Only the name `LazyQuery` changes, its generic arguments are
        // copied. `Query()` exists for an array result alone, so one query
        // that answers anything else leaves `defaultQueries` unwritten.
        assertMacroExpansion(
            """
            @LazyQueries
            struct Queries {
                var all: () -> LazyQuery<Book, [Book]>
                var byAuthor: (_ descending: Bool) -> LazyQuery<Book, SectionedResults<Book, String>>
            }
            """,
            expandedSource: """
            struct Queries {
                var all: () -> LazyQuery<Book, [Book]>
                var byAuthor: (_ descending: Bool) -> LazyQuery<Book, SectionedResults<Book, String>>

                init(
                    all: @escaping @MainActor () -> Query<Book, [Book]>,
                    byAuthor: @escaping @MainActor (_ descending: Bool) -> Query<Book, SectionedResults<Book, String>>
                ) {
                    self.all = QueryUtilities.lazy(all)
                    self.byAuthor = QueryUtilities.lazy(byAuthor)
                }
            }
            """,
            macros: macros
        )
    }

    func testAMembersInlineDefaultIsNotCarried() {
        // The member's default answers `LazyQuery`; the parameter takes the
        // query expression, so it stays required and the initializer assigns.
        assertMacroExpansion(
            """
            @LazyQueries
            struct Queries {
                var all: () -> LazyQuery<Book, [Book]> = QueryUtilities.lazy { Query() }
            }
            """,
            expandedSource: """
            struct Queries {
                var all: () -> LazyQuery<Book, [Book]> = QueryUtilities.lazy { Query() }

                init(
                    all: @escaping @MainActor () -> Query<Book, [Book]>
                ) {
                    self.all = QueryUtilities.lazy(all)
                }

                static var defaultQueries: Self {
                    Self(
                        all: {
                            Query()
                        }
                    )
                }
            }
            """,
            macros: macros
        )
    }

    func testDiagnosesEveryMemberThatIsNotAQuery() {
        // Syntax-only: a value, an attributed function type, a qualified
        // result and an optional closure are not queries. Nothing is
        // generated, so no member is left out of an initializer.
        let message: (String) -> String = {
            "'\($0)' is not a query. Every stored property of a @LazyQueries type is a function type with no attributes whose result is spelled LazyQuery<…>, such as `(_ title: String) -> LazyQuery<Book, [Book]>`."
        }
        assertMacroExpansion(
            """
            @LazyQueries
            struct Queries {
                let all: () -> LazyQuery<Book, [Book]>
                var limit = 10
                let isolated: @MainActor (_ flag: Bool) -> LazyQuery<Book, [Book]>
                let qualified: (_ flag: Bool) -> CoreFlow.LazyQuery<Book, [Book]>
                var optional: ((_ flag: Bool) -> LazyQuery<Book, [Book]>)?
            }
            """,
            expandedSource: """
            struct Queries {
                let all: () -> LazyQuery<Book, [Book]>
                var limit = 10
                let isolated: @MainActor (_ flag: Bool) -> LazyQuery<Book, [Book]>
                let qualified: (_ flag: Bool) -> CoreFlow.LazyQuery<Book, [Book]>
                var optional: ((_ flag: Bool) -> LazyQuery<Book, [Book]>)?
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: message("limit"), line: 4, column: 9),
                DiagnosticSpec(message: message("isolated"), line: 5, column: 9),
                DiagnosticSpec(message: message("qualified"), line: 6, column: 9),
                DiagnosticSpec(message: message("optional"), line: 7, column: 9),
            ],
            macros: macros
        )
    }

    func testZeroQueriesGeneratesTheBareInitAndAnEmptyDefault() {
        assertMacroExpansion(
            """
            @LazyQueries
            public struct Empty {
            }
            """,
            expandedSource: """
            public struct Empty {

                public init() {

                }

                public static var defaultQueries: Self {
                    Self()
                }
            }
            """,
            macros: macros
        )
    }

    func testDiagnosesNotADataType() {
        // The shared entry, naming this macro.
        assertMacroExpansion(
            """
            @LazyQueries
            enum Queries {
                case books
            }
            """,
            expandedSource: """
            enum Queries {
                case books
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@LazyQueries can only be attached to a struct, class, or actor.",
                    line: 1,
                    column: 1
                ),
            ],
            macros: macros
        )
    }
}
