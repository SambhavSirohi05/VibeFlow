// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OneTake",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "OneTake", targets: ["OneTake"])
    ],
    targets: [
        .executableTarget(
            name: "OneTake",
            path: "Sources/OneTake",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
