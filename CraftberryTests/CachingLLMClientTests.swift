import XCTest
#if canImport(CraftberryCore)
@testable import CraftberryCore
#else
@testable import Craftberry
#endif

#if canImport(Craftberry)
@testable import Craftberry
#endif

final class CachingLLMClientTests: XCTestCase {
    func testExamplePromptsAreAllCachedAndValid() throws {
        #if canImport(Craftberry)
        let libraryPrompts = ExamplePromptLibrary.all.map(\.text)
        #else
        let libraryPrompts = ExamplePromptResponseCache.allCachedPrompts
        #endif
        for prompt in libraryPrompts {
            let identity = AddOnProjectIdentity.generate()
            let generation = try ExamplePromptResponseCache.generation(for: prompt, identity: identity, originalPrompt: prompt)
            XCTAssertNotNil(generation, "Missing cache entry for: \(prompt)")
            guard let project = generation?.project else { continue }
            let report = AddOnProjectValidator.validate(project, profile: .current)
            XCTAssertTrue(report.isSuccessful, "Cached project for \(prompt) failed validation: \(report.errors)")
        }
    }

    func testAllCachedPromptsMatchLibrary() {
        #if canImport(Craftberry)
        let library = Set(ExamplePromptLibrary.all.map(\.text))
        let cached = Set(ExamplePromptResponseCache.allCachedPrompts)
        XCTAssertEqual(library, cached, "ExamplePromptResponseCache must stay in sync with ExamplePromptLibrary")
        #endif
    }

    func testCachingClientReturnsPreSeededPromptWithoutCallingWrapped() async throws {
        let prompt = "A blue sword, 20 damage, crafted from diamonds"
        let counting = CountingLLMClient()
        let caching = CachingLLMClient(wrapping: counting, identityGenerator: { .generate() })
        let first = try await caching.generateProject(from: prompt)
        let c1 = await counting.callCount(for: prompt)
        XCTAssertEqual(c1, 0, "Pre-seeded prompt should not hit wrapped client")
        XCTAssertNotNil(first.project)
        let second = try await caching.generateProject(from: prompt)
        XCTAssertNotEqual(first.project?.id, second.project?.id, "Each call should get fresh identity")
        let c2 = await counting.callCount(for: prompt)
        XCTAssertEqual(c2, 0)
    }

    func testCachingClientCachesNonExamplePromptsAfterFirstNetworkCall() async throws {
        let prompt = "A totally custom prompt not in the library"
        let stubProject = try AddOnProject.sword(
            displayName: "Test Sword",
            originalPrompt: prompt,
            identity: .generate()
        )
        let stubGeneration = ProjectGeneration(outcome: .ready, message: "Ready", project: stubProject)
        let fake = FakeCountingClient(generation: stubGeneration)
        let caching = CachingLLMClient(wrapping: fake)
        let first = try await caching.generateProject(from: prompt)
        let c1 = await fake.callCount
        XCTAssertEqual(c1, 1)
        let second = try await caching.generateProject(from: prompt)
        let c2 = await fake.callCount
        XCTAssertEqual(c2, 1, "Second call should be served from memory cache")
        XCTAssertEqual(first, second)
    }

    func testExamplePromptWorksEvenWithEmptyAPIKey() async throws {
        // CreationViewModel with empty apiKey should still succeed for example prompts via cache.
        #if canImport(Craftberry) && canImport(SwiftUI)
        let viewModel = await CreationViewModel(apiKey: "")
        await MainActor.run { viewModel.prompt = "A blue sword, 20 damage, crafted from diamonds" }
        await viewModel.generate()
        let state = await viewModel.state
        guard case .ready(let project) = state else {
            return XCTFail("Expected ready state for cached example prompt without API key, got \(state)")
        }
        XCTAssertEqual(project.items.first?.displayName, "Azure Sword")
        #endif
    }
}

private actor CountingLLMClient: LLMClient {
    private var counts: [String: Int] = [:]
    func generateProject(from prompt: String) async throws -> ProjectGeneration {
        counts[prompt, default: 0] += 1
        throw LLMClientError.requestFailed("Should not be called for pre-seeded prompt")
    }
    func callCount(for prompt: String) -> Int {
        counts[prompt] ?? 0
    }
}

private actor FakeCountingClient: LLMClient {
    let generation: ProjectGeneration
    private(set) var callCount = 0
    init(generation: ProjectGeneration) { self.generation = generation }
    func generateProject(from prompt: String) async throws -> ProjectGeneration {
        callCount += 1
        return generation
    }
}
