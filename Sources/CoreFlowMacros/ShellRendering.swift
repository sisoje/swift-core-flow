import SwiftSyntax

/// Renders `@Shell`'s one generated member — a nested `Core` struct — over
/// exactly `OutFlow`'s field set (`outFlowProperties`, reused directly — see
/// its doc comment in `FlowableRendering.swift`), followed by a verbatim copy
/// of every non-stored host member (`copiedMembers` — computed by
/// `copiedMemberSources` in `ShellMacro.swift`, `body` included). The host
/// stays a completely ordinary SwiftUI view; `Core` is its standalone twin,
/// constructed directly in tests/previews via Swift's own synthesized
/// memberwise init — which is also why `@Shell` copies no initializers: a
/// copied init would suppress that synthesis.
///
/// The transform rules, all three of them:
///
/// **Rule 1 — no wrapper** (plain `let`/`var`): `var name: T [= default]` —
/// the initial value is kept, so the memberwise parameter comes defaulted;
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
/// (verified directly, `OutFlowTests`' old caveat), so the substitution was
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
/// **`@RawProperty` goes on every NON-private wrapper field of `Core`** —
/// the mapped substitutes (always non-private on `Core`) and non-private
/// verbatim copies — so the wrapper *instance* itself is swappable through
/// `raw_name` (`var m = makeCore(); m.raw_isOn = .constant(false)`), and
/// every field is `var`. Private
/// verbatim copies get no `raw_` — they're sealed: not init parameters, not
/// readable, not mocked, they just behave. One access check, no per-wrapper
/// knowledge (it also keeps raw_'s `Wrapper<T>` backing-type spelling away
/// from `@Namespace` in its normal private form — the one SwiftUI wrapper
/// that isn't generic, where that spelling wouldn't compile).
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
    // Core's field set is identical to OutFlow's — reused directly rather
    // than duplicating the filter.
    let fields = outFlowProperties(properties)

    // Every field is internal — never `access` — regardless of the attached
    // type's own access level, except verbatim-copied private wrappers,
    // which keep their `private`; see this file's own doc comment. No
    // @RawProperty is stamped anywhere — an earlier revision decorated
    // wrapper fields with it so tests could swap wrapper instances on a
    // captured copy; with the capture gone, mocking happens at construction
    // (bind CoreModel below), and the macro stays in the package for anyone
    // who wants raw_ access on hand-written code.
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
        // Rule 1 — plain let/var → var, initial value kept (so its memberwise
        // parameter is defaulted), access stripped (a private plain field is
        // already a diagnostic, `plainPrivatePropertyNotAllowed`).
        guard let attributeText = p.attributeText else {
            let def = p.defaultValue.map { " = \($0.trimmedDescription)" } ?? ""
            return "var \(p.name): \(p.type?.trimmedDescription ?? "")\(def)"
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
    // in the first place.

    // The CoreModel mock — one observable `var` per Binding-typed field on
    // Core (the @State/@AppStorage/@SceneStorage substitutes plus genuine
    // @Binding fields, the exact set whose memberwise parameter is
    // `Binding<T>`). A test instantiates it and binds each property into
    // Core's matching parameter — `Bindable(model).x` hands back a real
    // `Binding<T>` via @Observable's dynamic-member projection, in plain
    // code, no view needed — so every write the copied body makes lands on
    // the model, ready to assert. @Observable + @MainActor final class: the
    // compiler expands the @Observable macro inside this expansion the same
    // way it expands the wrapper attributes above. Init parameters mirror
    // rule 1's spirit: host default carried over, optionals implicitly nil,
    // function types @escaping — same conventions as @Flowable's init.
    let bindingFields = fields.filter { $0.isBindingBackedStorage || $0.isBinding }
    guard !bindingFields.isEmpty else { return [statelessStruct] }

    let modelProperties = bindingFields.map { p -> String in
        "var \(p.name): \(p.type?.trimmedDescription ?? "")"
    }.joined(separator: "\n")
    let modelParams = bindingFields.map { p -> String in
        let type = p.type?.trimmedDescription ?? ""
        let isFn = p.type.map(isFunctionType) ?? false
        var param = "\(p.name): \(isFn ? "@escaping " : "")\(type)"
        if let def = p.defaultValue {
            param += " = \(def.trimmedDescription)"
        } else if p.type.map(isOptionalType) ?? false {
            param += " = nil"
        }
        return param
    }.joined(separator: ", ")
    let modelAssignments = bindingFields.map { "    self.\($0.name) = \($0.name)" }
        .joined(separator: "\n")
    // Same relative-indentation convention as renderFlowable's init and the
    // Core struct above: members at column 0, the init body one level in —
    // the expansion machinery re-shifts every line by the splice position.
    let coreModel = DeclSyntax(
        stringLiteral: """
            @Observable @MainActor final class CoreModel {
            \(modelProperties)
            init(\(modelParams)) {
            \(modelAssignments)
            }
            }
            """
    )
    return [statelessStruct, coreModel]
}
