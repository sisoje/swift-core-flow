import DataMacros
import Foundation
import SwiftUI

// MARK: - MemberwiseInit

// @MemberwiseInit writes the memberwise initializer at the struct's own access
// level — the `public init` Swift refuses to synthesize for a public type.

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
    var count: Int = 0
}

// On a View: @State/@Environment are private, so they're excluded; @Binding is
// threaded as Binding<Bool>; @ViewBuilder carries onto the parameters. Generated init:
// `init(isOn: Binding<Bool>, title: String, subtitle: String? = nil, model: Settings,
//       @ViewBuilder content: @escaping () -> Content, @ViewBuilder footer: () -> Content)`.
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

// MARK: - DataLayoutInit

// @DataLayoutInit takes the same stored-property rules as @MemberwiseInit but
// bundles them into ONE tuple-typed `dataLayout` parameter instead of one parameter
// each. Two or more properties → a `DataLayout` typealias plus
// `init(_ dataLayout: DataLayout)`; call site: `SomeStruct((x: 1, y: $binding))`.
@DataLayoutInit
public struct SomeStruct {
    let x: Int
    @Binding var y: Int
}

// A single property still gets a DataLayout — just not a tuple (Swift has no
// 1-tuples: `(value: Int)` collapses to plain `Int`, no `.value` accessor). So
// `Box.DataLayout` aliases `Int` directly, and the init stays unlabeled:
// `init(_ value: DataLayout) { self.value = value }`.
@DataLayoutInit
public struct Box {
    let value: Int
}

// MARK: - DataInit

// @DataInit generates BOTH initializers from one attribute — everything
// @MemberwiseInit generates and everything @DataLayoutInit generates — collecting
// the stored properties once instead of stacking @DataLayoutInit @MemberwiseInit
// (which would collect, and diagnose, the same properties twice).
@DataInit
public struct Point {
    public let x: Int
    public let y: Int
}

let byProperty = Point(x: 1, y: 2)  // @MemberwiseInit-shaped init
let byLayout = Point((x: 1, y: 2))  // @DataLayoutInit-shaped init
