import CraftberryCore
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fail("usage: MinecraftFixture <output-directory> [display-name]")
}

let outputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
let displayName = arguments.count >= 3
    ? arguments[2]
    : "Mirror Test \(Int(Date().timeIntervalSince1970))"

do {
    let project = try AddOnProject.sword(
        displayName: displayName,
        color: .cyan,
        attackBonus: 14,
        durability: 500,
        craftingIngredient: "minecraft:diamond",
        originalPrompt: "A cyan sword, 14 damage, crafted from diamonds"
    )
    let result = try BedrockAddOnCompiler().compile(
        project: project,
        profile: .current,
        outputDirectory: outputDirectory
    )
    let payload: [String: String] = [
        "artifactPath": result.artifact.url.path,
        "fileName": result.artifact.fileName,
        "displayName": displayName
    ]
    let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    fail("error: \(error)")
}
