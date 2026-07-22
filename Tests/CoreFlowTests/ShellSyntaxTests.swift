import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import CoreFlowMacros

final class ShellSyntaxTests: XCTestCase {
    let macros: [String: Macro.Type] = ["Shell": ShellMacro.self]

    func testMixOfPlainQueryEnvironmentStateAndBindingFields() {
        // @Query's capture passes the bare fetched value (_items.wrappedValue),
        // not a constructed QueryCore: with fetchError/modelContext both
        // defaulted, QueryCore's init is callable with the wrapped value alone,
        // so Core's synthesized memberwise init takes the bare value — tests
        // write `Core(items: [item], ...)` with no QueryCore spelling at all.
        // @Environment is copied verbatim (key-path argument and `private`
        // kept, like @GestureState): initialized by its own attribute
        // arguments, it drops out of Core's memberwise init, so the capture
        // omits it — Core reads the live environment when hosted, the default
        // EnvironmentValues otherwise.
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
                        @Binding var isExpanded: Bool
                        @Binding var isOn: Bool
                        var title: String
                    }
                }
                """,
            macros: macros
        )
    }

    func testFocusStateIsUnmappedSoItIsCopiedVerbatim() {
        // @FocusState was once whitelisted (substituted with its own
        // FocusState<T>.Binding projection) and got cut: that projection has
        // no public initializer — a test can't back it with its own closures
        // — and its writes no-op outside a live view anyway (verified
        // directly), so the substitution was a pass-through pretending to be
        // a mock. Unmapped now: copied verbatim, private kept, dropped from
        // the memberwise init (FocusState self-initializes via its own
        // init()) — sealed, like every private verbatim copy.
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
                        @FocusState private var isFocused: Bool
                        var title: String
                    }
                }
                """,
            macros: macros
        )
    }

    func testGestureStateIsCopiedVerbatimOntoCorePrivateKept() {
        // @GestureState isn't on the mapping whitelist — unknown, used as-is:
        // its whole declaration — attribute (with reset: arguments), default,
        // and `private` — is copied onto Core byte-for-byte, not substituted
        // with a stand-in type. The reset closure lives in the copied
        // attribute text, so it carries over with nothing to reconstruct (an
        // earlier design that reconstructed a fresh @GestureState var from
        // the bare wrapper name silently swapped it for the default reset,
        // proved live by TrickyDragCardUITests). Because the field stays
        // private with a default, it drops out of Core's memberwise init — so
        // `core` omits dragOffset entirely (it starts fresh at .zero).
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
                        var title: String
                    }
                }
                """,
            macros: macros
        )
    }

    func testAWrapperThisPackageHasNeverHeardOfIsCopiedVerbatimToo() {
        // The whole point of the whitelist design: anything not on it —
        // @StateObject, a future SwiftUI wrapper, a custom one — is unknown
        // and gets the identical verbatim-copy treatment (arguments, access
        // modifier, and default included). No refusal diagnostic (an earlier
        // revision rejected unrecognized private wrappers outright). A
        // private one drops out of Core's memberwise init, sealed, no raw_;
        // a non-private one stays a parameter of the wrapper's own type,
        // captured as its backing instance `_x`, with stamped
        // (raw_ goes on non-private wrapper fields only). Plain fields keep
        // their initial value too (`flavor` below), so their memberwise
        // parameter comes defaulted.
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
                        var flavor: String = "mild"
                        var title: String
                    }
                }
                """,
            macros: macros
        )
    }

    func testAccessibilityFocusStateGetsFocusStatesExactTreatment() {
        // An exact @FocusState clone (verified directly against the real
        // SwiftUI interface), so it gets the identical unmapped treatment:
        // copied verbatim, private kept, dropped from the memberwise init.
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
                        var title: String
                    }
                }
                """,
            macros: macros
        )
    }

    func testScaledMetricIsUnmappedSoItIsCopiedVerbatim() {
        // @ScaledMetric isn't on the mapping whitelist — unknown, copied onto
        // Core verbatim with its BASE value and any relativeTo: argument
        // riding along in the attribute text. No double-scaling here, unlike
        // the old capture-the-scaled-value design would have hit if it had
        // redeclared the wrapper from the bare name: Core's copy scales its
        // own base value itself, exactly like the host.
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
                        var title: String
                    }
                }
                """,
            macros: macros
        )
    }

    func testSceneStorageFoldsIntoTheSameBindingSubstitutionAsAppStorage() {
        // @SceneStorage shares @State/@AppStorage's exact shape (settable
        // wrappedValue, projectedValue genuinely Binding<T> — verified directly
        // against the real SwiftUI interface), so it gets the same @Binding var
        // substitution, no separate case needed unlike @FocusState.
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
                        var title: String
                    }
                }
                """,
            macros: macros
        )
    }

    func testNamespaceIsUnmappedSoItIsCopiedVerbatim() {
        // @Namespace isn't on the mapping whitelist, so it's unknown to
        // @Shell and copied onto Core verbatim, `private` kept — Core mints
        // its own namespace, self-initialized by the wrapper's own init(), so
        // the field drops out of Core's memberwise init and the capture
        // omits it (verified directly that a self-initializing private
        // wrapper keeps the memberwise init internal). The one @Namespace
        // nicety that DOES survive: it needs no explicit type annotation —
        // it has exactly one possible wrapped type (`Namespace.ID`), so the
        // collection fills that in rather than diagnosing a missing type.
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
                        @Namespace private var ns: Namespace.ID
                        var title: String
                    }
                }
                """,
            macros: macros
        )
    }

    func testZeroEligibleFieldsStillGeneratesAnEmptyCoreStruct() {
        // No plain private fallthrough field here — a private property with no
        // recognized wrapper is a compile error now (see
        // testDiagnosesPlainPrivatePropertyWithNoWrapper), so zero eligible fields
        // means zero stored properties at all.
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
        // @ViewBuilder is kept only for the stored-closure form (content) —
        // its field type is already a closure, so the attribute is pure upside.
        // For the stored-value form (footer), keeping it would force Swift's
        // synthesized init to wrap the parameter in a builder closure purely to
        // satisfy the attribute (verified directly) — dropped entirely instead,
        // so footer stays a plain field, passed straight through with no
        // wrapping on either side. @Bindable is unmapped — copied verbatim
        // (no @RawProperty, nothing to mock) — and being non-private it stays
        // a memberwise-init parameter like any other non-private field.
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
                        @ViewBuilder var content: () -> Content
                        var footer: Content
                    }
                }
                """,
            macros: macros
        )
    }

    func testBodyIsCopiedIntoCoreVerbatim() {
        // The host writes a completely normal SwiftUI body; @Shell copies it
        // verbatim into Core (same expansion — referencing its own generated
        // fields is legal; only cross-expansion references are forbidden), and
        // Core's `: View` conformance is satisfied by the copy. One source
        // text serves both types: the identifiers resolve against the host's
        // real wrappers on one side and Core's substituted fields on the
        // other, by the one-to-one read-surface design.
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
                        @Binding var count: Int

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
        // Same copy for the ViewModifier shape: `Content` inside the copied
        // body(content:) resolves to Core's own ViewModifier.Content — a
        // different concrete type from the host's (each is keyed on its own
        // conforming type — verified directly), which is fine: each type
        // satisfies the protocol independently.
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
                        @Binding var level: Double

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
        // Every non-stored member rides along into Core — helper computed
        // properties, methods, static members (static stored included: a body
        // referencing `spacing` unqualified needs Core to carry its own copy),
        // nested types — so the copied body's helpers resolve without a
        // separate extension. Initializers are the one exception: Core is
        // constructed through Swift's synthesized memberwise init (in tests,
        // with mocks), and a copied init would suppress that synthesis.
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
                        @Binding var count: Int

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
        // Syntax-only detection reads the attached declaration's own inheritance
        // clause — conformance added elsewhere (a separate `extension Card: View`)
        // is invisible to it, since macros never get a type checker. Documented
        // limitation, not a bug: no `: View` on Core.
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
                        var title: String
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
