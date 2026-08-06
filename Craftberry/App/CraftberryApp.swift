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
        CreationViewModel(
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
    }
}

private struct UITestingLLMClient: LLMClient {
    func generateProject(from prompt: String) async throws -> ProjectGeneration {
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let usesEmerald = ProcessInfo.processInfo.arguments.contains("--ui-testing-emerald-sword")
        let usesRedstoneToolSet = ProcessInfo.processInfo.arguments.contains("--ui-testing-redstone-tool-set")
        let usesRedstoneWeaponSet = ProcessInfo.processInfo.arguments.contains("--ui-testing-redstone-weapon-set")
        let usesFreshPackIdentity = ProcessInfo.processInfo.arguments.contains("--ui-testing-fresh-pack-identity")
        let identity = usesFreshPackIdentity ? AddOnProjectIdentity.generate() : fixedUITestingIdentity
        let project: AddOnProject
        if usesRedstoneWeaponSet {
            project = try AddOnProject.materialWeaponSet(
                materialName: "Redstone",
                color: .red,
                sourceItem: "minecraft:redstone",
                sourceCount: 4,
                originalPrompt: prompt,
                identity: identity
            )
        } else if usesRedstoneToolSet {
            project = try AddOnProject.materialToolSet(
                materialName: "Redstone",
                color: .red,
                sourceItem: "minecraft:redstone",
                sourceCount: 4,
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
