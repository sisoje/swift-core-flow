import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import CoreFlowMacros

final class ShellSyntaxTests: XCTestCase {
    let macros: [String: Macro.Type] = ["Shell": ShellMacro.self]

    func testMixOfPlainQueryEnvironmentStateAndBindingFields() {
        // All three rules in one type. @Environment: verbatim copy,
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
                        @Binding var isExpanded: Bool
                        @Binding var isOn: Bool
                        let title: String
                    }
                }
                """,
            macros: macros
        )
    }

    func testFocusStateIsUnmappedSoItIsCopiedVerbatim() {
        // Deliberately unmapped — a stand-in would be a pass-through, not a
        // mock (no public initializer on FocusState<T>.Binding; writes no-op
        // outside a live view — both verified directly). Private verbatim
        // copy: sealed, out of the memberwise init.
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
                        let title: String
                    }
                }
                """,
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
                        var flavor: String = "mild"
                        let title: String
                    }
                }
                """,
            macros: macros
        )
    }

    func testAccessibilityFocusStateGetsFocusStatesExactTreatment() {
        // An exact @FocusState clone (verified directly against the real
        // SwiftUI interface) — identical unmapped treatment.
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
        // Shares @State/@AppStorage's exact shape (settable wrappedValue,
        // projectedValue genuinely Binding<T> — verified directly), hence
        // the same substitution with no separate case.
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
                        @Namespace private var ns: Namespace.ID
                        let title: String
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
        // @ViewBuilder survives only on the stored-closure form (content);
        // on the stored-value form (footer) it would force the synthesized
        // init to wrap the parameter in a builder closure to no benefit
        // (verified directly). @Bindable: unmapped, non-private → an
        // ordinary memberwise parameter.
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
