// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReadingListUI",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "ReadingListUI", targets: ["ReadingListUI"])
    ],
    dependencies: [
        .package(name: "CoreFlow", path: "../..")
    ],
    targets: [
        .target(
            name: "ReadingListUI",
            dependencies: [.product(name: "CoreFlow", package: "CoreFlow")]
        )
    ]
)
