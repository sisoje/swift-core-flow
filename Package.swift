// swift-tools-version: 6.4
import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "CoreFlow",
    platforms: [
        .macOS(.v14), .iOS(.v17), .tvOS(.v17), .watchOS(.v10), .visionOS(.v1), .macCatalyst(.v17),
    ],
    products: [
        .library(name: "CoreFlow", targets: ["CoreFlow"]),
    ],
    dependencies: [
        // swift-syntax 6xx matches Swift 6.x toolchains (601 = 6.1, 602 = 6.2, ... 604 = 6.4).
        // The macro APIs used here are stable across the whole 6xx line.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0" ..< "700.0.0"),
    ],
    targets: [
        // Every macro's implementation, compiled as one compiler plugin; never ships
        // to consumers. One file per macro (FlowableMacro.swift, ShellMacro.swift,
        // CapabilityMacro.swift, PickMacro.swift, TestSupportMacros.swift,
        // TestFocusStateMacro.swift, UnstructuredTaskMacro.swift, FlowUpMacro.swift),
        // plus the shared stored-property collection + rendering helpers
        // (StoredProperty.swift, MemberMacroEntry.swift, FieldRendering.swift,
        // FlowableRendering.swift, ShellRendering.swift) that @Flowable builds on
        // and @Shell reuses, and TuplePicker's own key-path parsing
        // (KeyPathPick.swift, TuplePickerSupport.swift). One Plugin.swift lists
        // every macro type.
        .macro(
            name: "CoreFlowMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        // The public-facing library: every macro's attribute/expression declaration,
        // one file per macro (Flowable.swift, Shell.swift, Capability.swift,
        // TuplePicker.swift, UnstructuredTask.swift, FlowUp.swift, and the
        // TestSupport/ directory: TestLog, UITestLogging, TestState, TestAction,
        // TestFocusState), plus the non-macro runtime: QueryResult.swift,
        // QueryView.swift, and the Experimental/ directory — Reflector.swift and
        // SectionedResults+Mock.swift, implementation-dependent runtime
        // techniques (uninitialized-memory reflection, memory-layout
        // fabrication) kept apart on purpose.
        .target(name: "CoreFlow", dependencies: ["CoreFlowMacros"]),
        // Expansion tests — `assertMacroExpansion` snapshots + diagnostics, one
        // file per macro, against the plugin module itself.
        .testTarget(
            name: "CoreFlowExpansionTests",
            dependencies: [
                "CoreFlowMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
        // Compiled/runtime tests against the product, one file per API. XCTest
        // and swift-testing coexist fine in one test target.
        .testTarget(name: "CoreFlowTests", dependencies: ["CoreFlow"]),
    ],
    swiftLanguageModes: [.v6]
)
