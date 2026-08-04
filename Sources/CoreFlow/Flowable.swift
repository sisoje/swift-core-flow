/// A memberwise `init` at the type's own access level — the `public` one
/// Swift refuses to synthesize, or any at all for a class/actor — plus a
/// labeled tuple typealias over the same non-private properties and a
/// factory building `Self` from that shape:
///
/// ```swift
/// @Flowable
/// public struct User {
///     public let id: UUID
///     public var isActive: Bool = false
///     // generates:
///     // public init(id: UUID, isActive: Bool = false) { ... }
///     // public static func makeFlow(_ flow: (UUID, Bool)) -> Self      // unlabeled — any shape-match converts in
///     // public typealias InFlow = (id: UUID, isActive: Bool)           // labeled — reflectable
/// }
/// ```
///
/// Rules (full reference: README's Flowable chapter; rationale in
/// `FlowableRendering.swift`):
///
/// - Mirrors Swift's synthesizer: inline `var` defaults become defaulted
///   parameters, optional `var`s default to `nil`, an inline-initialized
///   `let` is a constant, computed and `static` members are skipped.
///   Function-typed properties get `@escaping`.
/// - Explicit types required (the macro is syntax-only) — except bare
///   `Bool`/`Int`/`String` literal defaults, inferred off the literal's own
///   syntax, and `@Namespace` (always `Namespace.ID`).
/// - `@Binding`/`@ViewBuilder` are caller-supplied init parameters —
///   `private` on one is a compile error (unreachable). The source-of-truth
///   wrappers must be `private` and are excluded from the init (not from
///   `@Shell`'s `Core`). A private property with *no* wrapper is a compile
///   error: pure data flow has no room for opaque private state.
/// - `makeFlow(_:)`'s parameter is deliberately an *unlabeled* tuple,
///   spelled inline, so any structurally-compatible tuple converts in — an
///   `InFlow`-typed value included; `InFlow` is the one named shape: the
///   readable, `Mirror`-reflectable labeled tuple. One property collapses
///   both to the bare type (Swift has no 1-tuples); zero generates only
///   `init()`.
///
/// Deliberately nothing more: no typealias naming the unlabeled tuple (a
/// second name for the shape earned nothing — `InFlow` converts into the
/// unlabeled parameter, and generic code can't constrain on a generated
/// member typealias anyway), no accessor reading an instance back out into
/// an `InFlow` (data flows in at construction; nothing needed the backward
/// read), no protocol naming the shape (no proven generic-code use case),
/// no field-names member (`Reflector.fieldNames(of: SomeType.InFlow.self)`
/// covers it), and no snapshot wider than `InFlow` — capturing private
/// wrapper state is `@Shell`'s `Core`'s job (`Shell.swift`).
@attached(
    member, names: named(init), named(makeFlow), named(InFlow)
)
public macro Flowable() =
    #externalMacro(
        module: "CoreFlowMacros",
        type: "FlowableMacro"
    )
