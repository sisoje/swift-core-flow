import SwiftSyntax

/// A field's core type text, before any parameter-position-only decoration (a label,
/// `@escaping`, the `@ViewBuilder` attribute, a default) is added: `Binding<T>` for
/// `@Binding`, else the bare type — except a `@ViewBuilder`-stored *value* (`let
/// footer: Content`, not a closure) becomes a `() -> T` builder when `wrapViewBuilder`
/// is true.
///
/// `@MemberwiseInit` calls this twice, for two different purposes, with opposite
/// settings: once per init parameter with `wrapViewBuilder: true` (the default) —
/// that's what buys real trailing-closure call-site sugar (`Card(...) { content }`)
/// — and once per `DataLayout` typealias field with `wrapViewBuilder: false`. There
/// is no parameter position inside a tuple type for that trailing-closure sugar to
/// attach to, so wrapping would buy nothing there, and it's actively wrong: a
/// closure isn't `Equatable`/storable/diffable, which defeats `DataLayout`'s whole
/// purpose. So a `@ViewBuilder`-stored-value field in the typealias is just its own
/// declared type (`Content`), matching every other field.
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
/// Only used for the init — the `DataLayout` typealias is a plain type declaration
/// with no assignments to render, so unlike `baseTypeText` this has no
/// `wrapViewBuilder` parameter to thread through.
func fieldAssignment(_ p: StoredProperty, source: String) -> String {
    if p.isBinding { return "    self._\(p.name) = \(source)" }
    if p.isViewBuilder, !(p.type.map(isFunctionType) ?? false) {
        return "    self.\(p.name) = \(source)()"
    }
    return "    self.\(p.name) = \(source)"
}
