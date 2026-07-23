// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HyperForge",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "HyperForge", targets: ["HyperForge"]),
        .executable(name: "HyperForgeSmoke", targets: ["HyperForgeSmoke"]),
        .library(name: "HyperForgeKit", targets: ["HyperForgeKit"]),
    ],
    targets: [
        .target(
            name: "HyperForgeKit",
            path: "Sources/HyperForgeKit"
        ),
        .executableTarget(
            name: "HyperForge",
            dependencies: ["HyperForgeKit"],
            path: "Sources/HyperForge",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Combine"),
            ]
        ),
        .executableTarget(
            name: "HyperForgeSmoke",
            dependencies: ["HyperForgeKit"],
            path: "Sources/HyperForgeSmoke"
        ),
        // XCTest target — requires full Xcode (not Command Line Tools alone).
        .testTarget(
            name: "HyperForgeTests",
            dependencies: ["HyperForgeKit"],
            path: "Tests/HyperForgeTests"
        ),
    ]
)
