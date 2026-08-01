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
        case ready(SwordSpec)
        case building(SwordSpec)
        case built(SwordSpec, BedrockAddOnArtifact)
        case failed(String)
    }

    @Published var prompt = "Create a blue sword that does 20 damage and can be crafted from diamonds."
    @Published private(set) var state: State = .editing

    var isBusy: Bool {
        switch state {
        case .generating, .building: true
        default: false
        }
    }

    private let client: any LLMClient
    private let compiler: BedrockAddOnCompiler

    init(
        apiKey: String,
        compiler: BedrockAddOnCompiler = BedrockAddOnCompiler(),
        client: (any LLMClient)? = nil
    ) {
        self.client = client ?? OpenAIResponsesClient(apiKey: apiKey)
        self.compiler = compiler
    }

    func generate() async {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            state = .failed("Describe the sword you want to create first.")
            return
        }
        state = .generating
        do {
            let generation = try await client.generateSword(from: trimmedPrompt)
            switch generation.outcome {
            case .ready:
                guard let sword = generation.sword else { throw LLMClientError.invalidResponse }
                state = .ready(sword)
            case .unsupported:
                state = .unsupported(generation.message)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func buildArtifact(_ sword: SwordSpec) {
        state = .building(sword)
        do {
            let directory = try artifactDirectory()
            let artifact = try compiler.compile(sword, outputDirectory: directory)
            state = .built(sword, artifact)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func reset() {
        state = .editing
    }

    private func artifactDirectory() throws -> URL {
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
