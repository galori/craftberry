// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Craftberry",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "CraftberryCore", targets: ["CraftberryCore"]),
        .executable(name: "GenerationServer", targets: ["GenerationServer"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
        .target(name: "CraftberryCore", dependencies: ["CSQLite"], path: "Craftberry/Core"),
        .testTarget(
            name: "CraftberryTests",
            dependencies: ["CraftberryCore", "CSQLite"],
            path: "CraftberryTests",
            resources: [.copy("Fixtures/GenerationV1.json"), .copy("Fixtures/AppAttest")]
        ),
        .executableTarget(
            name: "GenerationServer",
            dependencies: ["CraftberryCore"],
            path: "Tools/GenerationServer",
            resources: [
                .copy("Resources/Apple_App_Attestation_Root_CA.pem"),
                .copy("Resources/AppleRootCA-G3.cer")
            ]
        ),
        .executableTarget(name: "MinecraftFixture", dependencies: ["CraftberryCore"], path: "Tools/MinecraftFixture"),
        .executableTarget(name: "SchemaFixture", dependencies: ["CraftberryCore"], path: "Tools/SchemaFixture"),
        .executableTarget(name: "IconPreview", dependencies: ["CraftberryCore"], path: "Tools/IconPreview")
    ]
)
