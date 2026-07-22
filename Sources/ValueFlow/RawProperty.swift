/// Exposes a property wrapper's synthesized `_name` backing storage at
/// internal access, as a `raw_name` peer. SE-0258 hardcodes that storage:
/// "The synthesized storage property is always named with a leading `_` and
/// is always `private`" — no spelling loosens it, so the wrapper *instance*
/// on a constructed value can never be swapped (a `Binding`, seeded state,
/// mocked SwiftData state). This macro overcomes that.
/// https://github.com/swiftlang/swift-evolution/blob/main/proposals/0258-property-wrappers.md
///
/// ```swift
/// @RawProperty @Binding var isOn: Bool
/// // generates:
/// // var raw_isOn: Binding<Bool> {
/// //     get { _isOn }
/// //     set { _isOn = newValue }
/// // }
/// ```
///
/// The wrapper type is inferred syntax-only: generics written on the
/// attribute (`@Binding<Bool>`) are used verbatim, otherwise the binding's
/// type annotation fills the generic — no annotation and no generics is a
/// diagnostic. Attaching it to something without a wrapper attribute is a
/// diagnostic too (there's no backing storage to expose).
@attached(peer, names: prefixed(raw_))
public macro RawProperty() =
    #externalMacro(module: "ValueFlowMacros", type: "RawPropertyMacro")
