/// Generates a memberwise `init` for the struct it is attached to, at the struct's
/// own access level.
///
/// Swift only ever synthesizes an **internal** memberwise initializer, and only
/// when you write no init of your own. `@MemberwiseInit` writes an explicit one that
/// matches the struct's access — the `public` memberwise init Swift refuses to give
/// a public type:
///
/// ```swift
/// @MemberwiseInit
/// public struct User {
///     public let id: UUID
///     public var isActive: Bool = false
///     // generates:
///     // public init(id: UUID, isActive: Bool = false) {
///     //     self.id = id
///     //     self.isActive = isActive
///     // }
/// }
/// ```
///
/// ## What it mirrors
/// - Inline `var` defaults become defaulted parameters.
/// - An inline-initialized `let` is a constant, excluded from `init`.
/// - Function-typed properties get `@escaping` (incl. `@MainActor`/`@Sendable` ones).
/// - Computed properties and `static`/`class` members are skipped.
///
/// ## Property wrappers (tuned for SwiftUI)
/// Only `@Binding` is threaded into the init, as a projected `Binding<T>` parameter.
/// Every other wrapper — `@State`, `@Environment`, `@StateObject`, … — is view-owned
/// or injected and is **excluded** from the init, so `@MemberwiseInit` works cleanly
/// on a `View`.
///
/// A property that becomes an init parameter must carry an explicit type annotation
/// (the macro is syntax-only and can't infer a type from a literal).
@attached(member, names: named(init))
public macro MemberwiseInit() =
    #externalMacro(
        module: "DataMacrosMacros",
        type: "MemberwiseInitMacro"
    )
