import ProjectDescription

// The tests run the app as Mac Catalyst: no simulator to boot. A Catalyst app
// is a macOS process, so it must be signed (ad hoc is enough; unsigned, the
// test runner is killed at launch), and the hardened runtime stays off so the
// runner loads the ad-hoc test bundle.
let catalyst: SettingsDictionary = [
    "SUPPORTS_MACCATALYST": "YES",
    // iPad idiom. For a `.macCatalyst` destination Tuist adds 6, the Mac idiom,
    // where a Toggle is a checkbox and a sheet dismisses like macOS.
    "TARGETED_DEVICE_FAMILY": "1,2",
    "ENABLE_HARDENED_RUNTIME": "NO",
    "MACOSX_DEPLOYMENT_TARGET": "27.0",
    "CODE_SIGN_IDENTITY": "-",
    "SWIFT_VERSION": "6.0",
    "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
    // No plist file (`infoPlist: nil` below): Xcode synthesizes it, as under
    // xcodegen. A generated file is rewritten by every `tuist generate`, after
    // which an incremental build re-copies the test runner's Info.plist without
    // re-signing the runner, and it is killed at launch.
    "GENERATE_INFOPLIST_FILE": "YES",
]

let project = Project(
    name: "CoreFlowHosted",
    options: .options(automaticSchemesOptions: .disabled),
    // Xcode's own SwiftPM integration, like xcodegen's `packages:`.
    packages: [.package(path: "..")],
    targets: [
        // The scenarios live here, not in the package; each launch picks one
        // from the TestPayload in its environment.
        .target(
            name: "CoreFlowHostApp",
            destinations: [.iPhone, .iPad, .macCatalyst],
            product: .app,
            bundleId: "com.coreflow.hosted.CoreFlowHostApp",
            deploymentTargets: .iOS("27.0"),
            infoPlist: nil,
            sources: ["HostApp/**", "Shared/**"],
            dependencies: [.package(product: "CoreFlow")],
            settings: .settings(base: catalyst.merging([
                "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
                "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
                "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
            ]) { $1 })
        ),
        // No MainActor default: XCTestCase's inherited inits are nonisolated.
        .target(
            name: "CoreFlowHostUITests",
            destinations: [.iPhone, .iPad, .macCatalyst],
            product: .uiTests,
            bundleId: "com.coreflow.hosted.CoreFlowHostUITests",
            deploymentTargets: .iOS("27.0"),
            infoPlist: nil,
            sources: ["UITests/**", "Shared/**"],
            dependencies: [
                .target(name: "CoreFlowHostApp"),
                .package(product: "CoreFlowUITesting"),
            ],
            settings: .settings(base: catalyst)
        ),
    ],
    schemes: [
        .scheme(
            name: "CoreFlowHostApp",
            buildAction: .buildAction(targets: ["CoreFlowHostApp"]),
            testAction: .targets(["CoreFlowHostUITests"], options: .options(coverage: true)),
            runAction: .runAction()
        ),
    ]
)
