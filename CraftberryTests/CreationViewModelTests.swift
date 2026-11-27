#if canImport(UIKit)
import XCTest
@testable import Craftberry

@MainActor
final class CreationViewModelTests: XCTestCase {
    func testGenerateTransitionsToReadyWithAFakeProjectClient() async throws {
        let project = try makeProject()
        let viewModel = CreationViewModel(
            apiKey: "",
            client: FakeLLMClient(response: .generation(
                ProjectGeneration(outcome: .ready, message: "Ready", project: project)
            ))
        )
        viewModel.prompt = "A blue diamond sword"

        await viewModel.generate()

        guard case .ready(let generatedProject) = viewModel.state else {
            return XCTFail("Expected ready state, got \(viewModel.state)")
        }
        XCTAssertEqual(generatedProject, project)
    }

    func testGenerateTransitionsToUnsupported() async {
        let viewModel = CreationViewModel(
            apiKey: "",
            client: FakeLLMClient(response: .generation(
                ProjectGeneration(outcome: .unsupported, message: "Try a single sword.", project: nil)
            ))
        )
        viewModel.prompt = "Make a dragon"

        await viewModel.generate()

        guard case .unsupported(let message) = viewModel.state else {
            return XCTFail("Expected unsupported state, got \(viewModel.state)")
        }
        XCTAssertEqual(message, "Try a single sword.")
    }

    func testGenerateTransitionsToFailedWhenTheClientFails() async {
        let viewModel = CreationViewModel(
            apiKey: "",
            client: FakeLLMClient(response: .failure(.network))
        )
        viewModel.prompt = "A blue sword"

        await viewModel.generate()

        guard case .failed(let message) = viewModel.state else {
            return XCTFail("Expected failed state, got \(viewModel.state)")
        }
        XCTAssertEqual(message, "The test network is unavailable.")
    }

    func testGenerationServiceTrafficRecordsOnlySafeTelemetryEvents() async throws {
        let project = try makeProject()
        let telemetrySink = InMemoryTelemetrySink()
        let telemetryManager = TelemetryManager(
            storage: InMemoryTelemetryStorage(optedIn: true),
            sink: telemetrySink
        )
        let viewModel = CreationViewModel(
            apiKey: "",
            client: FakeLLMClient(response: .generation(
                ProjectGeneration(outcome: .ready, message: "Ready", project: project)
            )),
            telemetryManager: telemetryManager
        )
        let privatePrompt = "A private custom sword and texture"
        viewModel.prompt = privatePrompt

        await viewModel.generate()

        XCTAssertEqual(telemetrySink.events.map(\.name), ["generation.requested", "generation.succeeded"])
        let encodedEvents = try XCTUnwrap(String(data: JSONEncoder().encode(telemetrySink.events), encoding: .utf8))
        XCTAssertFalse(encodedEvents.contains(privatePrompt))
        XCTAssertFalse(encodedEvents.contains("texture"))
        XCTAssertEqual(telemetrySink.events.last?.properties, ["outcome": "ready"])
    }

    func testGenerateRejectsAProjectThatFailsLocalValidation() async throws {
        let project = try makeProject()
        let invalidProject = AddOnProject(
            id: project.id,
            namespace: project.namespace,
            displayName: project.displayName,
            packUUIDs: project.packUUIDs,
            buildVersion: project.buildVersion,
            targetProfileID: project.targetProfileID,
            originalPrompt: project.originalPrompt,
            content: project.content + [.item(project.items[0])]
        )
        let viewModel = CreationViewModel(
            apiKey: "",
            client: FakeLLMClient(response: .generation(
                ProjectGeneration(outcome: .ready, message: "Ready", project: invalidProject)
            ))
        )
        viewModel.prompt = "A blue sword"

        await viewModel.generate()

        guard case .failed(let message) = viewModel.state else {
            return XCTFail("Expected failed state, got \(viewModel.state)")
        }
        XCTAssertEqual(message, "Duplicate item identifier: \(project.items[0].id.rawValue).")
    }

    func testOpenProjectFromSidecarTransitionsToReady() throws {
        let project = try makeProject()
        let sidecarURL = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: sidecarURL) }
        try AddOnProjectStore.save(project, to: sidecarURL)
        let viewModel = CreationViewModel(apiKey: "")

        viewModel.openProject(from: sidecarURL)

        guard case .ready(let loadedProject) = viewModel.state else {
            return XCTFail("Expected ready state after opening a sidecar, got \(viewModel.state)")
        }
        XCTAssertEqual(loadedProject, project)
        XCTAssertNil(viewModel.projectFileError)
    }

    func testOpenProjectRejectsIncompatibleProfileWithoutReplacingCurrentState() throws {
        let project = try makeProject()
        let incompatible = AddOnProject(
            id: project.id,
            namespace: project.namespace,
            displayName: project.displayName,
            shortDescription: project.shortDescription,
            packUUIDs: project.packUUIDs,
            buildVersion: project.buildVersion,
            targetProfileID: "bedrock-stable-incompatible",
            originalPrompt: project.originalPrompt,
            content: project.content
        )
        let sidecarURL = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: sidecarURL) }
        try AddOnProjectStore.save(incompatible, to: sidecarURL)
        let viewModel = CreationViewModel(apiKey: "")

        viewModel.openProject(from: sidecarURL)

        guard case .editing = viewModel.state else {
            return XCTFail("Invalid sidecar must not replace the current screen state.")
        }
        XCTAssertTrue(viewModel.projectFileError?.contains("migrate") == true)
    }

    func testOpenProjectReportsMalformedSidecar() throws {
        let sidecarURL = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: sidecarURL) }
        try Data("not a project".utf8).write(to: sidecarURL)
        let viewModel = CreationViewModel(apiKey: "")

        viewModel.openProject(from: sidecarURL)

        XCTAssertTrue(viewModel.projectFileError?.contains("Craftberry project") == true)
        guard case .editing = viewModel.state else {
            return XCTFail("Malformed sidecar must not replace the current screen state.")
        }
    }

    func testBuildTransitionsToFailedWhenTheCompilerFails() async throws {
        let project = try makeProject()
        let viewModel = CreationViewModel(
            apiKey: "",
            compiler: FailingCompiler(),
            client: FakeLLMClient(response: .generation(
                ProjectGeneration(outcome: .ready, message: "Ready", project: project)
            ))
        )
        viewModel.prompt = "A blue sword"
        await viewModel.generate()

        await viewModel.buildArtifact(project)

        guard case .failed(let message) = viewModel.state else {
            return XCTFail("Expected failed state, got \(viewModel.state)")
        }
        XCTAssertEqual(message, "The test compiler failed.")
    }

    func testBuildCreatesAnExportReadyArtifactAndSidecar() async throws {
        let project = try makeProject()
        let outputDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        let viewModel = CreationViewModel(
            apiKey: "",
            client: FakeLLMClient(response: .generation(
                ProjectGeneration(outcome: .ready, message: "Ready", project: project)
            )),
            artifactDirectoryProvider: { outputDirectory }
        )
        viewModel.prompt = "A blue sword"
        await viewModel.generate()

        await viewModel.buildArtifact(project)

        guard case .built(let builtProject, let result) = viewModel.state else {
            return XCTFail("Expected built state, got \(viewModel.state)")
        }
        XCTAssertEqual(builtProject, project)
        XCTAssertTrue(result.report.isSuccessful)
        XCTAssertEqual(result.artifact.url.pathExtension, "mcaddon")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.artifact.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.artifact.projectSidecarURL.path))
    }

    func testTextureImportFailureKeepsBuiltProjectAndPublishedSidecar() async throws {
        let project = try makeProject()
        let outputDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        let viewModel = CreationViewModel(
            apiKey: "",
            client: FakeLLMClient(response: .generation(
                ProjectGeneration(outcome: .ready, message: "Ready", project: project)
            )),
            artifactDirectoryProvider: { outputDirectory }
        )
        viewModel.prompt = "A blue diamond sword"
        await viewModel.generate()
        let buildResult = await viewModel.buildArtifact(project)
        let initialResult = try XCTUnwrap(buildResult)

        let nextBuildDirectory = initialResult.artifact.url
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(
                path: project.buildVersion.nextPatch().components.map(String.init).joined(separator: "."),
                directoryHint: .isDirectory
            )
        let blockedArchiveURL = nextBuildDirectory.appending(path: initialResult.artifact.fileName)
        try FileManager.default.createDirectory(at: blockedArchiveURL, withIntermediateDirectories: true)

        let visual = try XCTUnwrap(project.visualResources.first { $0.kind == .swordPixelArt })
        await viewModel.importTexture(
            fromPNG: PixelArtTextureRenderer.render(visual),
            visualResourceID: visual.id
        )

        guard case .built(let restoredProject, let restoredResult) = viewModel.state else {
            return XCTFail("A failed texture build must restore the existing built project, got \(viewModel.state)")
        }
        XCTAssertEqual(restoredProject, project)
        XCTAssertEqual(restoredResult.artifact.url, initialResult.artifact.url)
        XCTAssertTrue(viewModel.projectFileError?.contains("Couldn't build imported item art") == true)
        XCTAssertEqual(try AddOnProjectStore.load(from: initialResult.artifact.projectSidecarURL), project)
    }

    private func makeProject() throws -> AddOnProject {
        try AddOnProject.sword(
            displayName: "Azure Sword",
            originalPrompt: "A blue diamond sword",
            identity: AddOnProjectIdentity(
                projectID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
                namespace: "craftberry",
                contentSuffix: "a1b2c3",
                packUUIDs: PackUUIDs(
                    behaviorHeader: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!,
                    behaviorModule: UUID(uuidString: "20000000-0000-4000-8000-000000000002")!,
                    resourceHeader: UUID(uuidString: "20000000-0000-4000-8000-000000000003")!,
                    resourceModule: UUID(uuidString: "20000000-0000-4000-8000-000000000004")!
                )
            )
        )
    }
}

private enum FakeLLMResponse: Sendable {
    case generation(ProjectGeneration)
    case failure(FakeLLMError)
}

private struct FakeLLMClient: LLMClient {
    let response: FakeLLMResponse

    func generateProject(from prompt: String) async throws -> ProjectGeneration {
        switch response {
        case .generation(let generation): generation
        case .failure(let error): throw error
        }
    }
}

private enum FakeLLMError: LocalizedError, Sendable {
    case network

    var errorDescription: String? { "The test network is unavailable." }
}

private struct FailingCompiler: AddOnCompiling {
    func compile(
        project: AddOnProject,
        profile: BedrockContentProfile,
        outputDirectory: URL
    ) throws -> BedrockCompilationResult {
        throw FakeCompilerError.build
    }
}

private enum FakeCompilerError: LocalizedError {
    case build

    var errorDescription: String? { "The test compiler failed." }
}
#endif
