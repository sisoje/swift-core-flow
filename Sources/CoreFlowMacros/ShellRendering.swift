import SwiftSyntax

/// `Core` — the host's standalone twin: every collected stored property
/// (collection already refused anything unrenderable —
/// `plainPrivatePropertyNotAllowed`, `StoredProperty.swift`) plus a verbatim
/// copy of every non-stored member. Two field rules — substitute the
/// whitelist, copy everything else verbatim — each documented at its
/// branch below.
///
/// `Core` is always internal, regardless of the host's access — a
/// testing/preview seam, not API surface. Field access follows the branch:
/// the `@State` substitution stays private (the view's own SOT), the other
/// mapped fields are internal, verbatim copies keep their own access
/// (`public` erased). No init is generated or
/// copied — a copied init would suppress the synthesized memberwise init,
/// the only way tests construct a `Core`, and synthesis already reproduces
/// every field-specific behavior (verified directly: a wrapper without
/// `init(wrappedValue:)` (`@Binding`) synthesizes a parameter of the
/// *wrapper's* type, one with it (`@QueryResult`, `@Bindable`) of the
/// *wrapped* type, `@ViewBuilder` on a stored `let` a real builder
/// parameter). Deliberately no `core` capture property off the live host —
/// a unit test never has one — and no generated binding mocks: that small,
/// situational code belongs at the use site, shaped by the test (see
/// `ShellTests`).
func renderShell(
    properties: [StoredProperty], hostKind: ShellHostKind = .none,
    copiedMembers: [String] = []
) -> [DeclSyntax] {
    let fieldDecls = properties.map { p -> String in
        // Rule 1 — the whitelist (`isSubstitutedOnCore`): the source-of-truth
        // set becomes test-suppliable stand-ins (@State's stand-in is a
        // renamed verbatim copy — rule 2). @AppStorage/@SceneStorage are
        // external storage, injected as @Binding — each one's projectedValue
        // genuinely IS Binding<T> (verified directly), so a test-supplied
        // Binding(get:set:) captures every write the copied body makes.
        // @Query → @QueryResult, whose extra fields default so the memberwise
        // init takes the bare fetched value: `Core(items: [item], …)`.
        // @FocusState — like @State, the view's own — is a renamed verbatim
        // copy (rule 2 below): @TestFocusState holds a REAL FocusState peer
        // (no mock exists: FocusState<T>.Binding has no public initializer,
        // verified directly), so hosted behavior stays live and every
        // programmatic write logs. @AccessibilityFocusState is deliberately
        // NOT here — same shape, no substitute macro yet; verbatim copy.
        if p.isExternalStorage {
            return "@Binding var \(p.name): \(p.type?.trimmedDescription ?? "")"
        }
        if p.isQuery {
            return "@QueryResult var \(p.name): \(p.type?.trimmedDescription ?? "")"
        }
        // Rule 2 — everything else, wrapper or not, @ViewBuilder included:
        // the host's own declaration re-rendered as written, `public` erased
        // (Core is internal). `private` stays — a private
        // wrapper copy is self-initializing and sealed out of the memberwise
        // init; erasing it would resurface the field as a wrapper-typed
        // parameter. Attribute arguments (a @GestureState(reset:) closure)
        // ride along byte-for-byte — rebuilding from the wrapper name would
        // swap them out (proved live by TrickyDragCardUITests).
        if p.isPrivate {
            assert(!p.varDecl.attributes.isEmpty, "plain private fields are refused at collection")
        }
        var copy = p.varDecl
        // @State/@FocusState — the view's OWN state/focus — copy with just
        // the wrapper renamed: @TestState (still private and defaulted) /
        // @TestFocusState (still private, no default — @FocusState can't
        // carry one), logging every programmatic mutation.
        if p.isOwnState || p.isFocusState {
            assert(p.isPrivate, "collection refuses non-private @State/@FocusState")
            let (from, to) =
                p.isOwnState ? ("State", "TestState") : ("FocusState", "TestFocusState")
            copy.attributes = AttributeListSyntax(
                copy.attributes.map { element in
                    guard case var .attribute(a) = element,
                          a.attributeName.trimmedDescription == from
                    else { return element }
                    a.attributeName = TypeSyntax(stringLiteral: to)
                        .with(\.trailingTrivia, a.attributeName.trailingTrivia)
                    return .attribute(a)
                }
            )
        }
        copy.modifiers = copy.modifiers.filter {
            $0.name.tokenKind != .keyword(.public)
        }
        copy.bindings = PatternBindingListSyntax([p.binding.with(\.trailingComma, nil)])
        return copy.trimmedDescription
    }.joined(separator: "\n")

    let conformance: String
    switch hostKind {
    case .view: conformance = ": View"
    case .viewModifier: conformance = ": ViewModifier"
    case .none: conformance = ""
    }

    let copies = copiedMembers.map { "\n\n\($0)" }.joined()
    let statelessStruct = DeclSyntax(
        stringLiteral: """
        struct Core\(conformance) {
        \(fieldDecls)\(copies)
        }
        """
    )

    return [statelessStruct]
}
