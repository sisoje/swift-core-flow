/// Generates an init that takes the struct's (or class's, or actor's) stored
/// properties as **one tuple-typed parameter** — a "data layout" — instead of one
/// parameter per property, at the type's own access level.
///
/// ```swift
/// @DataLayoutInit
/// public struct User {
///     public let id: UUID
///     public let name: String
///     // generates:
///     // public typealias DataLayout = (id: UUID, name: String)
///     // public init(_ dataLayout: DataLayout) {
///     //     self.id = dataLayout.id
///     //     self.name = dataLayout.name
///     // }
/// }
/// ```
///
/// Call site: `User((id: someID, name: "Ada"))` — one positional argument, built as a
/// single labeled tuple value. Useful when the data layout itself is the thing you
/// want to pass around, store, or diff as a unit, rather than a call spelled out
/// argument by argument.
///
/// Shares its property-collection rules with `@MemberwiseInit` — see that macro's doc
/// comment for the inline `var` / property-wrapper / `@ViewBuilder` behavior. Two
/// differences fall out of using one tuple parameter instead of many:
///
/// - **No per-field defaults.** Tuple element types can't carry `= default`, so an
///   inline `var` default and an implicitly-`nil` optional `var` are both dropped —
///   every field must be supplied when constructing the tuple.
/// - **One property still gets a `DataLayout`, just not a tuple, and the init
///   doesn't route through it.** Swift has no 1-tuples — `(id: UUID)` as a type
///   collapses to plain `UUID`, no `.id` accessor — so with exactly one
///   participating property, `DataLayout` aliases the bare field type directly
///   (`typealias DataLayout = UUID`, declared for API uniformity), but the init
///   just uses the property's own name and type — `init(_ id: UUID) { self.id = id }`
///   — the same shape `@MemberwiseInit` would produce for that one property, just
///   unlabeled.
@attached(member, names: named(init), named(DataLayout))
public macro DataLayoutInit() =
    #externalMacro(
        module: "DataMacrosMacros",
        type: "DataLayoutInitMacro"
    )
