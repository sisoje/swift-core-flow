import SwiftSyntax

/// Renders `@Shell`'s one generated member — a nested `Core` struct — over
/// every collected stored property (nothing reaching here needs filtering: a
/// private property with no wrapper is refused by `collectStoredProperties`
/// — `plainPrivatePropertyNotAllowed`, `StoredProperty.swift` — and
/// everything else is legal by construction), followed by a verbatim copy
/// of every non-stored host member (`copiedMembers` — computed by
/// `copiedMemberSources` in `ShellMacro.swift`, `body` included). The host
/// stays a completely ordinary SwiftUI view; `Core` is its standalone twin,
/// constructed directly in tests/previews via Swift's own synthesized
/// memberwise init — which is also why `@Shell` copies no initializers: a
/// copied init would suppress that synthesis.
///
/// The transform rules, all three of them:
///
/// **Rule 1 — no wrapper** (plain `let`/`var`): `let|var name: T
/// [= default]` — specifier and initial value kept (a `var` default makes
/// its memberwise parameter defaulted; a `let` with a default is a constant
/// and drops out of the memberwise init, exactly like on the host);
/// `public` is stripped (a private plain field is already a diagnostic,
/// `plainPrivatePropertyNotAllowed`).
///
/// **Rule 2 — the whitelist** (`isSubstitutedOnCore`,
/// `StoredProperty.swift` — the only wrappers this macro really knows, all
/// required private): each is substituted with a stand-in that buys a REAL
/// mock:
/// - `@State`/`@AppStorage`/`@SceneStorage` → `@Binding var name: T` — a
///   test-supplied `Binding(get:set:)` captures every write the copied body
///   makes (all three share this case because each one's `projectedValue`
///   genuinely *is* `Binding<T>` — verified directly against the real
///   SwiftUI interface).
/// - `@Query` → `@QueryCore var name: T` — this package's own drop-in
///   stand-in (see `QueryCore.swift`), whitelisted for the practical reason
///   that reading a fetched array shouldn't require a SwiftData stack. Its
///   extra fields default, so `Core`'s synthesized memberwise init takes the
///   *bare* fetched value — `Core(items: [item], …)`, no `QueryCore`
///   spelling at a test's call site.
/// - (`@ViewBuilder` — not a property wrapper, a result-builder attribute —
///   rides along as init machinery: the stored-closure form keeps the
///   attribute for real builder syntax at `Core`'s init call site, the
///   stored-value form drops it — keeping it would make the synthesized
///   init wrap the parameter in a builder closure to no benefit, verified
///   directly.)
///
/// `@FocusState`/`@AccessibilityFocusState` were once whitelisted
/// (substituted with their own `.Binding` projections) and got cut: those
/// projections have no public initializer — a test can't back one with its
/// own closures — and their writes no-op outside a live view anyway
/// (verified directly), so the substitution was
/// a pass-through pretending to be a mock. As rule-3 verbatim copies they
/// behave identically when hosted.
///
/// **Rule 3 — any other wrapper**, `@Binding` included (it needs no case of
/// its own — the verbatim copy of `@Binding var x: T` already *is* the mock
/// vehicle): the whole declaration is copied onto `Core` verbatim —
/// attribute (arguments included), default value, and `private` kept,
/// `public` erased. Whatever behavior lives in the attribute's own arguments
/// (a `reset:` closure, a key path, a `relativeTo:`) rides along
/// byte-for-byte with nothing to reconstruct — proved live by
/// TrickyDragCardUITests in the ExampleApp: an earlier design reconstructing
/// `@GestureState var` from just the bare wrapper name silently swapped a
/// custom reset closure for the default one; the verbatim copy keeps it.
/// A *private* copy is self-initializing by construction (the host compiled
/// without an init assigning it), so it drops out of `Core`'s memberwise
/// init and produces its value live instead — an `@Environment` copy reads
/// the real environment reactively when `Core` is hosted (mock it there via
/// `.environment(...)`, the wrapper's own native story) and the default
/// `EnvironmentValues` outside a live view; a `@GestureState` copy starts a
/// fresh gesture at its declared default. A *non-private* copy stays a
/// memberwise parameter of the wrapper's own type.
///
/// Rule-1 fields keep the host's own `let`/`var`; wrapped fields are `var`
/// (wrappers require it); private verbatim copies are sealed — not init
/// parameters, not readable, not mocked, they just behave. Mocking happens
/// at construction, through hand-built `Binding(get:set:)`/`.constant`
/// values or a hand-written `@Observable` model whose `Bindable(model).x`
/// projections wire in — deliberately NOT generated here. An earlier revision emitted a `CoreModel` class plus a
/// `static make(model:...)` wiring constructor; both were cut in favor of
/// writing that (small, situational) code at the use site — the macro's job
/// ends at the mockable twin itself.
///
/// `Core` is always internal — the struct itself and every mapped field —
/// regardless of the attached type's own access level (verbatim-copied
/// fields keep whatever access they had, `private` included), and it carries
/// no `@Flowable`. It's a testing/preview seam, not API surface: consumers
/// of a public host never need the twin, only the module's own tests do.
/// Swift's memberwise-init synthesis reproduces every field-specific
/// behavior a hand-rolled init would — verified directly: a property-wrapper
/// field with no `init(wrappedValue:)` (`@Binding`) synthesizes a parameter
/// of the *wrapper's* type, one that does (`@Query` via `@QueryCore`,
/// `@Bindable`) synthesizes a parameter of the *wrapped* type, and
/// `@ViewBuilder` directly on a stored `let` synthesizes a real builder
/// parameter.
func renderShell(
    properties: [StoredProperty], hostKind: ShellHostKind = .none,
    copiedMembers: [String] = []
) -> [DeclSyntax] {
    let fields = properties

    // Every field is internal — never `access` — regardless of the attached
    // type's own access level, except verbatim-copied private wrappers,
    // which keep their `private`; see this file's own doc comment.
    let fieldDecls = fields.map { p -> String in
        // Rule 2 — the whitelist (`isSubstitutedOnCore`, `StoredProperty.swift`):
        // mutation-carrying wrappers become binding-shaped stand-ins a test
        // can mock to capture every write, and @Query becomes @QueryCore so
        // reading a fetched array needs no SwiftData stack.
        if p.isBindingBackedStorage {
            return "@Binding var \(p.name): \(p.type?.trimmedDescription ?? "")"
        }
        if p.isQuery {
            return "@QueryCore var \(p.name): \(p.type?.trimmedDescription ?? "")"
        }
        // @ViewBuilder isn't a property wrapper (no backing storage): the
        // stored-closure form keeps the attribute (real builder syntax at
        // Core's init call site), the stored-value form drops it (keeping it
        // would make the synthesized init wrap the parameter in a builder
        // closure to no benefit — verified directly).
        if p.isViewBuilder {
            let type = p.type?.trimmedDescription ?? ""
            let isStoredValue = !(p.type.map(isFunctionType) ?? false)
            return isStoredValue
                ? "var \(p.name): \(type)"
                : "@ViewBuilder var \(p.name): \(type)"
        }
        // Rule 1 — plain let/var, specifier preserved (the host's own choice —
        // a `let` stays a constant on Core too; forcing `var` was a relic of
        // the deleted post-construction instance-swapping design), initial
        // value kept, access stripped (a private plain field is already a
        // diagnostic, `plainPrivatePropertyNotAllowed`). Note Swift's own
        // memberwise rules apply: a `let` WITH a default is a constant and
        // drops out of Core's memberwise init — not overridable by a test,
        // exactly like on the host.
        guard let attributeText = p.attributeText else {
            let def = p.defaultValue.map { " = \($0.trimmedDescription)" } ?? ""
            let spec = p.isLet ? "let" : "var"
            return "\(spec) \(p.name): \(p.type?.trimmedDescription ?? "")\(def)"
        }
        // Rule 3 — ANY other wrapper (@Binding included — it fits here with
        // no case of its own): copied onto Core verbatim — attribute
        // (arguments included), `private` kept, `public` erased, default
        // value kept. Whatever behavior lives in the attribute's own
        // arguments (a @GestureState reset closure, an @Environment key
        // path, a @ScaledMetric relativeTo:) rides along byte-for-byte with
        // nothing to reconstruct. A private copy is self-initializing by
        // construction (the host compiled without an init assigning it), so
        // it drops out of Core's memberwise init — verified directly for the
        // wrapper-argument (@Environment), inline-default (@GestureState),
        // and wrapper-init() (@Namespace) forms alike; a non-private copy
        // stays a memberwise parameter of the wrapper's own type.
        let access = p.isPrivate ? "private " : ""
        let type = p.type.map { ": \($0.trimmedDescription)" } ?? ""
        let def = p.defaultValue.map { " = \($0.trimmedDescription)" } ?? ""
        return "\(attributeText) \(access)var \(p.name)\(type)\(def)"
    }.joined(separator: "\n")

    let conformance: String
    switch hostKind {
    case .view: conformance = ": View"
    case .viewModifier: conformance = ": ViewModifier"
    case .none: conformance = ""
    }

    // The host's non-stored members, copied verbatim — legal because this is
    // the same expansion that declares Core's fields, and the identifiers
    // inside resolve against them by the one-to-one read-surface design (see
    // this function's doc comment).
    let copies = copiedMembers.map { "\n\n\($0)" }.joined()
    let statelessStruct = DeclSyntax(
        stringLiteral: """
            struct Core\(conformance) {
            \(fieldDecls)\(copies)
            }
            """
    )

    // No `core` capture property — an earlier revision generated
    // `var core: Core { Core(...) }` off the live host, and with it came a
    // whole per-rule capture-expression mapping ($x vs _x vs skip-private).
    // Deleted: Core is for testing, tests construct it directly through the
    // memberwise init, and a unit test never has a live host to capture from
    // in the first place. Same fate for the generated `CoreModel` +
    // `static make(model:...)` pair: mocking bindings is use-site code now,
    // hand-written where it's needed (see ShellTests/the ExampleApp).

    return [statelessStruct]
}
