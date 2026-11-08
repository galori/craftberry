import CraftberryCore
import Foundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let project = try AddOnProject.materialStructureSet(originalPrompt: "A hut made of azure blocks")
let result = try BedrockAddOnCompiler().compile(project: project, profile: .current, outputDirectory: directory)
print(result.artifact.url.path)
