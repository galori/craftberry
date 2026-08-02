import Foundation

public enum ProjectGenerationOutcome: String, Codable, Sendable {
    case ready
    case unsupported
}

public struct ProjectGeneration: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let outcome: ProjectGenerationOutcome
    public let message: String
    public let project: AddOnProject?

    public init(
        schemaVersion: Int = 1,
        outcome: ProjectGenerationOutcome,
        message: String,
        project: AddOnProject?
    ) {
        self.schemaVersion = schemaVersion
        self.outcome = outcome
        self.message = message
        self.project = project
    }
}

public protocol LLMClient: Sendable {
    func generateProject(from prompt: String) async throws -> ProjectGeneration
}

public enum LLMClientError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case requestFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Add an OpenAI API key to the local Debug configuration before generating."
        case .invalidResponse: "The AI returned an unusable result. Please try again."
        case .requestFailed(let message): message
        }
    }
}
