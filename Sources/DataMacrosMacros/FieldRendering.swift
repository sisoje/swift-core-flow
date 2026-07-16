import SwiftSyntax

/// A field's core type text, before any parameter-position-only decoration (a label,
/// `@escaping`, the `@ViewBuilder` attribute, a default) is added: `Binding<T>` for
/// `@Binding`, `() -> T` for a ViewBuilder-stored value, else the bare type. Shared
/// by `renderMemberwiseInit` and `renderDataLayoutMembers`.
func baseTypeText(_ p: StoredProperty) -> String {
    let typeStr = p.type?.trimmedDescription ?? ""
    if p.isBinding { return "Binding<\(typeStr)>" }
    if p.isViewBuilder, !(p.type.map(isFunctionType) ?? false) { return "() -> \(typeStr)" }
    return typeStr
}

/// The member-init assignment for one field, reading from `source` — a bare
/// parameter name (`@MemberwiseInit`, and `@DataLayoutInit`'s single-property
/// fallback) or `dataLayout.<name>` (`@DataLayoutInit`'s tuple case). A `@Binding`
/// assigns its backing storage (`self._x`); a `@ViewBuilder`-stored value calls the
/// builder closure (`self.x = x()`); everything else assigns directly. Shared by
/// both renderers.
func fieldAssignment(_ p: StoredProperty, source: String) -> String {
    if p.isBinding { return "    self._\(p.name) = \(source)" }
    if p.isViewBuilder, !(p.type.map(isFunctionType) ?? false) {
        return "    self.\(p.name) = \(source)()"
    }
    return "    self.\(p.name) = \(source)"
}
