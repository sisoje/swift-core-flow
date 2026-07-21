// TuplePicker — KeyPath-driven `#pick` macro, macro-paid nominal tax.

/// Use-site pick: `#pick(from: value, \.a, \.b)` → `(a: value.a, b: value.b)`.
/// One or more sources, each introduced by a real `from:` label, arbitrarily
/// many picks per source.
///
/// Single key path (one source, one pick) returns the bare value (Swift has
/// no 1-tuples). Chained key paths are supported (`\.a.b`) — the label is
/// the last component. Output field order is exactly the written order of
/// the key path arguments across every source (reordering is just writing
/// them in a different order).
///
/// RENAME a field with the `=>` operator — see its doc comment below for why
/// this shape and not a plain argument label. `\.limit => "total"` overrides
/// the derived label ("total" instead of "limit") while still typing as a
/// real `KeyPath`. Mixing renamed and bare picks, and reordering, compose
/// freely:
///
///     #pick(from: store, \.expenses, \.limit => "total")
///     // → (expenses: store.expenses, total: store.limit)
///
/// A second, third, ... source is just another `from:` group in the same
/// call — `from:` is a real, predeclared parameter label, one per source,
/// that marks the boundary between separate variadic pack parameters in the
/// signature (verified directly, both as a plain function and as this
/// macro's actual declaration; see the README):
///
///     #pick(from: store, \.expenses, \.limit, from: actions, \.alerts)
///     // → (expenses:, limit:, alerts:) — one tuple, two sources
///
/// The same source value can follow more than one `from:` — it's bound
/// once, in order of first appearance, not re-evaluated:
///
///     #pick(from: store, \.expenses, from: actions, \.alerts, from: store, \.name)
///     // store is bound once even though it appears after two `from:`s
///
/// Duplicate output labels (including a rename colliding with another
/// field's derived name) are a compile error with a Fix-It suggesting a
/// distinct rename.
///
/// Works on structs, classes, AND bare tuple values (`#pick(from: t, \.a,
/// \.b)` where `t: (a: Int, b: String)`) — see the README for why that
/// wasn't a given. Composes with itself only as two separate statements,
/// not one nested expression, REGARDLESS of arity — every arity shares the
/// same underlying implementation type, so Swift's macro-recursion guard
/// (keyed on implementation identity, not spelled name or arity) refuses
/// any `#pick` nested textually inside another; see the README.
///
/// One, two, and three source overloads are provided, fully typed (verified:
/// Swift accepts multiple independent parameter packs concatenated in one
/// tuple return type, each resolved from its own source's key paths) — a
/// fourth source has no matching overload and falls back to a plain "no
/// matching function" diagnostic.
@freestanding(expression)
public macro pick<T1, each V1>(
    from source1: T1,
    _ paths1: repeat KeyPath<T1, each V1>
) -> (repeat each V1) = #externalMacro(module: "ValueFlowMacros", type: "PickMacro")

/// `#pick`, two sources. See the doc comment on the one-source overload above.
@freestanding(expression)
public macro pick<T1, each V1, T2, each V2>(
    from source1: T1, _ paths1: repeat KeyPath<T1, each V1>,
    from source2: T2, _ paths2: repeat KeyPath<T2, each V2>
) -> (repeat each V1, repeat each V2) =
    #externalMacro(module: "ValueFlowMacros", type: "PickMacro")

/// `#pick`, three sources. See the doc comment on the one-source overload above.
@freestanding(expression)
public macro pick<T1, each V1, T2, each V2, T3, each V3>(
    from source1: T1, _ paths1: repeat KeyPath<T1, each V1>,
    from source2: T2, _ paths2: repeat KeyPath<T2, each V2>,
    from source3: T3, _ paths3: repeat KeyPath<T3, each V3>
) -> (repeat each V1, repeat each V2, repeat each V3) =
    #externalMacro(module: "ValueFlowMacros", type: "PickMacro")

/// Enables `\.field => "label"` inside `#pick` to rename a field's output
/// label. Real Swift argument labels (`total: \.limit`) can't appear inside
/// a `#pick` call — verified against the compiler, `total:` there is
/// rejected with "extra argument 'total' in macro expansion" no matter how
/// loosely `#pick`'s `paths` parameter is typed, because argument-label
/// matching happens against the declared parameter list before a variadic/
/// pack parameter's individual elements are ever considered, and there's no
/// way to declare a parameter that accepts an arbitrary caller-chosen label.
///
/// `=>` sidesteps that: it's a real operator returning the same `KeyPath`
/// type as its left operand, so `\.limit => "total"` still type-checks
/// against `#pick`'s existing `repeat KeyPath<T, each V>` parameter with
/// full inference (implicit root `\.limit` keeps working) — no loosened or
/// untyped fallback needed. `#pick` never actually evaluates `=>` at
/// runtime; it reads the operator syntax to recover the rename label, then
/// discards the original expression in favor of freshly emitted code.
///
/// NOTE: the first choice here was `~>` — it reads a little more like an
/// arrow-that-isn't-`->`. Rejected because `~>` is already declared by the
/// Swift standard library itself (`Swift.swiftinterface`, unconditionally
/// in scope everywhere), which collides: "ambiguous operator declarations
/// found for operator." `=>` was checked against the SDK's declared
/// operators before shipping and is collision-free.
infix operator => : AdditionPrecedence
public func => <Root, Value>(lhs: KeyPath<Root, Value>, rhs: String) -> KeyPath<Root, Value> { lhs }
