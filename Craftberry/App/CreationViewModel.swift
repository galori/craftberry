#if canImport(SwiftUI)
import Foundation
#if canImport(CraftberryCore)
import CraftberryCore
#endif

@MainActor
final class CreationViewModel: ObservableObject {
    enum State {
        case editing
        case generating
        case unsupported(String)
        case ready(AddOnProject)
        case building(AddOnProject)
        case buildingWorld(AddOnProject, BedrockCompilationResult, BedrockWorldGameMode)
        case built(AddOnProject, BedrockCompilationResult)
        case failed(String)
    }

    @Published var prompt = ""
    @Published private(set) var state: State = .editing

    var isBusy: Bool {
        switch state {
        case .generating, .building, .buildingWorld: true
        default: false
        }
    }

    private let client: any LLMClient
    private let compiler: any AddOnCompiling
    private let worldExporter: any AddOnWorldExporting
    private let artifactDirectoryProvider: @MainActor () throws -> URL
    private let revisionService: AddOnRevisionService

    @Published private(set) var lastRevisionSummary: ChangeSummary?

    init(
        apiKey: String,
        compiler: any AddOnCompiling = BedrockAddOnCompiler(),
        worldExporter: any AddOnWorldExporting = BedrockWorldExporter(),
        client: (any LLMClient)? = nil,
        revisionService: AddOnRevisionService? = nil,
        artifactDirectoryProvider: @escaping @MainActor () throws -> URL = CreationViewModel.defaultArtifactDirectory
    ) {
        if let client {
            self.client = client
        } else {
            self.client = CachingLLMClient(wrapping: OpenAIResponsesClient(apiKey: apiKey))
        }
        self.compiler = compiler
        self.worldExporter = worldExporter
        self.artifactDirectoryProvider = artifactDirectoryProvider
        self.revisionService = revisionService ?? AddOnRevisionService(compiler: compiler)
    }

    func generate() async {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            state = .failed("Describe the add-on you want to create first.")
            return
        }
        state = .generating
        do {
            let generation = try await client.generateProject(from: trimmedPrompt)
            switch generation.outcome {
            case .ready:
                guard let project = generation.project else { throw LLMClientError.invalidResponse }
                let report = AddOnProjectValidator.validate(project, profile: .current)
                guard report.isSuccessful else {
                    throw BedrockCompilationError.invalidProject(report)
                }
                state = .ready(project)
            case .unsupported:
                state = .unsupported(generation.message)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    @discardableResult
    func buildArtifact(_ project: AddOnProject) async -> BedrockCompilationResult? {
        state = .building(project)
        await Task.yield()
        do {
            let directory = try artifactDirectoryProvider()
            let compiler = compiler
            let result = try await Task.detached(priority: .userInitiated) {
                try compiler.compile(
                    project: project,
                    profile: .current,
                    outputDirectory: directory
                )
            }.value
            state = .built(project, result)
            return result
        } catch {
            state = .failed(error.localizedDescription)
            return nil
        }
    }

    @discardableResult
    func buildWorld(
        project: AddOnProject,
        addOn: BedrockCompilationResult,
        gameMode: BedrockWorldGameMode
    ) async -> BedrockWorldCompilationResult? {
        state = .buildingWorld(project, addOn, gameMode)
        await Task.yield()
        do {
            let directory = try artifactDirectoryProvider()
            let worldExporter = worldExporter
            let result = try await Task.detached(priority: .userInitiated) {
                try worldExporter.compileWorld(
                    project: project,
                    addOn: addOn,
                    gameMode: gameMode,
                    outputDirectory: directory
                )
            }.value
            state = .built(project, addOn)
            return result
        } catch {
            state = .failed(error.localizedDescription)
            return nil
        }
    }

    func loadProject(from sidecarURL: URL) -> AddOnProject? {
        try? revisionService.loadProject(from: sidecarURL)
    }

    func revise(project baseProject: AddOnProject, newPrompt: String) async {
        let trimmed = newPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .failed("Describe the revision you want to make.")
            return
        }
        state = .generating
        do {
            let directory = try artifactDirectoryProvider()
            let client = client
            let revisionService = revisionService
            let result = try await revisionService.revise(
                baseProject: baseProject,
                newPrompt: trimmed,
                client: client,
                outputDirectory: directory
            )
            lastRevisionSummary = result.changeSummary
            state = .built(result.project, result.compilationResult)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func reviseStoredProject(projectID: UUID, newPrompt: String) async {
        let trimmed = newPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .failed("Describe the revision you want to make.")
            return
        }
        state = .generating
        do {
            let directory = try artifactDirectoryProvider()
            let baseProject = try revisionService.loadProject(for: projectID, in: directory)
            let client = client
            let revisionService = revisionService
            let result = try await revisionService.revise(
                baseProject: baseProject,
                newPrompt: trimmed,
                client: client,
                outputDirectory: directory
            )
            lastRevisionSummary = result.changeSummary
            state = .built(result.project, result.compilationResult)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func reset() {
        lastRevisionSummary = nil
        state = .editing
    }

    private static func defaultArtifactDirectory() throws -> URL {
        let documentsDirectory = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return documentsDirectory.appending(path: "Craftberry Builds", directoryHint: .isDirectory)
    }
}
#endif
