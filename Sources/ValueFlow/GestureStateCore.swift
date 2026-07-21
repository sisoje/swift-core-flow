#if canImport(SwiftUI)
    import SwiftUI

    /// Drop-in stand-in for SwiftUI's `@GestureState` on a `Core` snapshot,
    /// wrapping the live wrapper *instance* captured off the host. One-to-one
    /// with the real wrapper's own surface — verified directly against the
    /// SwiftUI interface: `GestureState<Value>` exposes exactly `wrappedValue`
    /// (get-only) and `projectedValue` (itself, the value `.updating(_:)`
    /// takes) — so this forwards both to the captured instance and body code
    /// written against the live property moves onto `Core` unchanged:
    /// `dragOffset` reads the in-flight value, `.updating($dragOffset)` wires
    /// the gesture to the host's real storage.
    ///
    /// Wrapping the instance whole is what makes this survive every one of
    /// `GestureState`'s argument-carrying inits — `(wrappedValue:reset:)`,
    /// `(wrappedValue:resetTransaction:)`, and the `initialValue:` spellings —
    /// because the reset closure/transaction live *inside* the instance and
    /// come along for free. An earlier revision mirrored a fresh
    /// `@GestureState var` onto `Core` instead; it silently swapped a custom
    /// reset for the default one (proved by a live UI test:
    /// `TrickyDragCardUITests` in the ExampleApp), which is why the instance
    /// capture is the design that stayed. The gesture writes route to the
    /// *host's* storage — the host property remains the one source of truth.
    ///
    /// Mockable by seeding: `GestureStateCore(GestureState(wrappedValue: mock))`
    /// reads back `mock` outside a live view (verified directly — a seeded
    /// `GestureState` returns its seed when its storage was never installed),
    /// so a test or preview can render `Core` as if mid-gesture.
    ///
    /// The one init takes the `GestureState` instance, deliberately with no
    /// `init(wrappedValue:)` alternative — that one would make Swift's
    /// synthesized memberwise init take the bare value and sever the live
    /// wiring; taking only the instance makes the synthesized init take the
    /// wrapper type itself, the same mechanism `@Binding`/`@QueryCore` fields
    /// rely on.
    @propertyWrapper
    public struct GestureStateCore<Value> {
        public var wrappedValue: Value { projectedValue.wrappedValue }
        public let projectedValue: GestureState<Value>

        public init(_ gestureState: GestureState<Value>) {
            self.projectedValue = gestureState
        }
    }
#endif
