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
        case built(AddOnProject, BedrockCompilationResult)
        case failed(String)
    }

    @Published var prompt = ""
    @Published private(set) var state: State = .editing

    var isBusy: Bool {
        switch state {
        case .generating, .building: true
        default: false
        }
    }

    private let client: any LLMClient
    private let compiler: any AddOnCompiling
    private let artifactDirectoryProvider: @MainActor () throws -> URL

    init(
        apiKey: String,
        compiler: any AddOnCompiling = BedrockAddOnCompiler(),
        client: (any LLMClient)? = nil,
        artifactDirectoryProvider: @escaping @MainActor () throws -> URL = CreationViewModel.defaultArtifactDirectory
    ) {
        self.client = client ?? OpenAIResponsesClient(apiKey: apiKey)
        self.compiler = compiler
        self.artifactDirectoryProvider = artifactDirectoryProvider
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

    func buildArtifact(_ project: AddOnProject) async {
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
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func reset() {
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
