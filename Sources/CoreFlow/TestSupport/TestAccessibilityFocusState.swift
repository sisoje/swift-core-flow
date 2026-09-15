import SwiftUI

/// A drop-in `@AccessibilityFocusState` that logs — `@TestFocusState` over
/// the accessibility wrapper, which is an exact `@FocusState` clone: the same
/// `Bool`-or-optional values, a real `AccessibilityFocusState` peer held by
/// the macro so hosted behavior is the live wrapper's own, and every
/// programmatic write logged `(name, newValue)` through `\.testLog`:
///
/// ```swift
/// @TestAccessibilityFocusState private var isFocused: Bool
/// Text("hint").accessibilityFocused($isFocused)   // $isFocused IS AccessibilityFocusState<Bool>.Binding
/// Button("focus") { isFocused = true }            // logs ("isFocused", "true")
/// ```
///
/// `$name` forwards the REAL `AccessibilityFocusState<T>.Binding`, so
/// assistive-technology focus moving through it does not log; the property
/// logs, the projection wires. Same shape rules as `@TestFocusState`: a
/// stored instance `var` with a type annotation and no initial value,
/// anything else a compile error at the attribute; every generated member
/// private; unhosted a no-op. `@Shell` substitutes it for a private
/// `@AccessibilityFocusState` on `Core`.
@attached(accessor, names: named(get), named(set))
@attached(peer, names: prefixed(`$`), prefixed(log_), suffixed(_storage))
public macro TestAccessibilityFocusState() =
    #externalMacro(module: "CoreFlowMacros", type: "TestAccessibilityFocusStateMacro")
