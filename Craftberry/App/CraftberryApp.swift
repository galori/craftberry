#if canImport(SwiftUI)
import SwiftUI

@main
struct CraftberryApp: App {
    @StateObject private var viewModel: CreationViewModel

    init() {
        _viewModel = StateObject(wrappedValue: Self.makeViewModel())
    }

    var body: some Scene {
        WindowGroup {
            CreationView(viewModel: viewModel)
        }
    }

    private static func makeViewModel() -> CreationViewModel {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            return CreationViewModel.uiTesting()
        }
        #endif

        return CreationViewModel(
            apiKey: Bundle.main.object(forInfoDictionaryKey: "OpenAIAPIKey") as? String ?? ""
        )
    }
}

#if DEBUG
private extension CreationViewModel {
    static func uiTesting() -> CreationViewModel {
        let viewModel = CreationViewModel(
            apiKey: "",
            compiler: UITestingCompiler(),
            client: UITestingLLMClient(),
            artifactDirectoryProvider: {
                FileManager.default.temporaryDirectory.appending(
                    path: "CraftberryUITesting",
                    directoryHint: .isDirectory
                )
            }
        )

        if ProcessInfo.processInfo.arguments.contains("--ui-testing-open-project"),
           let project = try? AddOnProject.sword(
               displayName: "Saved Cyan Sword",
               color: .cyan,
               attackBonus: 12,
               durability: 400,
               craftingIngredient: "minecraft:diamond",
               originalPrompt: "A saved cyan sword",
               identity: AddOnProjectIdentity.generate()
           ) {
            let sidecarURL = FileManager.default.temporaryDirectory
                .appending(path: "CraftberryUITestingSidecars/saved-project.json")
            do {
                try AddOnProjectStore.save(project, to: sidecarURL)
                viewModel.openProject(from: sidecarURL)
            } catch {
                viewModel.reportProjectFileError(error)
            }
        }

        return viewModel
    }
}

private struct UITestingLLMClient: LLMClient {
    func generateProject(from prompt: String) async throws -> ProjectGeneration {
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let usesEmerald = ProcessInfo.processInfo.arguments.contains("--ui-testing-emerald-sword")
        let usesRedstoneToolSet = ProcessInfo.processInfo.arguments.contains("--ui-testing-redstone-tool-set")
        let usesRedstoneWeaponSet = ProcessInfo.processInfo.arguments.contains("--ui-testing-redstone-weapon-set")
        let usesRedstoneArmorSet = ProcessInfo.processInfo.arguments.contains("--ui-testing-redstone-armor-set")
        let usesRedstoneConsumableSet = ProcessInfo.processInfo.arguments.contains("--ui-testing-redstone-consumable-set")
        let usesRedstoneBlockSet = ProcessInfo.processInfo.arguments.contains("--ui-testing-redstone-block-set")
        let usesRedstoneSmithingSet = ProcessInfo.processInfo.arguments.contains("--ui-testing-redstone-smithing-set")
        let usesRedstoneFurnaceSet = ProcessInfo.processInfo.arguments.contains("--ui-testing-redstone-furnace-set")
        let usesRedstoneBrewingSet = ProcessInfo.processInfo.arguments.contains("--ui-testing-redstone-brewing-set")
        let usesRedstoneStructureSet = ProcessInfo.processInfo.arguments.contains("--ui-testing-redstone-structure-set")
        let usesRedstoneOreSet = ProcessInfo.processInfo.arguments.contains("--ui-testing-redstone-ore-set")
        let usesRedstoneCropSet = ProcessInfo.processInfo.arguments.contains("--ui-testing-redstone-crop-set")
        let usesRedstoneHostileEntitySet = ProcessInfo.processInfo.arguments.contains("--ui-testing-redstone-hostile-entity-set")
        let usesRedstoneEnchantableSwordSet = ProcessInfo.processInfo.arguments.contains("--ui-testing-redstone-enchantable-sword-set")
        let usesFreshPackIdentity = ProcessInfo.processInfo.arguments.contains("--ui-testing-fresh-pack-identity")
        let usesRevisionFlow = ProcessInfo.processInfo.arguments.contains("--ui-testing-revision-flow")
        let identity = usesFreshPackIdentity ? AddOnProjectIdentity.generate() : fixedUITestingIdentity
        let project: AddOnProject
        if usesRedstoneHostileEntitySet {
            project = try AddOnProject.materialHostileEntitySet(
                materialName: "Redstone",
                color: .red,
                sourceItem: "minecraft:redstone",
                sourceCount: 4,
                health: 24,
                shortDescription: "A redstone hostile creature with a craftable spawn egg.",
                originalPrompt: prompt,
                identity: identity
            )
        } else if usesRedstoneEnchantableSwordSet {
            project = try AddOnProject.materialSwordSet(
                materialName: "Redstone",
                color: .red,
                sourceItem: "minecraft:redstone",
                sourceCount: 4,
                swordDisplayName: "Redstone Sword",
                attackBonus: 10,
                durability: 500,
                shortDescription: "A redstone ingot kit with a custom enchantable sword.",
                originalPrompt: prompt,
                identity: identity
            )
        } else if usesRevisionFlow && prompt.trimmingCharacters(in: .whitespacesAndNewlines) == "Increase the sword's damage" {
            project = try AddOnProject.sword(
                displayName: "Cyan Test Sword",
                color: .cyan,
                attackBonus: 20,
                durability: 500,
                craftingIngredient: "minecraft:diamond",
                shortDescription: "A stronger cyan test sword.",
                originalPrompt: prompt,
                identity: identity
            )
        } else if usesRedstoneOreSet {
            project = try AddOnProject.materialOreSet(
                materialName: "Redstone",
                color: .red,
                sourceItem: "minecraft:redstone",
                sourceCount: 4,
                destroyTime: 3.0,
                mapColor: "#B01A14",
                shortDescription: "A redstone ore kit with a custom ingot and ore block.",
                originalPrompt: prompt,
                identity: identity
            )
        } else if usesRedstoneCropSet {
            project = try AddOnProject.materialCropSet(
                materialName: "Redstone",
                color: .red,
                sourceItem: "minecraft:redstone",
                sourceCount: 4,
                shortDescription: "A redstone crop kit with seeds, crop block, and produce.",
                originalPrompt: prompt,
                identity: identity
            )
        } else if usesRedstoneBrewingSet {
            project = try AddOnProject.materialBrewingSet(
                materialName: "Redstone",
                color: .red,
                sourceItem: "minecraft:redstone",
                sourceCount: 4,
                shortDescription: "A redstone brewing kit with a custom ingot and brewing-stand elixir.",
                originalPrompt: prompt,
                identity: identity
            )
        } else if usesRedstoneFurnaceSet {
            project = try AddOnProject.materialFurnaceSet(
                materialName: "Redstone",
                color: .red,
                sourceItem: "minecraft:redstone",
                attackBonus: 10,
                durability: 500,
                shortDescription: "A redstone furnace kit with a furnace-smelted ingot and sword.",
                originalPrompt: prompt,
                identity: identity
            )
        } else if usesRedstoneStructureSet {
            project = try AddOnProject.materialStructureSet(
                materialName: "Redstone",
                color: .red,
                sourceItem: "minecraft:redstone",
                sourceCount: 4,
                destroyTime: 3.0,
                mapColor: "#B01A14",
                shortDescription: "A redstone structure kit with a custom ingot, storage block, and 3x3 hut shelter.",
                originalPrompt: prompt,
                identity: identity
            )
        } else if usesRedstoneBlockSet {
            project = try AddOnProject.materialBlockSet(
                materialName: "Redstone",
                color: .red,
                sourceItem: "minecraft:redstone",
                sourceCount: 4,
                destroyTime: 3.0,
                mapColor: "#B01A14",
                shortDescription: "A redstone block kit with a custom ingot and storage block.",
                originalPrompt: prompt,
                identity: identity
            )
        } else if usesRedstoneConsumableSet {
            project = try AddOnProject.materialConsumableSet(
                materialName: "Redstone",
                color: .red,
                sourceItem: "minecraft:redstone",
                sourceCount: 4,
                nutrition: 6,
                saturationModifier: "0.6",
                canAlwaysEat: false,
                fuelDuration: 12.0,
                shortDescription: "A redstone consumable kit with a custom ingot, food, and fuel.",
                originalPrompt: prompt,
                identity: identity
            )
        } else if usesRedstoneArmorSet {
            project = try AddOnProject.materialArmorSet(
                materialName: "Redstone",
                color: .red,
                sourceItem: "minecraft:redstone",
                sourceCount: 4,
                shortDescription: "A redstone armor kit with a custom ingot and four armor recipes.",
                originalPrompt: prompt,
                identity: identity
            )
        } else if usesRedstoneWeaponSet {
            project = try AddOnProject.materialWeaponSet(
                materialName: "Redstone",
                color: .red,
                sourceItem: "minecraft:redstone",
                sourceCount: 4,
                shortDescription: "A redstone melee kit with a custom ingot and four weapon recipes.",
                originalPrompt: prompt,
                identity: identity
            )
        } else if usesRedstoneSmithingSet {
            project = try AddOnProject.materialSmithingSet(
                materialName: "Redstone",
                color: .red,
                sourceItem: "minecraft:redstone",
                sourceCount: 4,
                attackBonus: 10,
                durability: 500,
                shortDescription: "A redstone smithing kit with a smithing-upgraded sword and armor trim.",
                originalPrompt: prompt,
                identity: identity
            )
        } else if usesRedstoneToolSet {
            project = try AddOnProject.materialToolSet(
                materialName: "Redstone",
                color: .red,
                sourceItem: "minecraft:redstone",
                sourceCount: 4,
                shortDescription: "A redstone tool kit with a custom ingot and five matching tools.",
                originalPrompt: prompt,
                identity: identity
            )
        } else {
            project = try AddOnProject.sword(
                displayName: usesEmerald ? "Emerald Test Sword" : "Cyan Test Sword",
                color: usesEmerald ? .green : .cyan,
                attackBonus: 14,
                durability: 500,
                craftingIngredient: usesEmerald ? "minecraft:emerald" : "minecraft:diamond",
                shortDescription: usesEmerald ? "A test emerald sword with a craftable Bedrock recipe." : "A cyan test sword with a craftable diamond recipe.",
                originalPrompt: prompt,
                identity: identity
            )
        }
        return ProjectGeneration(outcome: .ready, message: "Ready", project: project)
    }

    private var fixedUITestingIdentity: AddOnProjectIdentity {
        AddOnProjectIdentity(
            projectID: UUID(uuidString: "10000000-0000-4000-8000-000000000101")!,
            namespace: "craftberry",
            contentSuffix: "uitest",
            packUUIDs: PackUUIDs(
                behaviorHeader: UUID(uuidString: "20000000-0000-4000-8000-000000000101")!,
                behaviorModule: UUID(uuidString: "20000000-0000-4000-8000-000000000102")!,
                resourceHeader: UUID(uuidString: "20000000-0000-4000-8000-000000000103")!,
                resourceModule: UUID(uuidString: "20000000-0000-4000-8000-000000000104")!
            )
        )
    }
}

private struct UITestingCompiler: AddOnCompiling {
    private let compiler = BedrockAddOnCompiler()

    func compile(
        project: AddOnProject,
        profile: BedrockContentProfile,
        outputDirectory: URL
    ) throws -> BedrockCompilationResult {
        Thread.sleep(forTimeInterval: 4.0)
        return try compiler.compile(project: project, profile: profile, outputDirectory: outputDirectory)
    }
}
#endif
#endif
