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
        .library(
            name: "SwiftSDK",
            targets: ["SwiftSDK"]
        ),
    ],
    targets: [
        // Library target
        .target(
            name: "MyndCore"
        ),
        .target(
            name: "SwiftSDK"
        ),
        // Test target
        .testTarget(
            name: "MyndCoreTests",
            dependencies: ["MyndCore"]
        ),
    ]
)
