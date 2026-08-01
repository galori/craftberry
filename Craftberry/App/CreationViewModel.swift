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
        case packaging(SwordSpec)
        case packaged(SwordSpec, BedrockAddOnArtifact)
        case failed(String)
    }

    @Published var prompt = "Create a blue sword that does 20 damage and can be crafted from diamonds."
    @Published private(set) var state: State = .editing

    var isBusy: Bool {
        switch state {
        case .generating, .packaging: true
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

    func package(_ sword: SwordSpec) {
        state = .packaging(sword)
        do {
            let directory = FileManager.default.temporaryDirectory.appending(path: "Craftberry", directoryHint: .isDirectory)
            let artifact = try compiler.compile(sword, outputDirectory: directory)
            state = .packaged(sword, artifact)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func reset() {
        state = .editing
    }
}
#endif
