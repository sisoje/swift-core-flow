import DataMacros
import Foundation
import SwiftUI

// MARK: - MemberwiseInit

// @MemberwiseInit writes the memberwise initializer at the struct's own access
// level — the `public init` Swift refuses to synthesize for a public type — plus a
// `DataLayout` typealias bundling the same properties into a tuple alongside it:
// `public typealias DataLayout = (id: UUID, name: String, isActive: Bool, onmain: @MainActor () -> Void,
//     onChange: () async -> Void, onRename: @Sendable (String, Int) async -> Void, onDone: (() -> Void)?)`
// — no defaults, no @escaping, unlike the init right above it (tuple element types
// support neither).

@MemberwiseInit
public struct User {
    static let x: Int = 0
    static var y: Int {
        0
    }

    var x: Int {
        0
    }

    public let id: UUID
    public let name: String
    var isActive: Bool = false  // inline default → defaulted parameter
    public let onmain: @MainActor () -> Void
    public let onChange: () async -> Void  // function type → @escaping param
    public let onRename: @Sendable (String, Int) async -> Void  // attributed function type → @escaping param
    public var onDone: (() -> Void)?  // optional var → `= nil` param, no @escaping
}

@MemberwiseInit
@Observable public final class Settings {
    var count: Int = 0  // one property → `typealias DataLayout = Int`, no 1-tuple
}

// On a View: @State/@Environment are private, so they're excluded; @Binding is
// threaded as Binding<Bool>; @ViewBuilder carries onto the parameters. Generated init:
// `init(isOn: Binding<Bool>, title: String, subtitle: String? = nil, model: Settings,
//       @ViewBuilder content: @escaping () -> Content, @ViewBuilder footer: () -> Content)`.
// The DataLayout typealias diverges from that init in two ways: no default for
// subtitle, and footer keeps its own type (`Content`) instead of the `() -> Content`
// builder the init uses — `typealias DataLayout = (isOn: Binding<Bool>, title: String,
// subtitle: String?, model: Settings, content: () -> Content, footer: Content)`.
@MemberwiseInit
public struct ProfileCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded = false
    @Binding var isOn: Bool
    let title: String
    var subtitle: String?

    @Bindable var model: Settings

    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: Content

    public var body: some View {
        VStack {
            Text(isExpanded ? "Expanded" : "Collapsed")
            content()
            footer
        }
    }
}

// MARK: - TuplePicker

let store = (expenses: [12, 40, 7], limit: 100, name: "Groceries")
let actions = (alerts: ["low battery"], submit: {})

// #pick — multiple sources into one tuple
let merged = #pick(from: store, \.expenses => "zzz", \.limit, from: actions, \.alerts)

// #pick — picking 2 out of 11 fields from one large tuple
let big = (val1: 1, val2: 2, val3: 3, val4: 4, val5: 5, val6: 6, val7: 7, val8: 8, val9: 9, val10: 10, val11: 11)
let twoOfEleven = #pick(from: big, \.val3, \.val11)

// MARK: - Capability

// @Capability bundles every eligible computed property/method into one
// `Capability` tuple typealias + `capability` computed property. Unlike
// @MemberwiseInit, it works fine on an extension — it collects
// COMPUTED members (which extensions can declare), not stored ones (which they
// can't). `me`, `zola`, `zola2` (stored) don't participate; `x` (computed),
// `doSomething`, `doSomethingElse`, `meme` (methods) do. Generated:
// `typealias Capability = (x: Int, doSomething: () -> Void, doSomethingElse: () -> Void, meme: () async throws -> Void)`
// `var capability: Capability { (x, doSomething, doSomethingElse, meme) }`
// No @Sendable on the fields — marking them unconditionally would fail to
// compile for any type capturing something non-Sendable; Swift 6's region-based
// checking already permits crossing actor/Task boundaries without it when the
// captured content actually is safe.
struct MySomething {
    private var me = 0
    let zola: Int
    var zola2: Int = 0
}

@Capability
@MainActor
extension MySomething {
    var x: Int {
        zola * me
    }

    func doSomething() {
        print(zola)
    }

    func doSomethingElse() {
        print(zola2)
    }

    func meme() async throws {
        try await Task.sleep(nanoseconds: 1)
    }
}
