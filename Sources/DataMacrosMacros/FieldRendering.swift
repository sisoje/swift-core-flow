import SwiftSyntax

/// A field's core type text, before any parameter-position-only decoration (a label,
/// `@escaping`, the `@ViewBuilder` attribute, a default) is added: `Binding<T>` for
/// `@Binding`, else the bare type — except a `@ViewBuilder`-stored *value* (`let
/// footer: Content`, not a closure) becomes a `() -> T` builder when `wrapViewBuilder`
/// is true.
///
/// That wrapping is a deliberate divergence between the two renderers, not shared
/// behavior: `@MemberwiseInit` wants it (`wrapViewBuilder: true`, the default) — it's
/// what buys real trailing-closure call-site sugar (`Card(...) { content }`).
/// `@DataLayoutInit` passes `false` — there is no parameter position inside a tuple
/// literal for that sugar to attach to, so wrapping buys nothing there, and it's
/// actively wrong: a closure isn't `Equatable`/storable/diffable, which defeats
/// `DataLayout`'s whole purpose. So `@DataLayoutInit`'s tuple field for such a
/// property is just its own declared type (`Content`), matching every other field.
func baseTypeText(_ p: StoredProperty, wrapViewBuilder: Bool = true) -> String {
    let typeStr = p.type?.trimmedDescription ?? ""
    if p.isBinding { return "Binding<\(typeStr)>" }
    if wrapViewBuilder, p.isViewBuilder, !(p.type.map(isFunctionType) ?? false) {
        return "() -> \(typeStr)"
    }
    return typeStr
}

/// The member-init assignment for one field, reading from `source` — a bare
/// parameter name (`@MemberwiseInit`, and `@DataLayoutInit`'s single-property
/// fallback) or `dataLayout.<name>` (`@DataLayoutInit`'s tuple case). A `@Binding`
/// assigns its backing storage (`self._x`); with `wrapViewBuilder` true, a
/// `@ViewBuilder`-stored value calls the builder closure (`self.x = x()`) instead of
/// assigning it directly — see `baseTypeText` for why `@DataLayoutInit` passes
/// `false` here and skips that call.
func fieldAssignment(_ p: StoredProperty, source: String, wrapViewBuilder: Bool = true) -> String {
    if p.isBinding { return "    self._\(p.name) = \(source)" }
    if wrapViewBuilder, p.isViewBuilder, !(p.type.map(isFunctionType) ?? false) {
        return "    self.\(p.name) = \(source)()"
    }
    return "    self.\(p.name) = \(source)"
}
