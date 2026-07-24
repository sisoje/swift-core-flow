import SwiftSyntax

/// Render a memberwise initializer for `properties` at the given access level, plus
/// four supporting members: an unlabeled `InFlowSplat` typealias and a
/// `makeFlow(_:)` factory for building `Self` *from* one (splat-friendly,
/// see `renderInFlowSplatTypealias`/`renderInFlowSplatFactory`), and a labeled
/// `InFlow` typealias with an `inFlow` computed property for reading the current
/// instance's data back *out* (readable/reflectable, see
/// `renderInFlowTypealias`/`renderInFlowProperty`). `access` is a
/// modifier prefix such as `"public "` or `""` (internal). Deliberately
/// nothing wider — snapshotting private wrapper state is `@Shell`'s `Core`'s
/// job (see `ShellRendering.swift`).
public func renderFlowable(properties: [StoredProperty], access: String) -> [DeclSyntax] {
    let initParams = properties.filter { !$0.isPrivate }

    let params = initParams.map { p -> String in
        // Init params always have a type here (the macro diagnosed any that don't).
        let base = baseTypeText(p)
        let isFn = p.type.map(isFunctionType) ?? false
        // A `@Binding` is threaded through as its projected `Binding<T>` type.
        if p.isBinding {
            return "\(p.name): \(base)"
        }
        // A `@ViewBuilder` param carries the attribute. Stored-closure form is the
        // `@escaping` closure itself (`base` is the bare closure type here); stored-
        // value form takes a `() -> Value` builder (already baked into `base`, no
        // `@escaping` needed).
        if p.isViewBuilder {
            return "@ViewBuilder \(p.name): \(isFn ? "@escaping " : "")\(base)"
        }
        var param = "\(p.name): \(isFn ? "@escaping " : "")\(base)"
        // A `var` with an inline default gets the same default as the parameter,
        // and an optional `var` is implicitly nil-initialized — both mirroring
        // Swift's own memberwise initializer.
        if !p.isLet, let def = p.defaultValue {
            param += " = \(def.trimmedDescription)"
        } else if !p.isLet, p.type.map(isOptionalType) ?? false {
            param += " = nil"
        }
        return param
    }

    let assignments =
        initParams
        .map { fieldAssignment($0, source: $0.name) }
        .joined(separator: "\n")

    // One relative indentation level: the `init` header/brace at column 0, the body
    // at 4 spaces. The member macro's output is re-indented into the type body.
    let initDecl = """
        \(access)init(\(params.joined(separator: ", "))) {
        \(assignments)
        }
        """

    var decls = [DeclSyntax(stringLiteral: initDecl)]
    if let inFlowSplat = renderInFlowSplatTypealias(properties: properties, access: access) {
        decls.append(inFlowSplat)
    }
    if let factory = renderInFlowSplatFactory(properties: properties, access: access) {
        decls.append(factory)
    }
    if let inFlow = renderInFlowTypealias(properties: properties, access: access) {
        decls.append(inFlow)
    }
    if let property = renderInFlowProperty(properties: properties, access: access) {
        decls.append(property)
    }
    return decls
}

/// The `InFlowSplat` typealias declaration for `properties` — a tuple bundling
/// every non-private property, for API uniformity/discoverability alongside the
/// memberwise init above. Two or more properties → a tuple; exactly one collapses
/// to that property's bare type (Swift has no 1-tuples: `(T)` as a type is just
/// `T`); zero yields no typealias at all — there's nothing to alias, and a bare
/// `init()` already covers that case above.
///
/// **Deliberately unlabeled**, e.g. `(Int, String)` not `(x: Int, name: String)` —
/// so any structurally-compatible tuple converts into it, not just one built with
/// these exact field names — hence "splat" in the name. Verified directly: a
/// tuple *value* already bound with different labels (`let t = (xxx: 1, yyy: 2)`)
/// fails to convert into a *labeled* target tuple type of the same shape, but
/// succeeds against an *unlabeled* one — Swift only enforces label agreement
/// between two labeled tuple types, not into an unlabeled one. A labeled tuple
/// *literal* (`(x: 1, y: 2)`) converts into an unlabeled target either way, so
/// callers can still write field names for their own readability when
/// constructing the value; only a pre-existing differently-labeled variable
/// needed this loosening. The real tradeoff: with no labels, swapping two
/// same-typed fields' order is no longer caught by the type checker.
///
/// Always built with `wrapViewBuilder: false` (see `baseTypeText`), independent of
/// the init's own rendering above: a `@ViewBuilder`-stored *value* field
/// (`@ViewBuilder let footer: Content`) keeps its own type here (`Content`), not a
/// `() -> Content` builder — there's no parameter position inside a tuple type for
/// the trailing-closure sugar that wrapping exists to enable, and a closure would
/// make `InFlowSplat` — meant to be data you pass around/store/diff — hold
/// something that isn't `Equatable`. Function-typed fields likewise never get
/// `@escaping`: that attribute is only legal directly on a function *parameter*,
/// and a closure nested inside a tuple type is already escaping. Per-field
/// defaults are dropped too — tuple element types don't support `= default`.
func renderInFlowSplatTypealias(properties: [StoredProperty], access: String) -> DeclSyntax? {
    let initParams = properties.filter { !$0.isPrivate }
    guard !initParams.isEmpty else { return nil }

    let rhs =
        initParams.count > 1
        ? "(" + initParams.map { baseTypeText($0, wrapViewBuilder: false) }.joined(separator: ", ")
            + ")"
        : baseTypeText(initParams[0], wrapViewBuilder: false)

    return DeclSyntax(stringLiteral: "\(access)typealias InFlowSplat = \(rhs)")
}

/// A `makeFlow(_:)` static factory constructing `Self` from an
/// `InFlowSplat` value, by forwarding each field into the primary memberwise
/// init above — direct field access, not the array/map/force-unwrap trick a
/// `Self.init` function reference needs to accept a tuple. A static func (not a
/// second `init`) specifically because it works identically for a struct, class,
/// or actor: a delegating second `init` would need `self.init(...)`, which on a
/// class/actor requires the `convenience` keyword and drags in Swift's
/// designated/convenience init rules — `Self(...)` inside a plain static function
/// sidesteps all of that. Returns nil exactly when `renderInFlowSplatTypealias`
/// does (no properties, nothing to build from).
///
/// `InFlowSplat` is unlabeled (see `renderInFlowSplatTypealias`), so a
/// tuple-case field is read positionally — `flow.0`, `flow.1`, … in field order —
/// rather than by name.
///
/// A `@ViewBuilder`-stored *value* field is a plain value in `InFlowSplat` but
/// the primary init still wants a `() -> Value` builder for it (see
/// `baseTypeText`) — so unlike every other field, it's forwarded as a trivial
/// closure (`{ flow.0 }`) rather than the bare value.
func renderInFlowSplatFactory(properties: [StoredProperty], access: String) -> DeclSyntax? {
    let initParams = properties.filter { !$0.isPrivate }
    guard !initParams.isEmpty else { return nil }

    let isTuple = initParams.count > 1
    let args = initParams.enumerated().map { index, p -> String in
        let source = isTuple ? "flow.\(index)" : "flow"
        if p.isViewBuilder, !(p.type.map(isFunctionType) ?? false) {
            return "\(p.name): { \(source) }"
        }
        return "\(p.name): \(source)"
    }.joined(separator: ", ")

    // The single-field collapse makes `flow` a DIRECT function parameter when
    // that one field is a closure — non-escaping by default, yet it's passed
    // to the init's @escaping parameter. Only this case needs the annotation:
    // inside a real tuple a closure is already escaping (and @escaping on the
    // tuple parameter would be ill-formed).
    let escaping =
        !isTuple && (initParams[0].type.map(isFunctionType) ?? false) ? "@escaping " : ""

    return DeclSyntax(
        stringLiteral: """
            \(access)static func makeFlow(_ flow: \(escaping)InFlowSplat) -> Self {
                Self(\(args))
            }
            """
    )
}

/// The `InFlow` typealias — same fields and types as `InFlowSplat`, but
/// *labeled*: `(id: UUID, name: String)`, not `(UUID, String)`. Two or more
/// properties → a labeled tuple; exactly one collapses to the bare type, same as
/// `InFlowSplat` (a label on a lone value doesn't survive as a type either
/// way); zero → no typealias, matching `InFlowSplat`.
///
/// Exists specifically for readable field access (`layout.id`, not `layout.0`) and
/// so tools like `Mirror` can report real field names — verified directly:
/// `Mirror(reflecting:)` over a labeled tuple reports each field's actual name,
/// while over an unlabeled one it only reports positional labels (`".0"`, `".1"`).
/// `InFlowSplat` stays unlabeled (see `renderInFlowSplatTypealias`)
/// specifically for `makeFlow(_:)`'s splatting flexibility, so the two
/// typealiases serve opposite directions: `InFlow` out (via `inFlow` below),
/// `InFlowSplat` in (via `make`).
///
/// An `InFlow` value converts directly into an `InFlowSplat`-typed parameter
/// (verified directly) — Swift only enforces label agreement between two
/// *labeled* tuple types, and `InFlowSplat` is unlabeled — so
/// `Self.makeFlow(someInstance.inFlow)` round-trips with no manual
/// conversion.
func renderInFlowTypealias(properties: [StoredProperty], access: String) -> DeclSyntax? {
    let initParams = properties.filter { !$0.isPrivate }
    guard !initParams.isEmpty else { return nil }

    let rhs =
        initParams.count > 1
        ? "("
            + initParams.map { "\($0.name): \(baseTypeText($0, wrapViewBuilder: false))" }
            .joined(separator: ", ") + ")"
        : baseTypeText(initParams[0], wrapViewBuilder: false)

    return DeclSyntax(stringLiteral: "\(access)typealias InFlow = \(rhs)")
}

/// The `inFlow` computed property — extracts the *current* instance's data as an
/// `InFlow` value, the reverse direction of `makeFlow(_:)`. Present
/// exactly when `InFlow` is.
///
/// Every field reads via `fieldReadExpression`, no `self.` prefix (this is a
/// getter with no parameter list to disambiguate against — verified directly)
/// — unlike `makeFlow(_:)`'s reverse direction, no wrapping is needed for a
/// `@ViewBuilder` field: the stored property already holds exactly its own
/// declared type, which is exactly what `InFlowSplat`/`InFlow` already use as
/// that field's type. Only `@Binding` needs its projected form (`$x`).
func renderInFlowProperty(properties: [StoredProperty], access: String) -> DeclSyntax? {
    let initParams = properties.filter { !$0.isPrivate }
    guard !initParams.isEmpty else { return nil }

    let isTuple = initParams.count > 1
    let value =
        isTuple
        ? "(" + initParams.map { "\($0.name): \(fieldReadExpression($0))" }.joined(separator: ", ")
            + ")"
        : fieldReadExpression(initParams[0])

    return DeclSyntax(
        stringLiteral: """
            \(access)var inFlow: InFlow {
                \(value)
            }
            """
    )
}
