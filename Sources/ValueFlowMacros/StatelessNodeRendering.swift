import SwiftSyntax

/// Renders `@StatelessNode`'s two generated members: a nested `StatelessNode` struct
/// over `OutFlow`'s field set *plus* `@Environment`/`@Namespace`
/// (`outFlowProperties` itself excludes both — see its own doc comment, in
/// `DataLayoutRendering.swift` — but `@StatelessNode` still captures them, just
/// differently than `OutFlow` ever did), plus a `statelessNode` computed property
/// building one from the current instance.
///
/// `StatelessNode` is always internal — its own access, every field's, and
/// `statelessNode`'s — regardless of the attached type's own access level, and it
/// carries no `@DataLayout`. This is a purely internal testing/snapshot seam
/// (`.statelessNode` for assertions and `StatelessNode`-hosted `body`/
/// `body(content:)` implementations, both reachable from the same module or a
/// `@testable import`), not a public API surface even when the attached type
/// itself is `public` — consumers of a public host type never need the snapshot,
/// only the package's own tests do. No hand-rolled init is needed either: Swift's
/// own memberwise-init synthesis already reproduces `@DataLayout`'s field-specific
/// behavior for every kind of field here — verified directly: a property-wrapper
/// field with no `init(wrappedValue:)` (`@Binding`) synthesizes a parameter of the
/// *wrapper's* type, one that does (`@Bindable`) synthesizes a parameter of the
/// *wrapped* type, and `@ViewBuilder` directly on a stored `let` synthesizes a
/// builder-closure parameter for a value-typed field exactly like `@DataLayout`'s
/// own hand-written logic does. The one thing genuinely lost by skipping
/// `@DataLayout` is `InFlow`/`InFlowSplat`/`inFlow`/`makeFlow(_:)` on
/// `StatelessNode` itself — accepted, since nothing here needs to round-trip a
/// snapshot back into itself.
///
/// Because `StatelessNode`'s own type is always internal, `statelessNode`'s access
/// is forced internal too (Swift rejects a more-accessible property with a
/// less-accessible type — verified directly: "property must be declared internal
/// because its type uses an internal type"). `body`/`body(content:)` on the
/// *attached* type, by contrast, still mirrors the attached type's own access
/// (`public` included) — verified directly that this compiles even though it
/// reads `self.statelessNode` (internal) and returns it: `some View`'s opaque
/// return type only exposes the `View` conformance, never the concrete
/// `StatelessNode` type, so a `public` `body` can freely return an internal
/// concrete value.
///
/// Every private wrapper kind becomes a *plain, constructed* field on
/// `StatelessNode` — never the original attribute, always captured as an ordinary
/// value read once when `.statelessNode` is computed:
/// - `@Query` → the synthesized `(result:, fetchError:, modelContext:)` tuple.
/// - `@State`/`@AppStorage`/`@SceneStorage` → `@Binding var name: T` (the one
///   case that keeps an attribute — substituted, not mirrored, since their own
///   storage only installs inside a live SwiftUI view and can't be redeclared
///   as itself on a plain struct; `@Binding` is the injectable/settable form a
///   genuine `@Binding` field already uses verbatim, which is why all three
///   share one condition below).
/// - `@FocusState` → `@FocusState<T>.Binding var name: T`, its own substituted
///   attribute, distinct from `@Binding var name: T` above. `@FocusState`'s own
///   `projectedValue` is `FocusState<T>.Binding`, **not** `Binding<T>` — verified
///   directly against the real SwiftUI interface: it exposes only
///   `wrappedValue` and `projectedValue` (itself), no conversion to `Binding<T>`
///   and no public initializer either, so folding it into the `@Binding` case
///   above isn't an option. The real `FocusState<T>.Binding`, though, is itself
///   `@propertyWrapper`-attributed (verified directly, reading the actual
///   SwiftUI interface), so it redeclares onto `StatelessNode` the same way
///   `@Binding` does — just spelling a different wrapper — and round-trips for
///   free: `snap.name` reads the unwrapped value, `snap.$name` hands back a
///   real `FocusState<T>.Binding` usable directly with `.focused(_:)`.
/// - `@Environment`/`@Namespace` → a plain `let name: T` — no attribute at all.
///   `@Environment`'s `wrappedValue` has no public setter (verified directly:
///   `error: cannot assign to property: 'colorScheme' is a get-only
///   property`), but that only blocks preserving the *attribute*; a plain,
///   unattributed `let` has no such restriction; the synthesized init just
///   assigns `self.name = name` like any other field. Always `let`, not
///   mirroring the original's `let`/`var` — the original is *always* `var`
///   (every property wrapper requires it), but the captured copy is a
///   one-time snapshot, immutable by design. `@Namespace` is grouped with
///   `@Environment` here rather than getting its own case: same get-only
///   `wrappedValue` problem (verified directly), and unlike
///   `@State`/`@AppStorage`/`@SceneStorage`/`@FocusState` it has no `projectedValue` at all to
///   fall back on for a `@Binding`-style substitution, so a plain `let` is the
///   only option.
///
/// Every other field — plain, `@ViewBuilder`, `@Query`, `@Bindable`, or any other
/// property wrapper — mirrors the *original* property's own attribute (if it has
/// one) and declared type onto `StatelessNode` verbatim, but **not** its
/// mutability: `StatelessNode` is a deterministic snapshot, so a field gets `var`
/// only where Swift's own property-wrapper rule forces it (a real
/// `@propertyWrapper` type — `@Bindable`, or any other genuine wrapper — requires
/// `var` storage; verified directly, `@Bindable let model: Settings` is a compile
/// error: "property wrapper can only be applied to a 'var'"). Every field that
/// doesn't carry a genuine wrapper attribute is `let`, regardless of whether the
/// *original* property was declared `let` or `var`:
/// - A plain `var subtitle: String?` on the original type becomes `let subtitle:
///   String?` on `StatelessNode` — a captured value, not a re-tweakable one.
/// - `@Query`'s synthesized `(result:, fetchError:, modelContext:)` tuple carries
///   no attribute on the copy (see above) and is `let` for the same reason.
/// - `@ViewBuilder` is **not** a `@propertyWrapper` — it's a result-builder
///   attribute, legal directly on a stored `let` (verified directly:
///   `@ViewBuilder let vb: () -> Text` compiles) — so it mirrors verbatim
///   including `let`, and unlike `OutFlow`'s tuple (nowhere to attach
///   trailing-closure sugar), that's a real win here: Swift's own synthesized
///   init reproduces `@ViewBuilder`'s builder-closure parameter for a
///   value-typed field (verified directly), so `@ViewBuilder` on `StatelessNode`'s
///   field genuinely buys real builder syntax at its own init call site, not
///   just documentation.
/// - `@Bindable` mirrors verbatim, `var` included — needs no special handling
///   beyond the general "genuine wrapper forces var" rule above. Swift's
///   synthesized init handles `@Bindable` the same way `@DataLayout`'s
///   hand-written one would (`self.model = model`, legal since `@Bindable`'s
///   wrappedValue is a plain get/set — verified directly), so mirroring it onto
///   `StatelessNode`'s copy works with no extra logic anywhere in this file.
func renderStatelessNode(
    properties: [StoredProperty], access: String, hostKind: StatelessNodeHostKind = .none
) -> [DeclSyntax] {
    // StatelessNode's own field set: OutFlow's, plus @Environment (OutFlow's tuple
    // can't carry it at all — see outFlowProperties's own doc comment — but
    // StatelessNode, a real struct, captures it as a plain field like everything
    // else). One filter over `properties` so declaration order is preserved
    // as a single interleaved list, matching the same principle
    // `outFlowProperties` documents for OutFlow/InFlow.
    let fields = properties.filter {
        !$0.isPrivate || $0.isQuery || $0.isBindingBackedStorage || $0.isEnvironment
            || $0.isFocusState || $0.isNamespace
    }

    // Every field is internal — never `access` — regardless of the attached
    // type's own access level; see this file's own doc comment for why
    // `StatelessNode` is deliberately never public.
    let fieldDecls = fields.map { p -> String in
        if p.isBindingBackedStorage || p.isBinding {
            // Always `var` — `@Binding` is a genuine `@propertyWrapper`, and Swift
            // requires `var` storage for any property-wrapper-attributed field
            // (verified directly: `@Binding let x: Int` is a compile error).
            return "@Binding var \(p.name): \(p.type?.trimmedDescription ?? "")"
        }
        if p.isFocusState {
            // Its own substituted attribute, distinct from @Binding above —
            // FocusState<T>.Binding is a different type than Binding<T> (see
            // this file's own doc comment) — but the same "genuine wrapper
            // requires var" reasoning applies.
            let type = p.type?.trimmedDescription ?? ""
            return "@FocusState<\(type)>.Binding var \(p.name): \(type)"
        }
        if p.isEnvironment || p.isNamespace {
            return "let \(p.name): \(p.type?.trimmedDescription ?? "")"
        }
        // Query gets its OutFlow-synthesized type with no attribute (no wrapper
        // of its own could apply to that resulting shape); everything else
        // reuses outFlowFieldType too — it already reduces to the property's own
        // bare declared type once Binding/Query are excluded — but carries its
        // original wrapper attribute along, verbatim. Mutability is never
        // mirrored: `var` only where a genuine `@propertyWrapper` (anything
        // other than `@ViewBuilder`, which isn't one) forces it — everything
        // else is `let`, a deterministic snapshot field.
        let requiresVar = p.wrapperName != nil && !p.isQuery && !p.isViewBuilder
        let keyword = requiresVar ? "var" : "let"
        let attributePrefix = p.isQuery ? "" : p.wrapperName.map { "@\($0) " } ?? ""
        return "\(attributePrefix)\(keyword) \(p.name): \(outFlowFieldType(p))"
    }.joined(separator: "\n")

    let conformance: String
    switch hostKind {
    case .view: conformance = ": View"
    case .viewModifier: conformance = ": ViewModifier"
    case .none: conformance = ""
    }

    // A doc comment, not a diagnostic — `@StatelessNode` can't know whether the
    // implementing extension already exists elsewhere in the module (no
    // semantic model), so a diagnostic here would either be a permanent nag
    // that never clears once implemented, or nothing at all. A doc comment on
    // the declaration itself costs nothing once the extension is written (it's
    // just documentation, visible on demand via Quick Help/jump-to-definition),
    // and Swift's own "does not conform to protocol" build error already
    // enforces that the extension gets written at all — this only clarifies
    // *what* to write, since the error alone doesn't say "extend `StatelessNode`,
    // not the outer type."
    let hostDocLines: [String]
    switch hostKind {
    case .view:
        hostDocLines = [
            "/// Conforms to `View`, declared by `@StatelessNode` — implement its real",
            "/// `body` in a separate extension, e.g. `extension YourType.StatelessNode {",
            "/// var body: some View { ... } }`.",
        ]
    case .viewModifier:
        hostDocLines = [
            "/// Conforms to `ViewModifier`, declared by `@StatelessNode` — implement its",
            "/// real `body(content:)` in a separate extension, e.g. `extension",
            "/// YourType.StatelessNode { func body(content: Content) -> some View",
            "/// { ... } }`.",
        ]
    case .none:
        hostDocLines = []
    }
    let hostDocComment = hostDocLines.isEmpty ? "" : hostDocLines.joined(separator: "\n") + "\n"

    let statelessStruct = DeclSyntax(
        stringLiteral: """
            \(hostDocComment)struct StatelessNode\(conformance) {
            \(fieldDecls)
            }
            """
    )

    // Constructing `StatelessNode`: each field reads the way `outFlow` does
    // (`outFlowFieldReadExpression`) — including `@Environment`, which falls
    // through to that function's plain `self.x` default, exactly right for a
    // plain captured `let` field — with one addition mirroring
    // `renderInFlowSplatFactory`'s own reverse-direction trick: a
    // `@ViewBuilder`-stored *value* field reads as its already-built plain value
    // (`self.footer`, type `Content`), but `StatelessNode`'s own `@ViewBuilder` field
    // — mirrored verbatim above — means its generated init parameter is a
    // builder closure (`() -> Content`), not the bare value. So that one case
    // gets wrapped in a trivial closure on the way in; every other field is
    // passed through unchanged.
    let args = fields.map { p -> String in
        let value = outFlowFieldReadExpression(p)
        if p.isViewBuilder, !(p.type.map(isFunctionType) ?? false) {
            return "\(p.name): { \(value) }"
        }
        return "\(p.name): \(value)"
    }.joined(separator: ", ")
    // Always internal, never `access` — `statelessNode`'s type (`StatelessNode`)
    // is itself always internal, and Swift rejects a more-accessible property
    // with a less-accessible type.
    let statelessProperty = DeclSyntax(
        stringLiteral: """
            var statelessNode: StatelessNode {
                StatelessNode(\(args))
            }
            """
    )

    // The mechanical delegation from the attached type's own real `body`/
    // `body(content:)` requirement down to `self.statelessNode`. `.modifier(_:)`
    // is what makes the `ViewModifier` case work at all without needing
    // `StatelessNode`'s own `Content` to unify with the attached type's — see this
    // function's doc comment (in StatelessNodeMacro.swift) for the verified reason
    // forwarding `content` directly into `StatelessNode.body(content:)` doesn't.
    let hostBody: DeclSyntax?
    switch hostKind {
    case .view:
        hostBody = DeclSyntax(
            stringLiteral: """
                \(access)var body: some View {
                    self.statelessNode
                }
                """
        )
    case .viewModifier:
        hostBody = DeclSyntax(
            stringLiteral: """
                \(access)func body(content: Content) -> some View {
                    content.modifier(self.statelessNode)
                }
                """
        )
    case .none:
        hostBody = nil
    }

    return [statelessStruct, statelessProperty] + (hostBody.map { [$0] } ?? [])
}
