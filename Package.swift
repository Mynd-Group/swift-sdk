// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MyndCore",

    platforms: [
        .iOS(.v14),
        .macOS(.v14)
    ],

    products: [
        .library(
            name: "MyndCore",
            targets: ["MyndCore"]
        ),
    ],
    targets: [
        .target(
            name: "MyndCore"
        ),
        .testTarget(
            name: "MyndCoreTests",
            dependencies: ["MyndCore"]
        ),
    ]
)
