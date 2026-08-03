// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Craftberry",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "CraftberryCore", targets: ["CraftberryCore"])
    ],
    targets: [
        .target(name: "CraftberryCore", path: "Craftberry/Core"),
        .testTarget(name: "CraftberryTests", dependencies: ["CraftberryCore"], path: "CraftberryTests"),
        .executableTarget(name: "MinecraftFixture", dependencies: ["CraftberryCore"], path: "Tools/MinecraftFixture")
    ]
)
