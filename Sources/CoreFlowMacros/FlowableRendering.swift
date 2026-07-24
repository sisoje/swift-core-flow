import SwiftSyntax

/// The memberwise init plus `InFlowSplat`/`makeFlow(_:)`/`InFlow`
/// (each renderer below documents its own rules). `access` is a modifier
/// prefix — `"public "` or `""`. Deliberately nothing wider: snapshotting
/// private wrapper state is `@Shell`'s `Core`'s job (`ShellRendering.swift`).
public func renderFlowable(properties: [StoredProperty], access: String) -> [DeclSyntax] {
    let initParams = properties.filter { !$0.isPrivate }

    let params = initParams.map { p -> String in
        // Init params always have a type here (the macro diagnosed any that don't).
        let base = baseTypeText(p)
        let isFn = p.type.map(isFunctionType) ?? false
        if p.isBinding {
            return "\(p.name): \(base)"
        }
        // Stored-closure form is the `@escaping` closure itself; stored-value
        // form takes the `() -> Value` builder already baked into `base` —
        // no `@escaping` needed there.
        if p.isViewBuilder {
            return "@ViewBuilder \(p.name): \(isFn ? "@escaping " : "")\(base)"
        }
        var param = "\(p.name): \(isFn ? "@escaping " : "")\(base)"
        // Inline `var` defaults and optional-implies-nil both mirror Swift's
        // own memberwise initializer.
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
    return decls
}

/// One property collapses to its bare type (Swift has no 1-tuples); zero →
/// no typealias.
///
/// **Deliberately unlabeled** — "splat": any structurally-compatible tuple
/// converts into it. Verified directly: a tuple *value* bound with different
/// labels fails to convert into a *labeled* target of the same shape but
/// succeeds into an unlabeled one — Swift only enforces label agreement
/// between two labeled tuple types. A labeled *literal* converts either way,
/// so callers can still spell field names when constructing. Tradeoff: no
/// labels means two swapped same-typed fields aren't caught.
///
/// `wrapViewBuilder: false`, and never `@escaping` (only legal directly on a
/// function parameter; a closure inside a tuple type is already escaping).
/// Per-field defaults are dropped — tuple element types can't carry them.
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

/// A static func, not a second `init`, so it works identically on
/// struct/class/actor — a delegating init needs `convenience` on a
/// class/actor; `Self(...)` in a static func sidesteps that. Fields read
/// positionally (`flow.0`, …) since `InFlowSplat` is unlabeled. A
/// `@ViewBuilder`-stored *value* is a plain value in the tuple but the init
/// wants a builder, so it forwards as a trivial closure (`{ flow.0 }`).
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

/// `InFlowSplat`, labeled — the readable, `Mirror`-reflectable name of the
/// shape (verified directly: `Mirror` reports actual field names over a
/// labeled tuple, only `.0`/`.1` over an unlabeled one). Same
/// collapse/absence rules. An `InFlow` value converts into the unlabeled
/// `InFlowSplat` parameter like any differently-labeled tuple (verified
/// directly). Deliberately no generated accessor reading an instance back
/// out into one: data flows in at construction, and nothing needed the
/// backward read.
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
