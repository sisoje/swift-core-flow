/// Generates a nested `Core` struct — the host's standalone,
/// directly-constructible twin: every stored property as a substituted or
/// verbatim-copied field, plus a verbatim copy of every non-stored member
/// (`body` included). One source text, two types — the host runs it against
/// the live wrappers, `Core` compiles the identical text against injected
/// boundaries, so drift is impossible.
///
/// ```swift
/// @Shell
/// struct Card: View {
///     @Query private var items: [Item]
///     @State private var isExpanded: Bool = false
///     let title: String
///
///     var body: some View { ... }   // ordinary SwiftUI, written once
///
///     // generates:
///     // struct Core: View {
///     //     @QueryCore var items: [Item]
///     //     @Binding var isExpanded: Bool
///     //     let title: String
///     //     var body: some View { ... }   <- the same text, copied
///     // }
/// }
///
/// // constructed directly, no live view — the @QueryCore parameter is the
/// // bare fetched value:
/// // Card.Core(items: [item], isExpanded: .constant(true), title: "t")
/// ```
///
/// Field rules (full reference: README's Shell chapter; rationale at each
/// branch in `ShellRendering.swift`):
///
/// - **Plain fields** copy as-is, `public` stripped; a *private* plain field
///   is a compile error (`plainPrivatePropertyNotAllowed`).
/// - **The whitelist** — `@State`/`@AppStorage`/`@SceneStorage` → `@Binding`,
///   `@Query` → `@QueryCore` (`QueryCore.swift`) — must be private
///   (`sourceOfTruthMustBePrivate`): a view's own source of truth is never
///   caller-supplied. Conversely `@Binding`/`@ViewBuilder` must NOT be
///   private — callers supply them through the init.
/// - **Every other wrapper** copies verbatim — attribute arguments, default,
///   and `private` kept. A private copy is self-initializing and sealed
///   (an `@Environment` copy reads the real environment when hosted — mock
///   it via `.environment(...)` — and default `EnvironmentValues` outside);
///   a non-private copy stays a memberwise parameter of the wrapper's type.
///
/// No init is generated or copied — tests construct `Core` through Swift's
/// synthesized memberwise init, and a copied init would suppress it.
/// Mocking is use-site code, deliberately not generated:
///
/// ```swift
/// var writes: [Bool] = []
/// let core = Card.Core(
///     items: [item],
///     isExpanded: Binding(get: { false }, set: { writes.append($0) }),
///     title: "t")
/// core.isExpanded = true          // body writes land in `writes`
/// ```
///
/// `Core` is always internal, never `@Flowable` — a testing/preview seam,
/// not API surface. As a nominal struct it can conform to protocols, carry
/// the copied members, and host live — a tuple can do none of that
/// (verified directly: tuples cannot conform to `Equatable` or anything
/// else).
///
/// When the attached type's own inheritance clause spells `View` or
/// `ViewModifier`, `Core` conforms too — satisfied by the copied
/// `body`/`body(content:)` (for `ViewModifier`, `Content` resolves to
/// `Core`'s *own* `ViewModifier.Content`, fine — each type satisfies the
/// protocol independently; verified directly). Detection is syntactic and
/// misses extensions/typealiases/qualified spellings (see `detectHostKind`).
/// Members in a separate extension of the host aren't seen either — declare
/// what `Core` needs in the type, or extend `Core` too. Since the host's
/// `body` is hand-written source, `#Preview { Card() }` works natively;
/// macro-generated names are invisible inside `#Preview` (a Swift-level
/// rule), so a mocked `Core` previews through a hand-written wrapper — the
/// example apps' scenarios double as exactly that:
/// `#Preview { DragCardScenario() }`.
///
/// Independent of `@Flowable` — works with or without it attached.
@attached(member, names: named(Core))
public macro Shell() =
    #externalMacro(module: "CoreFlowMacros", type: "ShellMacro")
