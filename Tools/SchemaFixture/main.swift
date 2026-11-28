import CraftberryCore
import Foundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let samples = try [
    AddOnProject.materialStructureSet(materialName: "Schema Structure", originalPrompt: "Schema fixture"),
    AddOnProject.materialSwordSet(materialName: "Schema Sword", originalPrompt: "Schema fixture"),
    AddOnProject.materialFurnaceSet(materialName: "Schema Furnace", originalPrompt: "Schema fixture"),
    AddOnProject.materialSmithingSet(materialName: "Schema Smithing", originalPrompt: "Schema fixture"),
    AddOnProject.materialBrewingSet(materialName: "Schema Brewing", originalPrompt: "Schema fixture"),
    AddOnProject.materialHostileEntitySet(materialName: "Schema Hostile", originalPrompt: "Schema fixture"),
    AddOnProject.materialBossEntitySet(materialName: "Schema Boss", originalPrompt: "Schema fixture"),
    AddOnProject.biomeSet(biomeName: "Schema Biome", originalPrompt: "Schema fixture"),
    AddOnProject.materialCropSet(materialName: "Schema Crop", originalPrompt: "Schema fixture"),
    AddOnProject.materialConsumableSet(materialName: "Schema Food", originalPrompt: "Schema fixture"),
    AddOnProject.materialArmorSet(materialName: "Schema Armor", originalPrompt: "Schema fixture"),
    AddOnProject.materialOreSet(materialName: "Schema Ore", originalPrompt: "Schema fixture"),
    AddOnProject.materialBlockSet(materialName: "Schema Block", originalPrompt: "Schema fixture")
]
let identity = AddOnProjectIdentity.generate()
let project = AddOnProject(
    id: identity.projectID,
    namespace: identity.namespace,
    displayName: "Schema coverage fixture",
    shortDescription: "Exercises every generated behavior document family.",
    packUUIDs: identity.packUUIDs,
    buildVersion: VersionTriplet(major: 1, minor: 0, patch: 0),
    targetProfileID: BedrockContentProfile.current.id,
    originalPrompt: "Schema coverage fixture",
    content: samples.flatMap(\.content)
)
let result = try BedrockAddOnCompiler().compile(project: project, profile: .current, outputDirectory: directory)
print(result.artifact.url.path)
