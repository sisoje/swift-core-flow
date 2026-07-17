/// Generates a `Capability` tuple typealias and a `capability` computed property that
/// bundles every eligible computed property and method of the type (or extension) it's
/// attached to into one value — a lightweight "protocol witness"-style bundle of
/// behavior, rather than data.
///
/// ```swift
/// struct Counter {
///     private var count = 0
/// }
///
/// @Capability
/// extension Counter {
///     var doubled: Int { count * 2 }
///     func increment() { /* ... */ }
///     func fetch() async throws -> Int { count }
///     // generates:
///     // typealias Capability = (doubled: Int, increment: () -> Void, fetch: () async throws -> Int)
///     // var capability: Capability {
///     //     (doubled, increment, fetch)
///     // }
/// }
/// ```
///
/// Unlike `@MemberwiseInit` — which collects *stored* properties and therefore
/// cannot usefully attach to an extension (extensions can't declare stored
/// properties, so there'd be nothing to find) — `@Capability` collects *computed*
/// members, which extensions can declare freely. So `@Capability` works attached
/// directly to a struct/class/actor, or to an extension of one; either way it only
/// sees whatever's written in the exact declaration it's attached to.
///
/// ## What's collected
/// - **Computed properties** (a `var` with a getter — stored properties, and ones with
///   only `willSet`/`didSet`, are skipped) — the field is the property's own type.
///   Needs an explicit type annotation (syntax-only, same reason as the other macros).
/// - **Instance methods** — the field is a closure type built from the method's
///   parameter types (labels dropped, matching how closure types work), `async`/
///   `throws` effects, and return type (`Void` if absent).
/// - **Skipped**: `private`/`fileprivate` members, `static`/`class` members,
///   initializers, subscripts, and — because Swift can't form a plain closure
///   reference to one — `mutating` methods.
///
/// One eligible member collapses `Capability` to that member's bare type (Swift has no
/// 1-tuples) and `capability` to that bare value — same collapse `@MemberwiseInit`'s
/// `DataLayout` typealias does. Zero eligible members is a diagnostic, not an empty
/// `Capability` — there's no sensible "empty capability."
///
/// No `@Sendable` on the generated closure fields: marking them unconditionally would
/// make the generated code fail to compile for any type that captures something
/// non-Sendable (verified directly — `error: converting non-Sendable function value to
/// '@Sendable () -> Void' may introduce data races`), and Swift 6's region-based
/// checking already permits crossing actor/Task boundaries with a plain, un-annotated
/// closure type when the captured content actually is safe.
@attached(member, names: named(Capability), named(capability))
public macro Capability() =
    #externalMacro(
        module: "DataMacrosMacros",
        type: "CapabilityMacro"
    )
