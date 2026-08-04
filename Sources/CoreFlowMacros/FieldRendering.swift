import SwiftSyntax

/// `wrapViewBuilder` exists because `@Flowable` needs opposite settings at
/// its two call sites: `true` per init parameter — the `() -> T` wrapping of a
/// `@ViewBuilder`-stored *value* is what buys trailing-closure call-site
/// sugar — and `false` per `makeFlow` tuple/`InFlow` field: a tuple type has no
/// parameter position for that sugar, and a closure field isn't
/// `Equatable`/storable/diffable, defeating the tuple's purpose.
func baseTypeText(_ p: StoredProperty, wrapViewBuilder: Bool = true) -> String {
    let typeStr = p.type?.trimmedDescription ?? ""
    if p.isBinding { return "Binding<\(typeStr)>" }
    if wrapViewBuilder, p.isViewBuilder, !(p.type.map(isFunctionType) ?? false) {
        return "() -> \(typeStr)"
    }
    return typeStr
}

/// `@Binding` must assign the backing `_x`: `self.$x = x` is a compile error
/// ("'$x' is immutable" — `projectedValue` has no setter; verified directly).
/// A `@ViewBuilder`-stored value calls the builder the init parameter wrapped
/// it in.
func fieldAssignment(_ p: StoredProperty, source: String) -> String {
    if p.isBinding { return "    self._\(p.name) = \(source)" }
    if p.isViewBuilder, !(p.type.map(isFunctionType) ?? false) {
        return "    self.\(p.name) = \(source)()"
    }
    return "    self.\(p.name) = \(source)"
}
