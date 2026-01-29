// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VibeFlow",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "VibeFlow", targets: ["VibeFlow"])
    ],
    targets: [
        .executableTarget(
            name: "VibeFlow",
            path: "Sources/VibeFlow"
        )
    ]
)
