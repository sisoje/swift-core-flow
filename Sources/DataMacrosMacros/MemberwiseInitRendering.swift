import SwiftSyntax

/// Render a memberwise initializer for `properties` at the given access level —
/// one parameter per property — plus a `DataLayout` typealias bundling the same
/// properties into a tuple type. `access` is a modifier prefix such as `"public "`
/// or `""` (internal).
public func renderMemberwiseInit(properties: [StoredProperty], access: String) -> [DeclSyntax] {
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
    if let dataLayout = renderDataLayoutTypealias(properties: properties, access: access) {
        decls.append(dataLayout)
    }
    return decls
}

/// The `DataLayout` typealias declaration for `properties` — a tuple bundling every
/// non-private property, for API uniformity/discoverability alongside the memberwise
/// init above. Two or more properties → a tuple; exactly one collapses to that
/// property's bare type (Swift has no 1-tuples: `(x: T)` as a type collapses to
/// plain `T`, no `.x` accessor); zero yields no typealias at all — there's nothing
/// to alias, and a bare `init()` already covers that case above.
///
/// Always built with `wrapViewBuilder: false` (see `baseTypeText`), independent of
/// the init's own rendering above: a `@ViewBuilder`-stored *value* field
/// (`@ViewBuilder let footer: Content`) keeps its own type here (`Content`), not a
/// `() -> Content` builder — there's no parameter position inside a tuple type for
/// the trailing-closure sugar that wrapping exists to enable, and a closure would
/// make `DataLayout` — meant to be data you pass around/store/diff — hold something
/// that isn't `Equatable`. Function-typed fields likewise never get `@escaping`:
/// that attribute is only legal directly on a function *parameter*, and a closure
/// nested inside a tuple type is already escaping. Per-field defaults are dropped
/// too — tuple element types don't support `= default`.
func renderDataLayoutTypealias(properties: [StoredProperty], access: String) -> DeclSyntax? {
    let initParams = properties.filter { !$0.isPrivate }
    guard !initParams.isEmpty else { return nil }

    let rhs =
        initParams.count > 1
        ? "(" + initParams.map { "\($0.name): \(baseTypeText($0, wrapViewBuilder: false))" }
            .joined(separator: ", ") + ")"
        : baseTypeText(initParams[0], wrapViewBuilder: false)

    return DeclSyntax(stringLiteral: "\(access)typealias DataLayout = \(rhs)")
}
