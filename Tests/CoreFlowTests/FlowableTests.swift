@testable import CoreFlowMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

final class FlowableTests: XCTestCase {
    let macros: [String: Macro.Type] = ["Flowable": FlowableMacro.self]

    func testPublicStructGetsPublicInit() {
        assertMacroExpansion(
            """
            @Flowable
            public struct User {
                public let id: UUID
                public var isActive: Bool = false
            }
            """,
            expandedSource: """
            public struct User {
                public let id: UUID
                public var isActive: Bool = false

                public init(id: UUID, isActive: Bool = false) {
                    self.id = id
                    self.isActive = isActive
                }

                public static func makeFlow(_ flow: (UUID, Bool)) -> Self {
                    Self(id: flow.0, isActive: flow.1)
                }

                public typealias InFlow = (id: UUID, isActive: Bool)
            }
            """,
            macros: macros
        )
    }

    func testAccessLevelMirrorsTheStruct() {
        // A plain (internal) struct gets an init and typealias with no access modifier.
        assertMacroExpansion(
            """
            @Flowable
            struct Point {
                let x: Int
                let y: Int
            }
            """,
            expandedSource: """
            struct Point {
                let x: Int
                let y: Int

                init(x: Int, y: Int) {
                    self.x = x
                    self.y = y
                }

                static func makeFlow(_ flow: (Int, Int)) -> Self {
                    Self(x: flow.0, y: flow.1)
                }

                typealias InFlow = (x: Int, y: Int)
            }
            """,
            macros: macros
        )
    }

    func testSingleClosurePropertyMakesFlowParameterEscaping() {
        // The 1-field collapse makes `flow` a DIRECT function parameter —
        // non-escaping by default, yet forwarded to the init's @escaping
        // parameter. Caught live by the ReadingList example.
        assertMacroExpansion(
            """
            @Flowable
            struct Deleter {
                let onDelete: (String) -> Void
            }
            """,
            expandedSource: """
            struct Deleter {
                let onDelete: (String) -> Void

                init(onDelete: @escaping (String) -> Void) {
                    self.onDelete = onDelete
                }

                static func makeFlow(_ flow: @escaping (String) -> Void) -> Self {
                    Self(onDelete: flow)
                }

                typealias InFlow = (String) -> Void
            }
            """,
            macros: macros
        )
    }

    func testWorksOnAClass() {
        // Works on a class too — e.g. an @Observable class, which Swift gives no
        // memberwise init at all. Access level mirrors the type (internal here).
        // One property collapses makeFlow's parameter to its bare type, not a 1-tuple.
        assertMacroExpansion(
            """
            @Flowable
            @Observable final class Zola {
                var ii: Int = 0
            }
            """,
            expandedSource: """
            @Observable final class Zola {
                var ii: Int = 0

                init(ii: Int = 0) {
                    self.ii = ii
                }

                static func makeFlow(_ flow: Int) -> Self {
                    Self(ii: flow)
                }

                typealias InFlow = Int
            }
            """,
            macros: macros
        )
    }

    func testWorksOnAnActor() {
        // Works on an actor too — a synchronous memberwise init is valid (it runs
        // before isolation applies). Access level mirrors the type.
        assertMacroExpansion(
            """
            @Flowable
            public actor Counter {
                public var count: Int = 0
            }
            """,
            expandedSource: """
            public actor Counter {
                public var count: Int = 0

                public init(count: Int = 0) {
                    self.count = count
                }

                public static func makeFlow(_ flow: Int) -> Self {
                    Self(count: flow)
                }

                public typealias InFlow = Int
            }
            """,
            macros: macros
        )
    }

    func testClosuresGetEscaping() {
        // The init gets @escaping on every function-typed param; makeFlow's
        // tuple never does (a closure nested inside a tuple type is already
        // escaping — @escaping is only legal directly on a function parameter).
        assertMacroExpansion(
            """
            @Flowable
            public struct Handler {
                public var onChange: () -> Void
                public var onMain: @MainActor () -> Void
                public var onSend: @Sendable (Int) -> Void
            }
            """,
            expandedSource: """
            public struct Handler {
                public var onChange: () -> Void
                public var onMain: @MainActor () -> Void
                public var onSend: @Sendable (Int) -> Void

                public init(onChange: @escaping () -> Void, onMain: @escaping @MainActor () -> Void, onSend: @escaping @Sendable (Int) -> Void) {
                    self.onChange = onChange
                    self.onMain = onMain
                    self.onSend = onSend
                }

                public static func makeFlow(_ flow: (() -> Void, @MainActor () -> Void, @Sendable (Int) -> Void)) -> Self {
                    Self(onChange: flow.0, onMain: flow.1, onSend: flow.2)
                }

                public typealias InFlow = (onChange: () -> Void, onMain: @MainActor () -> Void, onSend: @Sendable (Int) -> Void)
            }
            """,
            macros: macros
        )
    }

    func testOptionalVarsAreImplicitlyNilDefaulted() {
        // Optional vars default to nil like Swift's own synthesizer; optional
        // closures get no @escaping (already escaping — adding it is a
        // compile error); the typealias carries no defaults (tuple element
        // types can't).
        assertMacroExpansion(
            """
            @Flowable
            public struct Handler {
                public var nickname: String?
                public var onChange: (() -> Void)?
                public var onSend: (@Sendable (Int) -> Void)!
            }
            """,
            expandedSource: """
            public struct Handler {
                public var nickname: String?
                public var onChange: (() -> Void)?
                public var onSend: (@Sendable (Int) -> Void)!

                public init(nickname: String? = nil, onChange: (() -> Void)? = nil, onSend: (@Sendable (Int) -> Void)! = nil) {
                    self.nickname = nickname
                    self.onChange = onChange
                    self.onSend = onSend
                }

                public static func makeFlow(_ flow: (String?, (() -> Void)?, (@Sendable (Int) -> Void)!)) -> Self {
                    Self(nickname: flow.0, onChange: flow.1, onSend: flow.2)
                }

                public typealias InFlow = (nickname: String?, onChange: (() -> Void)?, onSend: (@Sendable (Int) -> Void)!)
            }
            """,
            macros: macros
        )
    }

    func testOnlyBindingWrappersReachTheInit() {
        // Only @Binding reaches the init/typealiases; private wrappers still
        // need explicit types (Core reads them — enforced uniformly by the
        // shared collection).
        assertMacroExpansion(
            """
            @Flowable
            public struct ProfileCard: View {
                @Environment(\\.colorScheme) private var colorScheme: ColorScheme
                @Binding public var isOn: Bool
                @State private var isExpanded: Bool = false
                public let title: String
            }
            """,
            expandedSource: """
            public struct ProfileCard: View {
                @Environment(\\.colorScheme) private var colorScheme: ColorScheme
                @Binding public var isOn: Bool
                @State private var isExpanded: Bool = false
                public let title: String

                public init(isOn: Binding<Bool>, title: String) {
                    self._isOn = isOn
                    self.title = title
                }

                public static func makeFlow(_ flow: (Binding<Bool>, String)) -> Self {
                    Self(isOn: flow.0, title: flow.1)
                }

                public typealias InFlow = (isOn: Binding<Bool>, title: String)
            }
            """,
            macros: macros
        )
    }

    func testStateWithoutAnInlineDefaultIsFineHereItIsShellsRule() {
        // @Shell diagnoses a defaultless @State (Core copies the default
        // onto its @TestState field); @Flowable renders nothing from a
        // private @State, so it has no stake and stays out of the way.
        assertMacroExpansion(
            """
            @Flowable
            struct Card: View {
                @State private var selection: Int?
                var title: String
            }
            """,
            expandedSource: """
            struct Card: View {
                @State private var selection: Int?
                var title: String

                init(title: String) {
                    self.title = title
                }

                static func makeFlow(_ flow: String) -> Self {
                    Self(title: flow)
                }

                typealias InFlow = String
            }
            """,
            macros: macros
        )
    }

    func testDiagnosesPlainPrivatePropertyWithNoWrapper() {
        // A private property with no property wrapper is a compile error, not
        // a silent exclusion: pure data flow has no room for opaque private
        // state that's neither a source of truth nor something a caller
        // supplies.
        assertMacroExpansion(
            """
            @Flowable
            public struct V {
                public var title: String
                private var cache: Int = 0
                fileprivate var scratch = ""
                private let seed = 42
            }
            """,
            expandedSource: """
            public struct V {
                public var title: String
                private var cache: Int = 0
                fileprivate var scratch = ""
                private let seed = 42
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                    "'cache' is private with no property wrapper — @Flowable has no room for opaque private state in pure data flow. Make it non-private, or give it a property wrapper (mapped ones are substituted with mockable stand-ins; any other is copied onto Core verbatim).",
                    line: 4,
                    column: 17
                ),
                DiagnosticSpec(
                    message:
                    "'scratch' is private with no property wrapper — @Flowable has no room for opaque private state in pure data flow. Make it non-private, or give it a property wrapper (mapped ones are substituted with mockable stand-ins; any other is copied onto Core verbatim).",
                    line: 5,
                    column: 21
                ),
                DiagnosticSpec(
                    message:
                    "'seed' is private with no property wrapper — @Flowable has no room for opaque private state in pure data flow. Make it non-private, or give it a property wrapper (mapped ones are substituted with mockable stand-ins; any other is copied onto Core verbatim).",
                    line: 6,
                    column: 17
                ),
            ],
            macros: macros
        )
    }

    func testCallerSuppliedWrapperDeclaredPrivateIsDiagnosed() {
        // Caller-supplied kinds declared private are unreachable — rejected
        // with a dedicated message. Only these two: any other private
        // wrapper copies onto Core verbatim, no diagnostic.
        assertMacroExpansion(
            """
            @Flowable
            struct V {
                @Binding private var isOn: Bool
            }
            """,
            expandedSource: """
            struct V {
                @Binding private var isOn: Bool
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                    "'isOn' uses @Binding, which a caller supplies through @Flowable's generated init — declaring it private makes it unreachable. Remove `private`/`fileprivate` from 'isOn'.",
                    line: 3,
                    column: 26
                ),
            ],
            macros: macros
        )
    }

    func testViewBuilderPropertiesGetBuilderParameters() {
        // The init wraps a stored-value @ViewBuilder field into a builder
        // and calls it; makeFlow's tuple and InFlow keep the bare type;
        // makeFlow(_:) re-wraps as a trivial closure. Reasons: baseTypeText/
        // renderMakeFlowFactory docs.
        assertMacroExpansion(
            """
            @Flowable
            public struct ProfileCard<Content: View>: View {
                public let title: String
                @ViewBuilder let content: () -> Content
                @ViewBuilder let footer: Content
            }
            """,
            expandedSource: """
            public struct ProfileCard<Content: View>: View {
                public let title: String
                @ViewBuilder let content: () -> Content
                @ViewBuilder let footer: Content

                public init(title: String, @ViewBuilder content: @escaping () -> Content, @ViewBuilder footer: () -> Content) {
                    self.title = title
                    self.content = content
                    self.footer = footer()
                }

                public static func makeFlow(_ flow: (String, () -> Content, Content)) -> Self {
                    Self(title: flow.0, content: flow.1, footer: {
                            flow.2
                        })
                }

                public typealias InFlow = (title: String, content: () -> Content, footer: Content)
            }
            """,
            macros: macros
        )
    }

    func testComputedAndStaticAreSkipped() {
        assertMacroExpansion(
            """
            @Flowable
            public struct Point {
                public let x: Double
                public let y: Double
                public static let origin = Point(x: 0, y: 0)
                public var magnitude: Double { (x * x + y * y).squareRoot() }
            }
            """,
            expandedSource: """
            public struct Point {
                public let x: Double
                public let y: Double
                public static let origin = Point(x: 0, y: 0)
                public var magnitude: Double { (x * x + y * y).squareRoot() }

                public init(x: Double, y: Double) {
                    self.x = x
                    self.y = y
                }

                public static func makeFlow(_ flow: (Double, Double)) -> Self {
                    Self(x: flow.0, y: flow.1)
                }

                public typealias InFlow = (x: Double, y: Double)
            }
            """,
            macros: macros
        )
    }

    func testOnePropertyCollapsesTheFlowShapeToItsBareType() {
        // Swift has no 1-tuples — makeFlow's parameter and InFlow both
        // collapse to the bare type; the value passes directly, no positional
        // index.
        assertMacroExpansion(
            """
            @Flowable
            public struct Box {
                public let value: Int
            }
            """,
            expandedSource: """
            public struct Box {
                public let value: Int

                public init(value: Int) {
                    self.value = value
                }

                public static func makeFlow(_ flow: Int) -> Self {
                    Self(value: flow)
                }

                public typealias InFlow = Int
            }
            """,
            macros: macros
        )
    }

    func testTwoPropertiesGetATupleFlowShape() {
        assertMacroExpansion(
            """
            @Flowable
            public struct Point {
                public let x: Int
                public let y: Int
            }
            """,
            expandedSource: """
            public struct Point {
                public let x: Int
                public let y: Int

                public init(x: Int, y: Int) {
                    self.x = x
                    self.y = y
                }

                public static func makeFlow(_ flow: (Int, Int)) -> Self {
                    Self(x: flow.0, y: flow.1)
                }

                public typealias InFlow = (x: Int, y: Int)
            }
            """,
            macros: macros
        )
    }

    func testZeroPropertiesGeneratesOnlyTheBareInit() {
        // Nothing to alias/build from — makeFlow(_:) and InFlow share the
        // same "at least one participating property" rule, so a zero-property
        // type gets only the bare init, nothing else.
        assertMacroExpansion(
            """
            @Flowable
            public struct Empty {
            }
            """,
            expandedSource: """
            public struct Empty {

                public init() {

                }
            }
            """,
            macros: macros
        )
    }

    func testDiagnosesNotAStruct() {
        assertMacroExpansion(
            """
            @Flowable
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
                    message: "@Flowable can only be attached to a struct, class, or actor.",
                    line: 1,
                    column: 1
                ),
            ],
            macros: macros
        )
    }

    func testDiagnosesMissingType() {
        // Uses a call expression, not a Bool/Int/String literal, so it isn't
        // one of the three inferable kinds — the genuine missing-type path.
        assertMacroExpansion(
            """
            @Flowable
            public struct Thing {
                public var count = someDefault()
            }
            """,
            expandedSource: """
            public struct Thing {
                public var count = someDefault()
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                    "Stored property 'count' needs an explicit type annotation so @Flowable can generate the initializer/stateless snapshot.",
                    line: 3,
                    column: 16
                ),
            ],
            macros: macros
        )
    }

    func testLiteralDefaultsInferBoolIntAndStringWithNoExplicitAnnotation() {
        // Bool/Int/String are the only literal kinds unambiguous without a
        // type checker — no numeric-defaults-to-Double, no witness
        // resolution.
        assertMacroExpansion(
            """
            @Flowable
            struct Flags {
                var isOn = false
                var count = 0
                var label = "x"
            }
            """,
            expandedSource: """
            struct Flags {
                var isOn = false
                var count = 0
                var label = "x"

                init(isOn: Bool = false, count: Int = 0, label: String = "x") {
                    self.isOn = isOn
                    self.count = count
                    self.label = label
                }

                static func makeFlow(_ flow: (Bool, Int, String)) -> Self {
                    Self(isOn: flow.0, count: flow.1, label: flow.2)
                }

                typealias InFlow = (isOn: Bool, count: Int, label: String)
            }
            """,
            macros: macros
        )
    }

    func testDiagnosesNonPrivateSourceOfTruthWrappers() {
        // Enforced rather than accommodated: downstream renderers assume the
        // source-of-truth set is always private, no "what if it's public"
        // case.
        assertMacroExpansion(
            """
            @Flowable
            struct Card {
                @State var isExpanded = false
            }
            """,
            expandedSource: """
            struct Card {
                @State var isExpanded = false
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                    "'isExpanded' must be private — @State/@FocusState/@AppStorage/@SceneStorage/@Query are a view's own source of truth, not something a caller supplies (use @Binding for that).",
                    line: 3,
                    column: 16
                ),
            ],
            macros: macros
        )
    }
}
