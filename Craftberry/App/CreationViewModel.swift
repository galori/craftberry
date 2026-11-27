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
    private let telemetryManager: TelemetryManager?

    @Published private(set) var lastRevisionSummary: ChangeSummary?
    @Published private(set) var revisionError: String?
    @Published private(set) var projectFileError: String?

    init(
        apiKey: String,
        compiler: any AddOnCompiling = BedrockAddOnCompiler(),
        worldExporter: any AddOnWorldExporting = BedrockWorldExporter(),
        client: (any LLMClient)? = nil,
        revisionService: AddOnRevisionService? = nil,
        telemetryManager: TelemetryManager? = nil,
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
        self.telemetryManager = telemetryManager
    }

    func generate() async {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            state = .failed("Describe the add-on you want to create first.")
            return
        }
        state = .generating
        telemetryManager?.record(name: "generation.requested")
        do {
            let generation = try await client.generateProject(from: trimmedPrompt)
            switch generation.outcome {
            case .ready:
                guard let project = generation.project else { throw LLMClientError.invalidResponse }
                let report = AddOnProjectValidator.validate(project, profile: .current)
                guard report.isSuccessful else {
                    throw BedrockCompilationError.invalidProject(report)
                }
                telemetryManager?.record(name: "generation.succeeded", properties: ["outcome": "ready"])
                state = .ready(project)
            case .unsupported:
                telemetryManager?.record(name: "generation.unsupported", properties: ["outcome": "unsupported"])
                state = .unsupported(generation.message)
            }
        } catch {
            telemetryManager?.record(name: "generation.failed", properties: ["outcome": "failed"])
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
            telemetryManager?.record(name: "build.succeeded")
            state = .built(project, result)
            return result
        } catch {
            telemetryManager?.record(name: "build.failed", properties: ["outcome": "failed"])
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
            let retentionService = SidecarRetentionService()
            let result = try await Task.detached(priority: .userInitiated) {
                let snapshotURL = try retentionService.makeShareSnapshot(of: addOn.artifact.url, in: directory)
                defer { retentionService.removeShareSnapshot(at: snapshotURL, in: directory) }
                let snapshotArtifact = BedrockAddOnArtifact(
                    url: snapshotURL,
                    identifier: addOn.artifact.identifier,
                    fileName: addOn.artifact.fileName,
                    projectSidecarURL: addOn.artifact.projectSidecarURL
                )
                let snapshotAddOn = BedrockCompilationResult(artifact: snapshotArtifact, report: addOn.report)
                return try worldExporter.compileWorld(
                    project: project,
                    addOn: snapshotAddOn,
                    gameMode: gameMode,
                    outputDirectory: directory
                )
            }.value
            telemetryManager?.record(name: "build.succeeded")
            state = .built(project, addOn)
            return result
        } catch {
            telemetryManager?.record(name: "build.failed", properties: ["outcome": "failed"])
            state = .failed(error.localizedDescription)
            return nil
        }
    }

    func openProject(from sidecarURL: URL) {
        do {
            let project = try revisionService.loadProject(from: sidecarURL)
            let report = AddOnProjectValidator.validate(project, profile: .current)
            guard report.isSuccessful else {
                projectFileError = report.errors.map(\.message).joined(separator: " ")
                return
            }
            lastRevisionSummary = nil
            revisionError = nil
            projectFileError = nil
            state = .ready(project)
        } catch {
            projectFileError = "This file isn't a valid Craftberry project sidecar. \(error.localizedDescription)"
        }
    }

    func saveProjectSidecar(for project: AddOnProject) -> URL? {
        do {
            let outputDirectory = try artifactDirectoryProvider()
            let sidecarURL = AddOnProjectStore.sidecarURL(for: project.id, in: outputDirectory)
            try SidecarBuildAccessCoordinator.shared.withExclusiveAccess {
                try AddOnProjectStore.save(project, to: sidecarURL)
            }
            projectFileError = nil
            return sidecarURL
        } catch {
            reportProjectFileError(error)
            return nil
        }
    }

    func makeShareSnapshot(of artifactURL: URL) -> URL? {
        do {
            let outputDirectory = try artifactDirectoryProvider()
            let snapshotURL = try SidecarRetentionService().makeShareSnapshot(of: artifactURL, in: outputDirectory)
            projectFileError = nil
            return snapshotURL
        } catch {
            projectFileError = "Couldn't prepare the generated file for sharing. \(error.localizedDescription)"
            return nil
        }
    }

    func removeShareSnapshot(at snapshotURL: URL) {
        guard let outputDirectory = try? artifactDirectoryProvider() else { return }
        SidecarRetentionService().removeShareSnapshot(at: snapshotURL, in: outputDirectory)
    }

    func importTexture(fromPNG data: Data, visualResourceID: ContentID) async {
        guard let project = currentProjectForTextureImport() else {
            projectFileError = "Generate an add-on before importing item art."
            return
        }
        do {
            let pixels = try PixelArtTextureImporter.canonicalPixels(fromPNG: data)
            guard let visual = project.visualResources.first(where: { $0.id == visualResourceID }),
                  visual.kind.supportsImportedPixels else {
                throw PixelArtTextureImportError.incorrectDimensions
            }
            let content = project.content.map { node in
                guard case .visualResource(let resource) = node, resource.id == visualResourceID else { return node }
                return .visualResource(VisualResource(
                    id: resource.id,
                    kind: resource.kind,
                    color: resource.color,
                    customPixels: pixels
                ))
            }
            let importedProject = AddOnProject(
                schemaVersion: project.schemaVersion,
                id: project.id,
                namespace: project.namespace,
                displayName: project.displayName,
                shortDescription: project.shortDescription,
                packUUIDs: project.packUUIDs,
                buildVersion: project.buildVersion.nextPatch(),
                targetProfileID: project.targetProfileID,
                originalPrompt: project.originalPrompt,
                content: content
            )
            let report = AddOnProjectValidator.validate(importedProject, profile: .current)
            guard report.isSuccessful else { throw BedrockCompilationError.invalidProject(report) }
            projectFileError = nil
            let previousState = state
            guard await buildArtifact(importedProject) != nil else {
                let buildError: String
                if case .failed(let message) = state {
                    buildError = message
                } else {
                    buildError = "The item texture could not be built."
                }
                state = previousState
                projectFileError = "Couldn't build imported item art. \(buildError)"
                return
            }
        } catch {
            projectFileError = error.localizedDescription
        }
    }

    func reportTextureImportError(_ error: Error) {
        projectFileError = error.localizedDescription
    }

    func clearTextureImportError() {
        projectFileError = nil
    }

    private func currentProjectForTextureImport() -> AddOnProject? {
        switch state {
        case .ready(let project), .built(let project, _): project
        default: nil
        }
    }

    func clearProjectFileError() {
        projectFileError = nil
    }

    func reportProjectFileError(_ error: Error) {
        projectFileError = "Couldn't access the selected project file. \(error.localizedDescription)"
    }

    func revise(project baseProject: AddOnProject, newPrompt: String) async {
        let trimmed = newPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            revisionError = "Describe the revision you want to make."
            return
        }
        let previousState = state
        revisionError = nil
        state = .generating
        telemetryManager?.record(name: "generation.requested")
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
            telemetryManager?.record(name: "generation.succeeded", properties: ["outcome": "ready"])
            telemetryManager?.record(name: "build.succeeded")
            state = .built(result.project, result.compilationResult)
        } catch {
            state = previousState
            telemetryManager?.record(name: "generation.failed", properties: ["outcome": "failed"])
            telemetryManager?.record(name: "build.failed", properties: ["outcome": "failed"])
            revisionError = error.localizedDescription
        }
    }

    func reviseStoredProject(projectID: UUID, newPrompt: String) async {
        let trimmed = newPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .failed("Describe the revision you want to make.")
            return
        }
        state = .generating
        telemetryManager?.record(name: "generation.requested")
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
            telemetryManager?.record(name: "generation.succeeded", properties: ["outcome": "ready"])
            telemetryManager?.record(name: "build.succeeded")
            state = .built(result.project, result.compilationResult)
        } catch {
            telemetryManager?.record(name: "generation.failed", properties: ["outcome": "failed"])
            telemetryManager?.record(name: "build.failed", properties: ["outcome": "failed"])
            state = .failed(error.localizedDescription)
        }
    }

    func reset() {
        lastRevisionSummary = nil
        revisionError = nil
        projectFileError = nil
        state = .editing
    }

    func pruneStoredBuilds() async {
        guard let directory = try? artifactDirectoryProvider() else { return }
        let retentionService = SidecarRetentionService()
        _ = try? await Task.detached(priority: .utility) {
            try retentionService.prune(in: directory)
        }.value
    }

    nonisolated private static func defaultArtifactDirectory() throws -> URL {
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
