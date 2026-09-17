import SwiftUI

/// A value memoized by dependencies: `value(for:build:)` runs `build` only when
/// they differ from the last ones. A plain class meant to live in `@State` — a
/// render-phase write to a plain object, no SwiftUI state write.
final class Memo<Value> {
    private var dependencies: [any Equatable] = []
    private var value: Value?

    func value(for dependencies: [any Equatable], build: () -> Value) -> Value {
        if let value, Self.isSame(dependencies, self.dependencies) {
            return value
        }
        self.dependencies = dependencies
        let built = build()
        value = built
        return built
    }

    /// Pairwise equality; two values of different types are different.
    private static func isSame(_ lhs: [any Equatable], _ rhs: [any Equatable]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (element, other) in zip(lhs, rhs) where !isSame(element, other) {
            return false
        }
        return true
    }

    private static func isSame<Element: Equatable>(_ element: Element, _ other: Any) -> Bool {
        (other as? Element) == element
    }
}

/// A value built from the view's inputs, kept across renders, rebuilt only
/// when its `dependencies` change — React's `useMemo` as a view. `@State`
/// builds its value once and ignores every later input; this one follows its
/// inputs without an `.id()` reset of the subtree.
///
/// `dependencies` are the values that take part in building `value`, those and
/// only those; a value left out is a change the memoized value will not
/// follow. `content` is not gated and reads whatever state it wants. The value
/// is derived, not a source of truth: `MemoView` hands it out, it does not
/// write it.
public struct MemoView<Value, Content: View>: View {
    public init(
        _ value: @autoclosure @escaping () -> Value,
        dependencies: [any Equatable] = [],
        @ViewBuilder content: @escaping (Value) -> Content
    ) {
        self.value = value
        self.dependencies = dependencies
        self.content = content
    }

    @State private var memo = Memo<Value>()
    let value: () -> Value
    let dependencies: [any Equatable]
    let content: (Value) -> Content

    public var body: some View {
        content(memo.value(for: dependencies, build: value))
    }
}
