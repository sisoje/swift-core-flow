/// Generates BOTH initializers at once — everything `@MemberwiseInit` generates
/// *and* everything `@DataLayoutInit` generates — from a single attribute, at the
/// type's own access level.
///
/// ```swift
/// @DataInit
/// public struct User {
///     public let id: UUID
///     public let name: String
///     // generates:
///     // public init(id: UUID, name: String) {
///     //     self.id = id
///     //     self.name = name
///     // }
///     // public typealias DataLayout = (id: UUID, name: String)
///     // public init(_ dataLayout: DataLayout) {
///     //     self.id = dataLayout.id
///     //     self.name = dataLayout.name
///     // }
/// }
///
/// let a = User(id: someID, name: "Ada")             // per-property init
/// let b = User((id: someID, name: "Ada"))            // DataLayout tuple init
/// ```
///
/// Equivalent to stacking `@DataLayoutInit @MemberwiseInit` on the same type — same
/// two initializers, since a labeled per-property init and an unlabeled
/// tuple-parameter init are different signatures and never collide (the one
/// exception, zero stored properties, collapses to a single shared `init()` rather
/// than a redeclaration). The difference from stacking is *how* they're produced:
/// `@DataInit` collects the type's stored properties once and renders both shapes
/// from that single pass, so a property missing its required type annotation is
/// diagnosed once, not twice.
///
/// See `@MemberwiseInit` and `@DataLayoutInit`'s own doc comments for the shared
/// property rules (`private` exclusion, `@Binding`, `@ViewBuilder`) and for what's
/// different about the tuple-parameter init specifically (no per-field defaults, the
/// single-property collapse).
@attached(member, names: named(init), named(DataLayout))
public macro DataInit() =
    #externalMacro(
        module: "DataMacrosMacros",
        type: "DataInitMacro"
    )
