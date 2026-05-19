// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeCodeMenubar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ClaudeCodeMenubar", targets: ["ClaudeCodeMenubar"])
    ],
    targets: [
        .executableTarget(
            name: "ClaudeCodeMenubar",
            path: "Sources/ClaudeCodeMenubar"
        ),
        .testTarget(
            name: "ClaudeCodeMenubarTests",
            dependencies: ["ClaudeCodeMenubar"],
            path: "Tests/ClaudeCodeMenubarTests"
        )
    ]
)
