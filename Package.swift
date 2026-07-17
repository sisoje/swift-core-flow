// swift-tools-version: 6.3
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "DataMacros",
    platforms: [
        .macOS(.v14), .iOS(.v17), .tvOS(.v17), .watchOS(.v10), .visionOS(.v1), .macCatalyst(.v17),
    ],
    products: [
        .library(name: "DataMacros", targets: ["DataMacros"]),
    ],
    dependencies: [
        // swift-syntax 6xx matches Swift 6.x toolchains (601 = 6.1, 602 = 6.2, ... 604 = 6.4).
        // The macro APIs used here are stable across the whole 6xx line.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0" ..< "700.0.0"),
    ],
    targets: [
        // Every macro's implementation, compiled as one compiler plugin; never ships
        // to consumers. One file per macro (DataLayoutMacro.swift,
        // CapabilityMacro.swift, PickMacro.swift), plus the shared stored-property
        // collection + rendering helpers (StoredProperty.swift, MemberMacroEntry.swift,
        // FieldRendering.swift, DataLayoutRendering.swift) that @DataLayout
        // builds on, and TuplePicker's own key-path parsing (KeyPathPick.swift,
        // TuplePickerSupport.swift). One Plugin.swift lists every macro type.
        .macro(
            name: "DataMacrosMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        // The public-facing library: every macro's attribute/expression declaration,
        // one file per macro (DataLayout.swift, Capability.swift,
        // TuplePicker.swift).
        .target(name: "DataMacros", dependencies: ["DataMacrosMacros"]),
        // All tests — macro-expansion + diagnostic coverage per macro, plus
        // TuplePicker's real-compiled end-to-end suite. XCTest and swift-testing
        // coexist fine in one test target.
        .testTarget(
            name: "DataMacrosTests",
            dependencies: [
                "DataMacrosMacros",
                "DataMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
        // One playground exercising every macro in the package.
        .executableTarget(
            name: "Examples",
            dependencies: ["DataMacros"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
