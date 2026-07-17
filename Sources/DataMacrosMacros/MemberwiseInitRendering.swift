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
    if let factory = renderDataLayoutFactory(properties: properties, access: access) {
        decls.append(factory)
    }
    return decls
}

/// The `DataLayout` typealias declaration for `properties` — a tuple bundling every
/// non-private property, for API uniformity/discoverability alongside the memberwise
/// init above. Two or more properties → a tuple; exactly one collapses to that
/// property's bare type (Swift has no 1-tuples: `(T)` as a type is just `T`); zero
/// yields no typealias at all — there's nothing to alias, and a bare `init()`
/// already covers that case above.
///
/// **Deliberately unlabeled**, e.g. `(Int, String)` not `(x: Int, name: String)` —
/// so any structurally-compatible tuple converts into it, not just one built with
/// these exact field names. Verified directly: a tuple *value* already bound with
/// different labels (`let t = (xxx: 1, yyy: 2)`) fails to convert into a
/// *labeled* target tuple type of the same shape, but succeeds against an
/// *unlabeled* one — Swift only enforces label agreement between two labeled tuple
/// types, not into an unlabeled one. A labeled tuple *literal* (`(x: 1, y: 2)`)
/// converts into an unlabeled target either way, so callers can still write field
/// names for their own readability when constructing the value; only a
/// pre-existing differently-labeled variable needed this loosening. The real
/// tradeoff: with no labels, swapping two same-typed fields' order is no longer
/// caught by the type checker.
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
        ? "(" + initParams.map { baseTypeText($0, wrapViewBuilder: false) }.joined(separator: ", ") + ")"
        : baseTypeText(initParams[0], wrapViewBuilder: false)

    return DeclSyntax(stringLiteral: "\(access)typealias DataLayout = \(rhs)")
}

/// A `make(dataLayout:)` static factory constructing `Self` from a `DataLayout`
/// value, by forwarding each field into the primary memberwise init above — direct
/// field access, not the array/map/force-unwrap trick a `Self.init` function
/// reference needs to accept a tuple. A static func (not a second `init`)
/// specifically because it works identically for a struct, class, or actor: a
/// delegating second `init` would need `self.init(...)`, which on a class/actor
/// requires the `convenience` keyword and drags in Swift's designated/convenience
/// init rules — `Self(...)` inside a plain static function sidesteps all of that.
/// Returns nil exactly when `renderDataLayoutTypealias` does (no properties,
/// nothing to build from).
///
/// `DataLayout` is unlabeled (see `renderDataLayoutTypealias`), so a tuple-case
/// field is read positionally — `dataLayout.0`, `dataLayout.1`, … in field order —
/// rather than by name.
///
/// A `@ViewBuilder`-stored *value* field is a plain value in `DataLayout` but the
/// primary init still wants a `() -> Value` builder for it (see `baseTypeText`) — so
/// unlike every other field, it's forwarded as a trivial closure (`{ dataLayout.0 }`)
/// rather than the bare value.
func renderDataLayoutFactory(properties: [StoredProperty], access: String) -> DeclSyntax? {
    let initParams = properties.filter { !$0.isPrivate }
    guard !initParams.isEmpty else { return nil }

    let isTuple = initParams.count > 1
    let args = initParams.enumerated().map { index, p -> String in
        let source = isTuple ? "dataLayout.\(index)" : "dataLayout"
        if p.isViewBuilder, !(p.type.map(isFunctionType) ?? false) {
            return "\(p.name): { \(source) }"
        }
        return "\(p.name): \(source)"
    }.joined(separator: ", ")

    return DeclSyntax(
        stringLiteral: """
            \(access)static func make(dataLayout: DataLayout) -> Self {
                Self(\(args))
            }
            """
    )
}
