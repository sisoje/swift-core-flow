import SwiftSyntax

/// A field's core type text, before any parameter-position-only decoration (a label,
/// `@escaping`, the `@ViewBuilder` attribute, a default) is added: `Binding<T>` for
/// `@Binding`, else the bare type — except a `@ViewBuilder`-stored *value* (`let
/// footer: Content`, not a closure) becomes a `() -> T` builder when `wrapViewBuilder`
/// is true.
///
/// `@Flowable` calls this twice, for two different purposes, with opposite
/// settings: once per init parameter with `wrapViewBuilder: true` (the default) —
/// that's what buys real trailing-closure call-site sugar (`Card(...) { content }`)
/// — and once per `InFlowSplat` typealias field with `wrapViewBuilder: false`.
/// There is no parameter position inside a tuple type for that trailing-closure
/// sugar to attach to, so wrapping would buy nothing there, and it's actively
/// wrong: a closure isn't `Equatable`/storable/diffable, which defeats
/// `InFlowSplat`'s whole purpose. So a `@ViewBuilder`-stored-value field in the
/// typealias is just its own declared type (`Content`), matching every other field.
func baseTypeText(_ p: StoredProperty, wrapViewBuilder: Bool = true) -> String {
    let typeStr = p.type?.trimmedDescription ?? ""
    if p.isBinding { return "Binding<\(typeStr)>" }
    if wrapViewBuilder, p.isViewBuilder, !(p.type.map(isFunctionType) ?? false) {
        return "() -> \(typeStr)"
    }
    return typeStr
}

/// The init assignment for one field, reading from the bare parameter `source`. A
/// `@Binding` assigns its backing storage (`self._x`); a `@ViewBuilder`-stored value
/// calls the builder closure (`self.x = x()`) instead of assigning it directly.
/// Only used for the init — the `InFlowSplat` typealias is a plain type
/// declaration with no assignments to render, so unlike `baseTypeText` this has no
/// `wrapViewBuilder` parameter to thread through.
func fieldAssignment(_ p: StoredProperty, source: String) -> String {
    if p.isBinding { return "    self._\(p.name) = \(source)" }
    if p.isViewBuilder, !(p.type.map(isFunctionType) ?? false) {
        return "    self.\(p.name) = \(source)()"
    }
    return "    self.\(p.name) = \(source)"
}

/// The expression reading a field's *current* value, for the `inFlow` computed
/// property — the reverse of `fieldAssignment`. A `@Binding` reads its
/// projected form (`$x`, type `Binding<T>`, matching `baseTypeText`'s
/// `Binding<T>` field type); everything else — including a `@ViewBuilder` field, in
/// either form — reads `x` directly.
///
/// `$x`, not `_x`, on this read side — same `$`-projection convention every
/// other `Binding`-producing wrapper in this file already uses
/// (`@State`/`@AppStorage`/`@SceneStorage` in `outFlowFieldReadExpression`,
/// `FlowableRendering.swift`), rather than a `@Binding`-only special case.
/// Verified directly: `Binding`'s own `projectedValue` is `{ self }` — reading
/// `$x` from inside the type gives back the identical `Binding<T>` `_x`
/// would, real write-through included. `_x` is kept only on the *assignment*
/// side (`fieldAssignment`, above) — verified directly that `self.$x = x` is
/// a compile error ("'$x' is immutable"), since `projectedValue` has no
/// setter; the backing storage `_x` is the only assignable form there, so
/// there's no `$`-unifying it away.
///
/// No `self.` prefix, unlike `fieldAssignment`: every caller of this function
/// reads inside a computed property's getter with no parameters at all (no
/// local name can shadow a property there), unlike the init, where the
/// parameter genuinely does share the field's name and `self.` is what
/// disambiguates the two. Verified directly — bare `$x`/`x` both resolve
/// correctly via implicit `self` with no parameter list in scope to collide
/// with.
///
/// Unlike `makeFlow(_:)`'s reverse direction, no wrapping/unwrapping is needed
/// here: the stored property already holds exactly its own declared type (`Content`
/// for a ViewBuilder-stored *value*, `() -> Content` for a stored closure), which is
/// exactly what `InFlowSplat`/`InFlow` already use as that field's type —
/// `@ViewBuilder` only ever reshapes the *init parameter*, never the property's own
/// storage.
func fieldReadExpression(_ p: StoredProperty) -> String {
    p.isBinding ? "$\(p.name)" : "\(p.name)"
}
