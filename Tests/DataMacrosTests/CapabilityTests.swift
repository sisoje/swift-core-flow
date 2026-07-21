import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import DataMacrosMacros

final class CapabilityTests: XCTestCase {
    let macros: [String: Macro.Type] = ["Capability": CapabilityMacro.self]

    func testAttachedToAnExtensionBundlesComputedPropertiesAndMethods() {
        // Stored properties (me, zola, zola2) don't participate — only computed
        // members do. This is the case @DataLayout can't cover:
        // an extension can't declare stored properties, but it can declare these.
        assertMacroExpansion(
            """
            @Capability
            extension MySomething {
                var x: Int {
                    zola * me
                }

                func doSomething() {
                    print(zola)
                }

                func meme() async throws {
                    try await Task.sleep(nanoseconds: 1)
                }
            }
            """,
            expandedSource: """
                extension MySomething {
                    var x: Int {
                        zola * me
                    }

                    func doSomething() {
                        print(zola)
                    }

                    func meme() async throws {
                        try await Task.sleep(nanoseconds: 1)
                    }

                    typealias Capability = (x: Int, doSomething: () -> Void, meme: () async throws -> Void)

                    var capability: Capability {
                        (x, doSomething, meme)
                    }
                }
                """,
            macros: macros
        )
    }

    func testAttachedDirectlyToAStructWorksTheSameWay() {
        assertMacroExpansion(
            """
            @Capability
            public struct Counter {
                private var count = 0
                var doubled: Int { count * 2 }
                func increment() { count += 1 }
            }
            """,
            expandedSource: """
                public struct Counter {
                    private var count = 0
                    var doubled: Int { count * 2 }
                    func increment() { count += 1 }

                    public typealias Capability = (doubled: Int, increment: () -> Void)

                    public var capability: Capability {
                        (doubled, increment)
                    }
                }
                """,
            macros: macros
        )
    }

    func testSingleEligibleMemberCollapsesToItsBareTypeNotATuple() {
        // Same collapse @DataLayout's DataLayout typealias does for one property — Swift has no
        // 1-tuples, so (x: Int) as a type is indistinguishable from plain Int.
        assertMacroExpansion(
            """
            @Capability
            public struct Box {
                public var x: Int { 1 }
            }
            """,
            expandedSource: """
                public struct Box {
                    public var x: Int { 1 }

                    public typealias Capability = Int

                    public var capability: Capability {
                        x
                    }
                }
                """,
            macros: macros
        )
    }

    func testMethodParametersDropLabelsAndKeepTypesInDeclaredOrder() {
        assertMacroExpansion(
            """
            @Capability
            extension Adder {
                func add(_ x: Int, to y: Int) -> Int { x + y }
                var zero: Int { 0 }
            }
            """,
            expandedSource: """
                extension Adder {
                    func add(_ x: Int, to y: Int) -> Int { x + y }
                    var zero: Int { 0 }

                    typealias Capability = (add: (Int, Int) -> Int, zero: Int)

                    var capability: Capability {
                        (add, zero)
                    }
                }
                """,
            macros: macros
        )
    }

    func testStoredPropertiesAndMutatingMethodsAreExcluded() {
        // A stored property has nothing to compute; a mutating method can't be
        // referenced as a plain closure value on a value type (`self` isn't
        // mutable in that expression) — Swift rejects it outright.
        assertMacroExpansion(
            """
            @Capability
            public struct Counter {
                public var storedCount: Int = 0
                public var doubled: Int { storedCount * 2 }
                public mutating func increment() { storedCount += 1 }
            }
            """,
            expandedSource: """
                public struct Counter {
                    public var storedCount: Int = 0
                    public var doubled: Int { storedCount * 2 }
                    public mutating func increment() { storedCount += 1 }

                    public typealias Capability = Int

                    public var capability: Capability {
                        doubled
                    }
                }
                """,
            macros: macros
        )
    }

    func testPrivateAndStaticMembersAreExcluded() {
        assertMacroExpansion(
            """
            @Capability
            public struct V {
                public var title: String { "t" }
                private var cache: Int { 0 }
                fileprivate func helper() {}
                static var shared: V { V() }
                public func run() {}
            }
            """,
            expandedSource: """
                public struct V {
                    public var title: String { "t" }
                    private var cache: Int { 0 }
                    fileprivate func helper() {}
                    static var shared: V { V() }
                    public func run() {}

                    public typealias Capability = (title: String, run: () -> Void)

                    public var capability: Capability {
                        (title, run)
                    }
                }
                """,
            macros: macros
        )
    }

    func testDiagnosesNoEligibleMembers() {
        assertMacroExpansion(
            """
            @Capability
            public struct Empty {
                public let x: Int
            }
            """,
            expandedSource: """
                public struct Empty {
                    public let x: Int
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "@Capability found no eligible computed properties or methods — nothing to bundle into a Capability.",
                    line: 1,
                    column: 1
                )
            ],
            macros: macros
        )
    }

    func testDiagnosesMissingTypeOnAComputedProperty() {
        // SwiftSyntax's parser accepts a computed property with no type annotation
        // even though real Swift itself would separately reject it ("computed
        // property must have an explicit type") — assertMacroExpansion only runs
        // macro expansion, not full type-checking, so this exercises our own
        // diagnostic independent of that.
        assertMacroExpansion(
            """
            @Capability
            public struct Thing {
                public var value { 0 }
            }
            """,
            expandedSource: """
                public struct Thing {
                    public var value { 0 }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "Computed property 'value' needs an explicit type annotation so @Capability can include it.",
                    line: 3,
                    column: 16
                )
            ],
            macros: macros
        )
    }

    func testDiagnosesNotAnEligibleDeclaration() {
        assertMacroExpansion(
            """
            @Capability
            public enum E {
                case a
            }
            """,
            expandedSource: """
                public enum E {
                    case a
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "@Capability can only be attached to a struct, class, actor, or an extension of one.",
                    line: 1,
                    column: 1
                )
            ],
            macros: macros
        )
    }
}
