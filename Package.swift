// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SwiftSDK",

    platforms: [
        .iOS(.v14),
        .macOS(.v10_15),
    ],

    products: [
        // Your library (unchanged)
        .library(
            name: "SwiftSDK",
            targets: ["SwiftSDK"]
        ),

        // Optional: make the CLI runnable/dispatchable via SPM
        .executable(
            name: "terminal-app",  // any lowercase name you like
            targets: ["TerminalApp"]
        ),
    ],

    targets: [
        // Library target
        .target(
            name: "SwiftSDK"
        ),

        // CLI target (folder: Sources/TerminalApp)
        .executableTarget(
            name: "TerminalApp",
            dependencies: ["SwiftSDK"]
            // , path: "Sources/TerminalApp"   // add if the folder is not the default
        ),

        // Test target
        .testTarget(
            name: "SwiftSDKTests",
            dependencies: ["SwiftSDK"]
        ),
    ]
)
