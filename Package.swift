// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CCMeter",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CCMeter", targets: ["CCMeter"])
    ],
    targets: [
        .executableTarget(
            name: "CCMeter",
            path: "Sources/CCMeter"
        ),
        .testTarget(
            name: "CCMeterTests",
            dependencies: ["CCMeter"],
            path: "Tests/CCMeterTests"
        )
    ]
)
