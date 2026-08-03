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
        let project = try AddOnProject.sword(
            displayName: "Cyan Test Sword",
            color: .cyan,
            attackBonus: 14,
            durability: 500,
            craftingIngredient: "minecraft:diamond",
            originalPrompt: prompt,
            identity: AddOnProjectIdentity(
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
        )
        return ProjectGeneration(outcome: .ready, message: "Ready", project: project)
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
