import SwiftSyntax

/// Render a memberwise initializer for `properties` at the given access level, plus
/// five supporting members: an unlabeled `InFlowSplat` typealias and a
/// `makeFlow(_:)` factory for building `Self` *from* one (splat-friendly,
/// see `renderInFlowSplatTypealias`/`renderInFlowSplatFactory`), a labeled
/// `InFlow` typealias with an `inFlow` computed property for reading the current
/// instance's data back *out* (readable/reflectable, see
/// `renderInFlowTypealias`/`renderInFlowProperty`), and an `OutFlow` typealias
/// with an `outFlow` computed property: `InFlow`'s fields plus every recognized
/// private source-of-truth wrapper (`@Query`/`@State`/`@AppStorage`/
/// `@SceneStorage`/`@FocusState`/`@Environment`/`@Namespace` — see
/// `outFlowProperties`), in declaration order (see
/// `renderOutFlowTypealias`/`renderOutFlowProperty`). `access` is a modifier
/// prefix such as `"public "` or `""` (internal).
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
    if let outFlowTypealias = renderOutFlowTypealias(properties: properties, access: access) {
        decls.append(outFlowTypealias)
    }
    if let outFlowProperty = renderOutFlowProperty(properties: properties, access: access) {
        decls.append(outFlowProperty)
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

    return DeclSyntax(
        stringLiteral: """
            \(access)static func makeFlow(_ flow: InFlowSplat) -> Self {
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

/// The properties `OutFlow`/`outFlow` (below) include: every non-private
/// participating property (same set `InFlow` has), plus every recognized
/// private source-of-truth wrapper — `@Query`/`@State`/`@AppStorage`/
/// `@SceneStorage`/`@FocusState`/`@Environment`/`@Namespace` — the view's own
/// externally-relevant *capturable* state, alongside its public data, no
/// exceptions. In declaration order, same as `properties` itself; not
/// data-layout fields first and wrapper fields appended after.
///
/// **No wrapper kind is excluded** — an earlier revision left `@Environment`
/// out on the theory that a captured snapshot goes stale the moment the real
/// environment changes, and that its own mocking story (inject a different
/// value where the type is constructed/hosted) already covers testing it
/// without this package's help. That reasoning was reconsidered: every
/// private property this package recognizes at all *is* a source of truth,
/// full stop, and `@Shell` never excluded `@Environment` either — the
/// asymmetry was the actual defect, not a deliberate design choice worth
/// keeping. `OutFlow`'s field set is identical to `@Shell`'s now (see
/// `outFlowProperties`'s reuse in `ShellRendering.swift`).
///
/// There's nothing left to exclude here at all — every property this function
/// sees is already guaranteed a recognized shape: a private property with no
/// wrapper (`private var cache = 0`) or an unrecognized one (`@StateObject`, a
/// future SwiftUI wrapper this package hasn't been taught about, …) is refused
/// outright by `collectStoredProperties`
/// (`plainPrivatePropertyNotAllowed`/`unsupportedPrivateWrapper`,
/// `StoredProperty.swift`) before it ever reaches this filter.
func outFlowProperties(_ properties: [StoredProperty]) -> [StoredProperty] {
    properties.filter {
        !$0.isPrivate || $0.isQuery || $0.isBindingBackedStorage || $0.isFocusState
            || $0.isEnvironment || $0.isNamespace
    }
}

/// A field's `OutFlow` type — distinct from `baseTypeText` (used by
/// `InFlowSplat`/`InFlow`), since `@Query`/`@State`/`@AppStorage`/
/// `@SceneStorage`/`@FocusState` need their own mapping, not the
/// `@Binding`/`@ViewBuilder` one `baseTypeText` knows:
/// - **Non-private fields** use `baseTypeText` unchanged — same rules `InFlow`
///   already applies (`Binding<T>` for `@Binding`, `@ViewBuilder` unwrapped to its
///   bare type, everything else as declared).
/// - **`@Query`** (`isQuery`) → `QueryCore<WrappedType>` — this package's own
///   drop-in stand-in for the live wrapper (see `QueryCore.swift` in
///   `Sources/ValueFlow`), carrying the exact instance surface the real
///   `Query` has (`wrappedValue`/`fetchError`/`modelContext`, no
///   `projectedValue` — verified directly against the `_SwiftData_SwiftUI`
///   interface). `WrappedType` is the property's own declared type (e.g.
///   `[Item]` for `@Query private var items: [Item]`). An earlier revision
///   synthesized a bare `(wrappedValue:, fetchError:)` tuple via `#pick`
///   instead — replaced by the real wrapper so `Core`'s field reads the
///   fetched value directly (`core.items`, not `.items.wrappedValue`).
/// - **`@State`/`@AppStorage`/`@SceneStorage`** (`isBindingBackedStorage`) →
///   `Binding<T>`, since these are the view's own read-*and-write*-able
///   storage from the outside — `$x` already gives the real thing, since
///   all three wrappers' `projectedValue` genuinely *is* `Binding<T>`
///   (verified directly against the real SwiftUI interface, `@SceneStorage`
///   included).
/// - **`@FocusState`** (`isFocusState`) → `FocusState<T>.Binding`, **not**
///   `Binding<T>` — a deliberately different type from the row above it, even
///   though both are read via `$x`. Verified directly against the real
///   SwiftUI interface: `FocusState<T>.Binding` exposes only `wrappedValue` and
///   `projectedValue` (itself), no public initializer at all and no conversion
///   to `Binding<T>` — so `$x` here resolves to a different concrete type
///   than it does for `@State`/`@AppStorage`/`@SceneStorage`, and there's no
///   way to normalize the two into one shared type without fabricating a fake
///   `Binding<T>` that satisfies neither `.focused(_:)` nor anything else
///   expecting the real projection back.
func outFlowFieldType(_ p: StoredProperty) -> String {
    if p.isBindingBackedStorage {
        return "Binding<\(p.type?.trimmedDescription ?? "")>"
    }
    if p.isFocusState {
        return "FocusState<\(p.type?.trimmedDescription ?? "")>.Binding"
    }
    if p.isQuery {
        return "QueryCore<\(p.type?.trimmedDescription ?? "")>"
    }
    return baseTypeText(p, wrapViewBuilder: false)
}

/// A field's `OutFlow` *read* expression, the `outFlow` property's counterpart to
/// `outFlowFieldType` above. No `self.` prefix anywhere here, same reasoning as
/// `fieldReadExpression`: every caller reads inside the `outFlow`/`core`
/// getter, neither of which has a parameter list, so there's nothing for a bare
/// identifier to collide with (verified directly).
/// - **Non-private fields** use `fieldReadExpression` unchanged (`x`, or
///   `$x` for `@Binding`).
/// - **`@State`/`@AppStorage`/`@SceneStorage`/`@FocusState`** all read the
///   *projected* value, `$x` — not `_x`, which gives the wrapper
///   instance itself (`State<T>`, not `Binding<T>`; verified directly). Same
///   expression for all four; only the resulting *type* differs (see
///   `outFlowFieldType` above) — `@FocusState`'s own `projectedValue` happens
///   to be `FocusState<T>.Binding` rather than `Binding<T>`, but it's still
///   reached the exact same way.
/// - **`@Query`** reads `QueryCore(wrappedValue: _x.wrappedValue, fetchError:
///   _x.fetchError, modelContext: _x.modelContext)` — `_x` is the wrapper
///   *instance* itself (type `Query<Element, Result>`, the same
///   underscore-prefixed access `@Binding`'s assignment side already uses),
///   and all three are its real members, captured verbatim into the drop-in
///   `QueryCore` declared by `outFlowFieldType` above. Reading
///   `modelContext` outside a live container works — verified directly, no
///   crash — so capturing it eagerly here is safe even for snapshots built in
///   plain code.
func outFlowFieldReadExpression(_ p: StoredProperty) -> String {
    if p.isBindingBackedStorage || p.isFocusState {
        return "$\(p.name)"
    }
    if p.isQuery {
        return
            "QueryCore(wrappedValue: _\(p.name).wrappedValue, fetchError: _\(p.name).fetchError, modelContext: _\(p.name).modelContext)"
    }
    return fieldReadExpression(p)
}

/// The `OutFlow` typealias — same collapse/absence rules as `InFlowSplat`/
/// `InFlow` (two-or-more → labeled tuple, exactly one → bare type, zero →
/// no typealias), but over `outFlowProperties`'s wider field set rather than just
/// the non-private ones.
func renderOutFlowTypealias(properties: [StoredProperty], access: String) -> DeclSyntax? {
    let fields = outFlowProperties(properties)
    guard !fields.isEmpty else { return nil }

    let rhs =
        fields.count > 1
        ? "(" + fields.map { "\($0.name): \(outFlowFieldType($0))" }.joined(separator: ", ") + ")"
        : outFlowFieldType(fields[0])

    return DeclSyntax(stringLiteral: "\(access)typealias OutFlow = \(rhs)")
}

/// The `outFlow` computed property — extracts the current instance's `OutFlow`
/// value, reading each field per `outFlowFieldReadExpression`. Present exactly when
/// `OutFlow` is.
func renderOutFlowProperty(properties: [StoredProperty], access: String) -> DeclSyntax? {
    let fields = outFlowProperties(properties)
    guard !fields.isEmpty else { return nil }

    let isTuple = fields.count > 1
    let value =
        isTuple
        ? "("
            + fields.map { "\($0.name): \(outFlowFieldReadExpression($0))" }.joined(separator: ", ")
            + ")"
        : outFlowFieldReadExpression(fields[0])

    return DeclSyntax(
        stringLiteral: """
            \(access)var outFlow: OutFlow {
                \(value)
            }
            """
    )
}
