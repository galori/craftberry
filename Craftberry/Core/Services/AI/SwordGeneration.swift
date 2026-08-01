import Foundation

public enum SwordGenerationOutcome: String, Codable, Sendable {
    case ready
    case unsupported
}

public struct SwordGeneration: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let outcome: SwordGenerationOutcome
    public let message: String
    public let sword: SwordSpec?

    public init(schemaVersion: Int = 1, outcome: SwordGenerationOutcome, message: String, sword: SwordSpec?) {
        self.schemaVersion = schemaVersion
        self.outcome = outcome
        self.message = message
        self.sword = sword
    }
}

public protocol LLMClient: Sendable {
    func generateSword(from prompt: String) async throws -> SwordGeneration
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
