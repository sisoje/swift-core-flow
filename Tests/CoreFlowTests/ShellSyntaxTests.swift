import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import CoreFlowMacros

final class ShellSyntaxTests: XCTestCase {
    let macros: [String: Macro.Type] = ["Shell": ShellMacro.self]

    func testMixOfPlainQueryEnvironmentStateAndBindingFields() {
        // Both rules in one type. @State: Core's own state, the host's line
        // renamed to @TestState. @Environment: verbatim copy,
        // self-initialized by its key-path argument, so it drops out of
        // Core's memberwise init — live environment when hosted, default
        // EnvironmentValues otherwise. Bare-value @QueryCore init:
        // QueryCore.swift.
        assertMacroExpansion(
            """
            @Shell
            struct Card {
                @Query private var items: [Item]
                @Environment(\\.colorScheme) private var colorScheme: ColorScheme
                @State private var isExpanded: Bool = false
                @Binding var isOn: Bool
                let title: String
            }
            """,
            expandedSource: """
                struct Card {
                    @Query private var items: [Item]
                    @Environment(\\.colorScheme) private var colorScheme: ColorScheme
                    @State private var isExpanded: Bool = false
                    @Binding var isOn: Bool
                    let title: String

                    struct Core {
                        @QueryCore var items: [Item]
                        @Environment(\\.colorScheme) private var colorScheme: ColorScheme
                        @TestState private var isExpanded: Bool = false
                        @Binding var isOn: Bool
                        let title: String
                    }
                }
                """,
            macros: macros
        )
    }

    func testFocusStateIsRenamedToTestFocusStateOnCore() {
        // The view's own focus, @State's exact treatment: the host's line
        // with just the wrapper token renamed — still private, sealed out of
        // the memberwise init (the substitute's storage peer
        // self-initializes; @FocusState never carries a default). Hosted
        // behavior stays the live wrapper's — @TestFocusState holds a REAL
        // FocusState peer — with every programmatic write logged.
        assertMacroExpansion(
            """
            @Shell
            struct SearchField {
                @FocusState private var isFocused: Bool
                let title: String
            }
            """,
            expandedSource: """
                struct SearchField {
                    @FocusState private var isFocused: Bool
                    let title: String

                    struct Core {
                        @TestFocusState private var isFocused: Bool
                        let title: String
                    }
                }
                """,
            macros: macros
        )
    }

    func testNonPrivateFocusStateIsDiagnosed() {
        // Focus is a view's own source of truth like @State — the shared
        // privacy invariant covers it now that it's on the whitelist.
        assertMacroExpansion(
            """
            @Shell
            struct SearchField {
                @FocusState var isFocused: Bool
            }
            """,
            expandedSource: """
                struct SearchField {
                    @FocusState var isFocused: Bool
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "'isFocused' must be private — @State/@FocusState/@AppStorage/@SceneStorage/@Query are a view's own source of truth, not something a caller supplies (use @Binding for that).",
                    line: 3, column: 21)
            ],
            macros: macros
        )
    }

    func testGestureStateIsCopiedVerbatimOntoCorePrivateKept() {
        // The reset: closure rides in the copied attribute text — rebuilding
        // from the bare wrapper name would swap it for the default (proved
        // live by TrickyDragCardUITests). Private with a default →
        // self-initializing → no memberwise parameter; each Core starts a
        // fresh gesture at .zero.
        assertMacroExpansion(
            """
            @Shell
            struct Draggable {
                @GestureState(reset: { _, transaction in transaction = Transaction() }) private var dragOffset: CGSize = .zero
                let title: String
            }
            """,
            expandedSource: """
                struct Draggable {
                    @GestureState(reset: { _, transaction in transaction = Transaction() }) private var dragOffset: CGSize = .zero
                    let title: String

                    struct Core {
                        @GestureState(reset: { _, transaction in
                            transaction = Transaction()
                        }) private var dragOffset: CGSize = .zero
                        let title: String
                    }
                }
                """,
            macros: macros
        )
    }

    func testAWrapperThisPackageHasNeverHeardOfIsCopiedVerbatimToo() {
        // Anything off the whitelist — @StateObject, a custom wrapper, a
        // future SwiftUI one — gets the identical verbatim treatment:
        // arguments, access, and default included, no refusal diagnostic.
        // Private → sealed, out of the memberwise init; non-private
        // (@Whatever) → a parameter of the wrapper's own type. Plain fields
        // keep their default, so the parameter comes defaulted.
        assertMacroExpansion(
            """
            @Shell
            struct Exotic {
                @StateObject private var vm: VM = VM()
                @Whatever(flavor: .spicy) var knob: Int = 7
                var flavor = "mild"
                let title: String
            }
            """,
            expandedSource: """
                struct Exotic {
                    @StateObject private var vm: VM = VM()
                    @Whatever(flavor: .spicy) var knob: Int = 7
                    var flavor = "mild"
                    let title: String

                    struct Core {
                        @StateObject private var vm: VM = VM()
                        @Whatever(flavor: .spicy) var knob: Int = 7
                        var flavor = "mild"
                        let title: String
                    }
                }
                """,
            macros: macros
        )
    }

    func testAccessibilityFocusStateStaysAnUnmappedVerbatimCopy() {
        // An exact @FocusState clone (verified directly against the real
        // SwiftUI interface), but deliberately NOT whitelisted alongside it —
        // no substitute macro yet, so it rides rule 2: private verbatim
        // copy, sealed, out of the memberwise init.
        assertMacroExpansion(
            """
            @Shell
            struct SearchField {
                @AccessibilityFocusState private var a11yFocused: Bool
                let title: String
            }
            """,
            expandedSource: """
                struct SearchField {
                    @AccessibilityFocusState private var a11yFocused: Bool
                    let title: String

                    struct Core {
                        @AccessibilityFocusState private var a11yFocused: Bool
                        let title: String
                    }
                }
                """,
            macros: macros
        )
    }

    func testScaledMetricIsUnmappedSoItIsCopiedVerbatim() {
        // The verbatim copy carries the BASE value plus any relativeTo:
        // argument — Core's copy scales its own base itself, exactly like
        // the host, so nothing double-scales.
        assertMacroExpansion(
            """
            @Shell
            struct IconRow {
                @ScaledMetric private var iconSize: CGFloat = 24
                let title: String
            }
            """,
            expandedSource: """
                struct IconRow {
                    @ScaledMetric private var iconSize: CGFloat = 24
                    let title: String

                    struct Core {
                        @ScaledMetric private var iconSize: CGFloat = 24
                        let title: String
                    }
                }
                """,
            macros: macros
        )
    }

    func testSceneStorageFoldsIntoTheSameBindingSubstitutionAsAppStorage() {
        // External storage is a dependency, injected as @Binding, the mock
        // vehicle — same shape as @AppStorage (settable wrappedValue,
        // Binding projection — verified directly), one case for both. The
        // key is dropped: a test twin doesn't persist.
        assertMacroExpansion(
            """
            @Shell
            struct SearchField {
                @SceneStorage("isPinned") private var isPinned: Bool = false
                let title: String
            }
            """,
            expandedSource: """
                struct SearchField {
                    @SceneStorage("isPinned") private var isPinned: Bool = false
                    let title: String

                    struct Core {
                        @Binding var isPinned: Bool
                        let title: String
                    }
                }
                """,
            macros: macros
        )
    }

    func testNamespaceIsUnmappedSoItIsCopiedVerbatim() {
        // Core mints its own namespace — self-initialized via the wrapper's
        // init(), out of the memberwise init. And @Namespace alone needs no
        // type annotation: exactly one possible wrapped type, filled in as
        // `Namespace.ID` by the collection.
        assertMacroExpansion(
            """
            @Shell
            struct HeroCard {
                @Namespace private var ns
                let title: String
            }
            """,
            expandedSource: """
                struct HeroCard {
                    @Namespace private var ns
                    let title: String

                    struct Core {
                        @Namespace private var ns
                        let title: String
                    }
                }
                """,
            macros: macros
        )
    }

    func testWrapperSpelledWithAQualifiedNameIsStillCopiedVerbatim() {
        // The verbatim rule keys on "carries attributes", not "carries a
        // recognized wrapper name": a qualified spelling has no bare
        // identifier for `propertyWrapperName` to report, and must still
        // ride along byte-for-byte rather than be stripped to a plain field.
        assertMacroExpansion(
            """
            @Shell
            struct Card {
                @MyModule.Tracked var count = 0
                let title: String
            }
            """,
            expandedSource: """
                struct Card {
                    @MyModule.Tracked var count = 0
                    let title: String

                    struct Core {
                        @MyModule.Tracked var count = 0
                        let title: String
                    }
                }
                """,
            macros: macros
        )
    }

    func testPrivateQualifiedWrapperIsNotMistakenForPlainPrivateState() {
        // The plain-private lint keys on "no attributes at all": a qualified
        // spelling reports no bare wrapper name yet IS a wrapper — sealed
        // verbatim copy, not a refusal.
        assertMacroExpansion(
            """
            @Shell
            struct Card {
                @MyModule.Tracked private var count = 0
                let title: String
            }
            """,
            expandedSource: """
                struct Card {
                    @MyModule.Tracked private var count = 0
                    let title: String

                    struct Core {
                        @MyModule.Tracked private var count = 0
                        let title: String
                    }
                }
                """,
            macros: macros
        )
    }

    func testPublicIsErasedAndLetIsKeptOnVerbatimCopies() {
        // Access never reaches Core — `public` is erased by not copying
        // modifiers — while the host's own `let`/`var` and default ride
        // along, so a defaulted `let` stays a constant on Core exactly as on
        // the host.
        assertMacroExpansion(
            """
            @Shell
            public struct Card {
                public let title: String = "x"
                public var subtitle: String
            }
            """,
            expandedSource: """
                public struct Card {
                    public let title: String = "x"
                    public var subtitle: String

                    struct Core {
                        let title: String = "x"
                        var subtitle: String
                    }
                }
                """,
            macros: macros
        )
    }

    func testZeroEligibleFieldsStillGeneratesAnEmptyCoreStruct() {
        // Zero eligible fields means zero stored properties at all — a
        // private property with no wrapper is a compile error, never a
        // silent fallthrough.
        assertMacroExpansion(
            """
            @Shell
            struct Empty {}
            """,
            expandedSource: """
                struct Empty {

                    struct Core {

                    }
                }
                """,
            macros: macros
        )
    }

    func testPlainViewBuilderAndUnmappedNonPrivateFieldsStayInTheInit() {
        // @ViewBuilder is copied untouched on both forms, `let` included —
        // an attribute like any other, so Core keeps the host's own
        // declaration. On the stored-value form (footer) that means Core's
        // synthesized init takes a builder closure rather than a bare value
        // (verified directly), matching the host's call shape. @Bindable:
        // unmapped, non-private → an ordinary memberwise parameter.
        assertMacroExpansion(
            """
            @Shell
            struct ProfileCard<Content: View> {
                var subtitle: String?
                @Bindable var model: Settings
                @ViewBuilder let content: () -> Content
                @ViewBuilder let footer: Content
            }
            """,
            expandedSource: """
                struct ProfileCard<Content: View> {
                    var subtitle: String?
                    @Bindable var model: Settings
                    @ViewBuilder let content: () -> Content
                    @ViewBuilder let footer: Content

                    struct Core {
                        var subtitle: String?
                        @Bindable var model: Settings
                        @ViewBuilder let content: () -> Content
                        @ViewBuilder let footer: Content
                    }
                }
                """,
            macros: macros
        )
    }

    func testNonPrivateSourceOfTruthIsDiagnosedUnderShellToo() {
        // The shared collection enforces the privacy invariant for @Shell
        // exactly as for @Flowable — a non-private SOT is never accommodated.
        assertMacroExpansion(
            """
            @Shell
            struct Card {
                @State var isOn: Bool = false
            }
            """,
            expandedSource: """
                struct Card {
                    @State var isOn: Bool = false
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "'isOn' must be private — @State/@FocusState/@AppStorage/@SceneStorage/@Query are a view's own source of truth, not something a caller supplies (use @Binding for that).",
                    line: 3, column: 16)
            ],
            macros: macros
        )
    }

    func testStateWithoutAnInlineDefaultIsDiagnosed() {
        // Core re-declares @State as @TestState with the host's default
        // copied — nothing to copy is diagnosed, never silently patched.
        assertMacroExpansion(
            """
            @Shell
            struct Card {
                @State private var selection: Int?
            }
            """,
            expandedSource: """
                struct Card {
                    @State private var selection: Int?
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "'selection' needs an inline default — @Shell re-declares @State as @TestState on Core and copies the default.",
                    line: 3, column: 24)
            ],
            macros: macros
        )
    }

    func testViewBuilderDeclaredVarIsDiagnosed() {
        // @ViewBuilder content is caller-supplied and never reassigned —
        // `var` is a compile error, not accommodated.
        assertMacroExpansion(
            """
            @Shell
            struct ProfileCard<Content: View> {
                @ViewBuilder var footer: Content
            }
            """,
            expandedSource: """
                struct ProfileCard<Content: View> {
                    @ViewBuilder var footer: Content
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "'footer' must be a `let` — @ViewBuilder content is caller-supplied through @Shell's generated init and never reassigned.",
                    line: 3, column: 22)
            ],
            macros: macros
        )
    }

    func testBodyIsCopiedIntoCoreVerbatim() {
        // The copy is legal (same expansion — only cross-expansion name
        // references are forbidden) and compiles on both types by
        // read-surface parity: one source text, two types.
        assertMacroExpansion(
            """
            @Shell
            struct Card: View {
                @State private var count: Int = 0
                var body: some View {
                    Text("\\(count)")
                }
            }
            """,
            expandedSource: """
                struct Card: View {
                    @State private var count: Int = 0
                    var body: some View {
                        Text("\\(count)")
                    }

                    struct Core: View {
                        @TestState private var count: Int = 0

                        var body: some View {
                            Text("\\(count)")
                        }
                    }
                }
                """,
            macros: macros
        )
    }

    func testBodyContentIsCopiedIntoCoreForViewModifierHosts() {
        // `Content` in the copied body(content:) resolves to Core's OWN
        // ViewModifier.Content — a different concrete type than the host's,
        // fine: each satisfies the protocol independently (verified
        // directly).
        assertMacroExpansion(
            """
            @Shell
            struct Dimmed: ViewModifier {
                @State private var level: Double = 0.5
                func body(content: Content) -> some View {
                    content.opacity(level)
                }
            }
            """,
            expandedSource: """
                struct Dimmed: ViewModifier {
                    @State private var level: Double = 0.5
                    func body(content: Content) -> some View {
                        content.opacity(level)
                    }

                    struct Core: ViewModifier {
                        @TestState private var level: Double = 0.5

                        func body(content: Content) -> some View {
                            content.opacity(level)
                        }
                    }
                }
                """,
            macros: macros
        )
    }

    func testHelpersStaticMembersAndNestedTypesAreCopiedButInitsAreNot() {
        // Static stored members copy too — a body referencing `spacing`
        // unqualified needs Core's own. Inits are the one exclusion: a
        // copied init would suppress the synthesized memberwise init.
        assertMacroExpansion(
            """
            @Shell
            struct Card: View {
                @State private var count: Int = 0
                static let spacing: CGFloat = 8
                enum Kind {
                    case a
                }
                init(seed: Int) {
                    count = seed
                }
                var doubled: Int {
                    count * 2
                }
                func label() -> String {
                    "\\(doubled)"
                }
                var body: some View {
                    Text(label())
                }
            }
            """,
            expandedSource: """
                struct Card: View {
                    @State private var count: Int = 0
                    static let spacing: CGFloat = 8
                    enum Kind {
                        case a
                    }
                    init(seed: Int) {
                        count = seed
                    }
                    var doubled: Int {
                        count * 2
                    }
                    func label() -> String {
                        "\\(doubled)"
                    }
                    var body: some View {
                        Text(label())
                    }

                    struct Core: View {
                        @TestState private var count: Int = 0

                        static let spacing: CGFloat = 8

                        enum Kind {
                            case a
                        }

                        var doubled: Int {
                            count * 2
                        }

                        func label() -> String {
                            "\\(doubled)"
                        }

                        var body: some View {
                            Text(label())
                        }
                    }
                }
                """,
            macros: macros
        )
    }

    func testConformanceDeclaredInASeparateExtensionIsNotDetected() {
        // Conformance in a separate extension is invisible to syntax-only
        // detection — documented limitation: no `: View` on Core.
        assertMacroExpansion(
            """
            @Shell
            struct Card {
                let title: String
            }
            """,
            expandedSource: """
                struct Card {
                    let title: String

                    struct Core {
                        let title: String
                    }
                }
                """,
            macros: macros
        )
    }

    func testCoreIsAlwaysInternalRegardlessOfTheStructsAccess() {
        assertMacroExpansion(
            """
            @Shell
            public struct Point {
                var x: Int
                var y: Int
            }
            """,
            expandedSource: """
                public struct Point {
                    var x: Int
                    var y: Int

                    struct Core {
                        var x: Int
                        var y: Int
                    }
                }
                """,
            macros: macros
        )
    }
}
