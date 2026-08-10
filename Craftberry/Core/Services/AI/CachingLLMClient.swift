import Foundation

/// Decorates an `LLMClient` with in-memory caching and a pre-seeded cache for every
/// `ExamplePromptLibrary` suggestion. Known prompts never hit the network; any other
/// prompt is cached after its first successful generation so repeated calls are cheap.
public actor CachingLLMClient: LLMClient {
    private let wrapped: any LLMClient
    private let identityGenerator: @Sendable () -> AddOnProjectIdentity
    private var memoryCache: [String: ProjectGeneration] = [:]

    public init(
        wrapping wrapped: any LLMClient,
        identityGenerator: @escaping @Sendable () -> AddOnProjectIdentity = { .generate() }
    ) {
        self.wrapped = wrapped
        self.identityGenerator = identityGenerator
    }

    public func generateProject(from prompt: String) async throws -> ProjectGeneration {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        if let cached = memoryCache[trimmed] {
            return cached
        }

        if let example = try ExamplePromptResponseCache.generation(
            for: trimmed,
            identity: identityGenerator(),
            originalPrompt: prompt
        ) {
            return example
        }

        let result = try await wrapped.generateProject(from: prompt)
        memoryCache[trimmed] = result
        return result
    }

    func cachedEntry(for prompt: String) -> ProjectGeneration? {
        memoryCache[prompt.trimmingCharacters(in: .whitespacesAndNewlines)]
    }
}
