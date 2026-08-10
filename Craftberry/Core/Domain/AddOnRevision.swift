import Foundation

// MARK: - Version bumping

public extension VersionTriplet {
    func nextPatch() -> VersionTriplet {
        VersionTriplet(major: major, minor: minor, patch: patch + 1)
    }
}

// MARK: - Content node identity

public extension AddOnContentNode {
    var contentID: ContentID {
        switch self {
        case .item(let item): item.id
        case .block(let block): block.id
        case .entity(let entity): entity.id
        case .spawnRule(let rule): rule.id
        case .entityLoot(let loot): loot.id
        case .shapedRecipe(let recipe): recipe.id
        case .shapelessRecipe(let recipe): recipe.id
        case .furnaceRecipe(let recipe): recipe.id
        case .smithingTrimRecipe(let recipe): recipe.id
        case .smithingTransformRecipe(let recipe): recipe.id
        case .brewingMixRecipe(let recipe): recipe.id
        case .brewingContainerRecipe(let recipe): recipe.id
        case .visualResource(let resource): resource.id
        case .mechanic(let mechanic): mechanic.id
        }
    }
}

// MARK: - Change summary

public struct ChangeSummary: Equatable, Sendable {
    public struct ModifiedNode: Equatable, Sendable {
        public let id: ContentID
        public let before: AddOnContentNode
        public let after: AddOnContentNode
    }

    public let added: [AddOnContentNode]
    public let removed: [AddOnContentNode]
    public let modified: [ModifiedNode]

    public init(added: [AddOnContentNode], removed: [AddOnContentNode], modified: [ModifiedNode]) {
        self.added = added
        self.removed = removed
        self.modified = modified
    }

    public var isEmpty: Bool { added.isEmpty && removed.isEmpty && modified.isEmpty }

    private static func nodeKey(_ node: AddOnContentNode) -> String {
        switch node {
        case .item(let v): return "item:\(v.id.rawValue)"
        case .block(let v): return "block:\(v.id.rawValue)"
        case .entity(let v): return "entity:\(v.id.rawValue)"
        case .spawnRule(let v): return "spawnRule:\(v.id.rawValue)"
        case .entityLoot(let v): return "entityLoot:\(v.id.rawValue)"
        case .shapedRecipe(let v): return "shapedRecipe:\(v.id.rawValue)"
        case .shapelessRecipe(let v): return "shapelessRecipe:\(v.id.rawValue)"
        case .furnaceRecipe(let v): return "furnaceRecipe:\(v.id.rawValue)"
        case .smithingTrimRecipe(let v): return "smithingTrimRecipe:\(v.id.rawValue)"
        case .smithingTransformRecipe(let v): return "smithingTransformRecipe:\(v.id.rawValue)"
        case .brewingMixRecipe(let v): return "brewingMixRecipe:\(v.id.rawValue)"
        case .brewingContainerRecipe(let v): return "brewingContainerRecipe:\(v.id.rawValue)"
        case .visualResource(let v): return "visualResource:\(v.id.rawValue)"
        case .mechanic(let v): return "mechanic:\(v.id.rawValue)"
        }
    }

    public static func diff(old: [AddOnContentNode], new: [AddOnContentNode]) -> ChangeSummary {
        let oldMap = Dictionary(uniqueKeysWithValues: old.map { (nodeKey($0), $0) })
        let newMap = Dictionary(uniqueKeysWithValues: new.map { (nodeKey($0), $0) })
        let oldKeys = Set(oldMap.keys)
        let newKeys = Set(newMap.keys)

        let addedKeys = newKeys.subtracting(oldKeys)
        let removedKeys = oldKeys.subtracting(newKeys)
        let commonKeys = oldKeys.intersection(newKeys)

        let added = addedKeys.sorted().compactMap { newMap[$0] }
        let removed = removedKeys.sorted().compactMap { oldMap[$0] }
        let modified = commonKeys.sorted().compactMap { key -> ModifiedNode? in
            guard let before = oldMap[key], let after = newMap[key], before != after else { return nil }
            return ModifiedNode(id: before.contentID, before: before, after: after)
        }
        return ChangeSummary(added: added, removed: removed, modified: modified)
    }
}

// MARK: - Revision result & errors

public struct RevisionResult: Sendable {
    public let project: AddOnProject
    public let changeSummary: ChangeSummary
    public let compilationResult: BedrockCompilationResult
}

public enum RevisionError: LocalizedError, Equatable {
    case emptyPrompt
    case unsupported(String)
    case validationFailed(CompilationReport)
    case missingProject(String)

    public var errorDescription: String? {
        switch self {
        case .emptyPrompt: "Describe the revision you want to make."
        case .unsupported(let message): message
        case .validationFailed(let report): report.errors.first?.message ?? "The revised project is invalid."
        case .missingProject(let message): message
        }
    }
}

// MARK: - Sidecar store

public enum AddOnProjectStore {
    public static func sidecarURL(for projectID: UUID, in outputDirectory: URL) -> URL {
        outputDirectory
            .appending(path: projectID.uuidString.lowercased(), directoryHint: .isDirectory)
            .appending(path: "project.json")
    }

    public static func load(from sidecarURL: URL) throws -> AddOnProject {
        let data = try Data(contentsOf: sidecarURL)
        return try JSONDecoder().decode(AddOnProject.self, from: data)
    }

    public static func load(for projectID: UUID, in outputDirectory: URL) throws -> AddOnProject {
        try load(from: sidecarURL(for: projectID, in: outputDirectory))
    }

    public static func save(_ project: AddOnProject, to sidecarURL: URL) throws {
        let data = try BedrockDocumentEncoder.encode(project)
        let directory = sidecarURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: sidecarURL, options: .atomic)
    }
}

// MARK: - Revision service

public final class AddOnRevisionService: @unchecked Sendable {
    private let profile: BedrockContentProfile
    private let compiler: any AddOnCompiling
    private let fileManager: FileManager

    public init(
        profile: BedrockContentProfile = .current,
        compiler: any AddOnCompiling = BedrockAddOnCompiler(),
        fileManager: FileManager = .default
    ) {
        self.profile = profile
        self.compiler = compiler
        self.fileManager = fileManager
    }

    public func loadProject(from sidecarURL: URL) throws -> AddOnProject {
        try AddOnProjectStore.load(from: sidecarURL)
    }

    public func loadProject(for projectID: UUID, in outputDirectory: URL) throws -> AddOnProject {
        try AddOnProjectStore.load(for: projectID, in: outputDirectory)
    }

    public func revise(
        baseProject: AddOnProject,
        newPrompt: String,
        client: any LLMClient,
        outputDirectory: URL
    ) async throws -> RevisionResult {
        let trimmed = newPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RevisionError.emptyPrompt }

        let generation = try await client.generateProject(from: trimmed)
        switch generation.outcome {
        case .unsupported:
            throw RevisionError.unsupported(generation.message)
        case .ready:
            guard let draft = generation.project else { throw LLMClientError.invalidResponse }
            return try await reviseWithDraft(
                baseProject: baseProject,
                draft: draft,
                newPrompt: trimmed,
                outputDirectory: outputDirectory
            )
        }
    }

    public func reviseWithDraft(
        baseProject: AddOnProject,
        draft: AddOnProject,
        newPrompt: String,
        outputDirectory: URL
    ) async throws -> RevisionResult {
        let bumped = baseProject.buildVersion.nextPatch()
        let revised = AddOnProject(
            id: baseProject.id,
            namespace: baseProject.namespace,
            displayName: draft.displayName,
            shortDescription: draft.shortDescription,
            packUUIDs: baseProject.packUUIDs,
            buildVersion: bumped,
            targetProfileID: draft.targetProfileID,
            originalPrompt: newPrompt,
            content: draft.content
        )

        let report = AddOnProjectValidator.validate(revised, profile: profile)
        guard report.isSuccessful else {
            throw RevisionError.validationFailed(report)
        }

        let changeSummary = ChangeSummary.diff(old: baseProject.content, new: revised.content)

        // Preserve original sidecar if present to allow rollback on compile failure.
        let sidecarURL = AddOnProjectStore.sidecarURL(for: baseProject.id, in: outputDirectory)
        let previousSidecarData = try? Data(contentsOf: sidecarURL)
        let bumpedVersionString = bumped.components.map(String.init).joined(separator: ".")
        let bumpedBuildDir = outputDirectory
            .appending(path: baseProject.id.uuidString.lowercased(), directoryHint: .isDirectory)
            .appending(path: "builds/\(bumpedVersionString)", directoryHint: .isDirectory)

        do {
            let compilationResult = try compiler.compile(project: revised, profile: profile, outputDirectory: outputDirectory)
            return RevisionResult(project: revised, changeSummary: changeSummary, compilationResult: compilationResult)
        } catch {
            // Attempt to restore previous sidecar and remove partially written bumped build dir.
            if let previousSidecarData {
                try? previousSidecarData.write(to: sidecarURL, options: .atomic)
            } else {
                try? fileManager.removeItem(at: sidecarURL)
            }
            if fileManager.fileExists(atPath: bumpedBuildDir.path) {
                try? fileManager.removeItem(at: bumpedBuildDir)
            }
            throw error
        }
    }
}
