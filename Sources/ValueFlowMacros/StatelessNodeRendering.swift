import SwiftSyntax

/// Renders `@StatelessNode`'s two generated members: a nested `StatelessNode` struct
/// over `OutFlow`'s field set *plus* `@Environment` (`outFlowProperties`
/// itself excludes `@Environment` — see its own doc comment, in
/// `DataLayoutRendering.swift` — but `@StatelessNode` still captures it, just
/// differently than `OutFlow` ever did), plus a `statelessNode` computed property
/// building one from the current instance.
///
/// `StatelessNode` carries `@DataLayout` itself, so its own memberwise init,
/// `InFlowSplat`/`makeFlow(_:)`, and `InFlow`/`inFlow` all come from that second
/// expansion — verified directly that a macro-generated declaration carrying
/// another macro's attribute really does get expanded by the compiler, no
/// different from writing it by hand. Nothing here hand-renders an init.
///
/// Every private wrapper kind becomes a *plain, constructed* field on
/// `StatelessNode` — never the original attribute, always captured as an ordinary
/// value read once when `.statelessNode` is computed:
/// - `@Query` → the synthesized `(result:, fetchError:, modelContext:)` tuple.
/// - `@State`/`@AppStorage` → `@Binding var name: T` (the one case that keeps
///   an attribute — substituted, not mirrored, since their own storage only
///   installs inside a live SwiftUI view and can't be redeclared as itself on
///   a plain struct; `@Binding` is the injectable/settable form a genuine
///   `@Binding` field already uses verbatim, which is why both share one
///   condition below).
/// - `@Environment` → a plain `let name: T` — no attribute at all.
///   `@Environment`'s `wrappedValue` has no public setter (verified directly:
///   `error: cannot assign to property: 'colorScheme' is a get-only
///   property`), but that only blocks preserving the *attribute*; a plain,
///   unattributed `let` has no such restriction; `@DataLayout`'s init just
///   assigns `self.name = name` like any other field. Always `let`, not
///   mirroring the original's `let`/`var` — the original is *always* `var`
///   (every property wrapper requires it), but the captured copy is a
///   one-time snapshot, immutable by design.
///
/// Every other field — plain, `@Binding`, `@ViewBuilder`, `@Bindable`, or any
/// other property wrapper — mirrors the *original* property's own declaration on
/// `StatelessNode` verbatim: same attribute (if it has one), same declared type,
/// same `let`/`var`. Concretely:
/// - A plain `var subtitle: String?` field stays a mutable `var` on `StatelessNode`,
///   not a `let` — useful for constructing/tweaking a snapshot directly for UI
///   testing.
/// - `@ViewBuilder` mirrors verbatim, and unlike `OutFlow`'s tuple (nowhere to
///   attach trailing-closure sugar), it's a real win here: `StatelessNode` has a
///   real init (from its own `@DataLayout` expansion), so `@ViewBuilder` on its
///   field genuinely buys real builder syntax at `StatelessNode`'s own init call
///   site, not just documentation.
/// - `@Bindable` mirrors verbatim and needs no special handling at all —
///   `@DataLayout`'s init logic never recognized `@Bindable` specially even on
///   the *original* type (it just assigns `self.model = model`, legal since
///   `@Bindable`'s wrappedValue is a plain get/set), so reusing that exact
///   unmodified path on `StatelessNode`'s copy works identically.
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
        !$0.isPrivate || $0.isQuery || $0.isStateOrAppStorage || $0.isEnvironment
    }

    let fieldDecls = fields.map { p -> String in
        if p.isStateOrAppStorage || p.isBinding {
            let keyword = p.isLet ? "let" : "var"
            return "@Binding \(access)\(keyword) \(p.name): \(p.type?.trimmedDescription ?? "")"
        }
        if p.isEnvironment {
            return "\(access)let \(p.name): \(p.type?.trimmedDescription ?? "")"
        }
        // Query gets its OutFlow-synthesized type with no attribute (no wrapper
        // of its own could apply to that resulting shape); everything else
        // reuses outFlowFieldType too — it already reduces to the property's own
        // bare declared type once Binding/Query are excluded — but carries its
        // original wrapper attribute along, verbatim.
        let keyword = p.isLet ? "let" : "var"
        let attributePrefix = p.isQuery ? "" : p.wrapperName.map { "@\($0) " } ?? ""
        return "\(attributePrefix)\(access)\(keyword) \(p.name): \(outFlowFieldType(p))"
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
            "/// public var body: some View { ... } }`.",
        ]
    case .viewModifier:
        hostDocLines = [
            "/// Conforms to `ViewModifier`, declared by `@StatelessNode` — implement its",
            "/// real `body(content:)` in a separate extension, e.g. `extension",
            "/// YourType.StatelessNode { public func body(content: Content) -> some View",
            "/// { ... } }`.",
        ]
    case .none:
        hostDocLines = []
    }
    let hostDocComment = hostDocLines.isEmpty ? "" : hostDocLines.joined(separator: "\n") + "\n"

    let statelessStruct = DeclSyntax(
        stringLiteral: """
            \(hostDocComment)@DataLayout
            \(access)struct StatelessNode\(conformance) {
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
    let statelessProperty = DeclSyntax(
        stringLiteral: """
            \(access)var statelessNode: StatelessNode {
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
