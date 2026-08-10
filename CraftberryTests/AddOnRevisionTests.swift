import Foundation
import XCTest
#if canImport(CraftberryCore)
@testable import CraftberryCore
#else
@testable import Craftberry
#endif

final class AddOnRevisionTests: XCTestCase {
    // MARK: - Helpers

    private func testIdentity(suffix: String = "a1b2c3") -> AddOnProjectIdentity {
        AddOnProjectIdentity(
            projectID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
            namespace: "craftberry",
            contentSuffix: suffix,
            packUUIDs: PackUUIDs(
                behaviorHeader: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!,
                behaviorModule: UUID(uuidString: "20000000-0000-4000-8000-000000000002")!,
                resourceHeader: UUID(uuidString: "20000000-0000-4000-8000-000000000003")!,
                resourceModule: UUID(uuidString: "20000000-0000-4000-8000-000000000004")!
            )
        )
    }

    private func makeSwordProject(displayName: String = "Azure Sword", attack: Int = 10, identity: AddOnProjectIdentity? = nil) throws -> AddOnProject {
        try AddOnProject.sword(
            displayName: displayName,
            color: .blue,
            attackBonus: attack,
            durability: 500,
            craftingIngredient: "minecraft:diamond",
            originalPrompt: "prompt \(displayName)",
            identity: identity ?? testIdentity()
        )
    }

    private func makeMaterialProject(material: String = "Azure") throws -> AddOnProject {
        try AddOnProject.materialSwordSet(materialName: material, sourceItem: "minecraft:diamond", sourceCount: 4, originalPrompt: "material \(material)", identity: testIdentity())
    }

    // MARK: - Sidecar round-trip

    func testSidecarRoundTripPreservesIdentityAndContent() throws {
        let project = try makeSwordProject()
        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(AddOnProject.self, from: data)
        XCTAssertEqual(decoded, project)
        XCTAssertEqual(decoded.id, project.id)
        XCTAssertEqual(decoded.packUUIDs, project.packUUIDs)
        XCTAssertEqual(decoded.buildVersion, VersionTriplet(major: 1, minor: 0, patch: 0))
    }

    func testProjectStoreRoundTripViaFile() throws {
        let project = try makeSwordProject()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let compiler = BedrockAddOnCompiler()
        _ = try compiler.compile(project: project, profile: .current, outputDirectory: directory)
        let sidecarURL = AddOnProjectStore.sidecarURL(for: project.id, in: directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecarURL.path))
        let loaded = try AddOnProjectStore.load(from: sidecarURL)
        XCTAssertEqual(loaded, project)
        let loadedByID = try AddOnProjectStore.load(for: project.id, in: directory)
        XCTAssertEqual(loadedByID, project)
    }

    // MARK: - Version increment

    func testVersionIncrementBumpsPatch() {
        let v = VersionTriplet(major: 1, minor: 0, patch: 0)
        XCTAssertEqual(v.nextPatch(), VersionTriplet(major: 1, minor: 0, patch: 1))
        XCTAssertEqual(VersionTriplet(major: 1, minor: 2, patch: 9).nextPatch(), VersionTriplet(major: 1, minor: 2, patch: 10))
    }

    func testRevisionBumpsVersion() async throws {
        let base = try makeSwordProject()
        let draft = try makeSwordProject(displayName: "Azure Sword", attack: 20)
        let service = AddOnRevisionService()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try await service.reviseWithDraft(baseProject: base, draft: draft, newPrompt: "make it stronger", outputDirectory: directory)
        XCTAssertEqual(result.project.buildVersion, VersionTriplet(major: 1, minor: 0, patch: 1))
        XCTAssertEqual(result.project.id, base.id)
        XCTAssertEqual(result.project.namespace, base.namespace)
        XCTAssertEqual(result.project.packUUIDs, base.packUUIDs)
    }

    func testSuccessiveRevisionsIncrementMonotonically() async throws {
        let base = try makeSwordProject()
        let draft1 = try makeSwordProject(displayName: "Azure Sword", attack: 15)
        let draft2 = try makeSwordProject(displayName: "Azure Sword", attack: 20)
        let service = AddOnRevisionService()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let r1 = try await service.reviseWithDraft(baseProject: base, draft: draft1, newPrompt: "revision 1", outputDirectory: directory)
        let r2 = try await service.reviseWithDraft(baseProject: r1.project, draft: draft2, newPrompt: "revision 2", outputDirectory: directory)
        XCTAssertEqual(r1.project.buildVersion, VersionTriplet(major: 1, minor: 0, patch: 1))
        XCTAssertEqual(r2.project.buildVersion, VersionTriplet(major: 1, minor: 0, patch: 2))
    }

    // MARK: - Identity preservation

    func testRevisionPreservesStableIdentity() async throws {
        let base = try makeSwordProject()
        // Draft generated with a different ephemeral identity must still be rewritten to base identity.
        let ephemeralIdentity = AddOnProjectIdentity(
            projectID: UUID(),
            namespace: "other",
            contentSuffix: "zz99zz",
            packUUIDs: PackUUIDs(
                behaviorHeader: UUID(), behaviorModule: UUID(), resourceHeader: UUID(), resourceModule: UUID()
            )
        )
        let draft = try makeSwordProject(displayName: "Ember Blade", attack: 12, identity: ephemeralIdentity)
        let service = AddOnRevisionService()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try await service.reviseWithDraft(baseProject: base, draft: draft, newPrompt: "ember", outputDirectory: directory)
        XCTAssertEqual(result.project.id, base.id)
        XCTAssertEqual(result.project.namespace, base.namespace)
        XCTAssertEqual(result.project.packUUIDs, base.packUUIDs)
        // Build version bumped, not copied from draft.
        XCTAssertNotEqual(result.project.buildVersion, draft.buildVersion)
    }

    // MARK: - Change summary

    func testChangeSummaryDetectsAddedAndRemoved() {
        let old: [AddOnContentNode] = [
            .item(ItemDefinition(id: ContentID("a"), displayName: "A", menuCategory: .equipment, menuGroup: "minecraft:itemGroup.name.sword", traits: ItemTraits(), visualResourceID: ContentID("a"))),
            .visualResource(VisualResource(id: ContentID("a"), kind: .swordPixelArt, color: .blue))
        ]
        let new: [AddOnContentNode] = [
            .item(ItemDefinition(id: ContentID("b"), displayName: "B", menuCategory: .equipment, menuGroup: "minecraft:itemGroup.name.sword", traits: ItemTraits(), visualResourceID: ContentID("b"))),
            .visualResource(VisualResource(id: ContentID("b"), kind: .swordPixelArt, color: .red))
        ]
        let summary = ChangeSummary.diff(old: old, new: new)
        XCTAssertEqual(summary.added.count, 2)
        XCTAssertEqual(summary.removed.count, 2)
        XCTAssertTrue(summary.modified.isEmpty)
    }

    func testChangeSummaryDetectsModifiedNode() throws {
        let base = try makeSwordProject(displayName: "Azure Sword", attack: 10)
        let draft = try makeSwordProject(displayName: "Azure Sword", attack: 20)
        // Same ID, different trait -> modified.
        let summary = ChangeSummary.diff(old: base.content, new: draft.content)
        // The item with same ID should appear as modified, not added/removed.
        XCTAssertTrue(summary.added.isEmpty)
        XCTAssertTrue(summary.removed.isEmpty)
        XCTAssertEqual(summary.modified.count, 1)
        XCTAssertEqual(summary.modified.first?.id, ContentID("azure_sword_a1b2c3"))
    }

    func testChangeSummaryForMaterialRenameShowsAddedRemoved() throws {
        let base = try makeMaterialProject(material: "Azure")
        let draft = try makeMaterialProject(material: "Ember")
        let summary = ChangeSummary.diff(old: base.content, new: draft.content)
        // All IDs change when material name changes, so expect all added/removed.
        XCTAssertFalse(summary.added.isEmpty)
        XCTAssertFalse(summary.removed.isEmpty)
        XCTAssertTrue(summary.modified.isEmpty)
        // Added IDs should contain ember, removed should contain azure.
        XCTAssertTrue(summary.added.contains { $0.contentID.rawValue.contains("ember") })
        XCTAssertTrue(summary.removed.contains { $0.contentID.rawValue.contains("azure") })
    }

    // MARK: - No partial write on failure

    func testNoPartialWriteWhenValidationFails() async throws {
        let base = try makeSwordProject()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let compiler = BedrockAddOnCompiler()
        _ = try compiler.compile(project: base, profile: .current, outputDirectory: directory)
        let sidecarURL = AddOnProjectStore.sidecarURL(for: base.id, in: directory)
        let originalData = try Data(contentsOf: sidecarURL)

        // Create an invalid draft: duplicate item IDs.
        let invalidItem = base.items[0]
        let invalidDraft = AddOnProject(
            id: UUID(),
            namespace: "craftberry",
            displayName: "Invalid",
            packUUIDs: testIdentity().packUUIDs,
            buildVersion: VersionTriplet(major: 1, minor: 0, patch: 0),
            targetProfileID: BedrockContentProfile.current.id,
            originalPrompt: "invalid",
            content: base.content + [.item(invalidItem)]
        )
        let service = AddOnRevisionService()

        do {
            _ = try await service.reviseWithDraft(baseProject: base, draft: invalidDraft, newPrompt: "invalid revision", outputDirectory: directory)
            XCTFail("Expected validation failure")
        } catch let error as RevisionError {
            guard case .validationFailed = error else { return XCTFail("Wrong error \(error)") }
        }

        // Sidecar must be unchanged.
        let afterData = try Data(contentsOf: sidecarURL)
        XCTAssertEqual(originalData, afterData)
        // No bumped build directory created.
        let bumped = directory
            .appending(path: base.id.uuidString.lowercased(), directoryHint: .isDirectory)
            .appending(path: "builds/1.0.1", directoryHint: .isDirectory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: bumped.path))
    }

    func testNoPartialWriteWhenCompileFails() async throws {
        let base = try makeSwordProject()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let compiler = BedrockAddOnCompiler()
        _ = try compiler.compile(project: base, profile: .current, outputDirectory: directory)
        let sidecarURL = AddOnProjectStore.sidecarURL(for: base.id, in: directory)
        let originalData = try Data(contentsOf: sidecarURL)

        let draft = try makeSwordProject(displayName: "Azure Sword", attack: 12)
        let failingCompiler = FailingCompiler()
        let service = AddOnRevisionService(compiler: failingCompiler)

        do {
            _ = try await service.reviseWithDraft(baseProject: base, draft: draft, newPrompt: "will fail compile", outputDirectory: directory)
            XCTFail("Expected compile failure")
        } catch {}

        // Original sidecar restored.
        let afterData = try Data(contentsOf: sidecarURL)
        XCTAssertEqual(originalData, afterData)
        let bumped = directory
            .appending(path: base.id.uuidString.lowercased(), directoryHint: .isDirectory)
            .appending(path: "builds/1.0.1", directoryHint: .isDirectory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: bumped.path))
    }

    // MARK: - Fake client flows

    func testReviseWithFakeClientReadyFlow() async throws {
        let base = try makeSwordProject()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        // Seed sidecar via initial compile so revise can load if needed.
        _ = try BedrockAddOnCompiler().compile(project: base, profile: .current, outputDirectory: directory)

        let draft = try AddOnProject.materialSwordSet(materialName: "Ember", sourceItem: "minecraft:diamond", sourceCount: 4, originalPrompt: "ember set", identity: testIdentity(suffix: "zzzzzz"))
        let client = FakeLLMClient(result: .success(ProjectGeneration(outcome: .ready, message: "Ready", project: draft)))
        let service = AddOnRevisionService()
        let result = try await service.revise(baseProject: base, newPrompt: "make ember set", client: client, outputDirectory: directory)
        XCTAssertEqual(result.project.id, base.id)
        XCTAssertEqual(result.project.buildVersion, VersionTriplet(major: 1, minor: 0, patch: 1))
        XCTAssertFalse(result.changeSummary.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.compilationResult.artifact.url.path))
    }

    func testReviseWithFakeClientUnsupportedFlowThrows() async throws {
        let base = try makeSwordProject()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = FakeLLMClient(result: .success(ProjectGeneration(outcome: .unsupported, message: "Cannot do that", project: nil)))
        let service = AddOnRevisionService()
        do {
            _ = try await service.revise(baseProject: base, newPrompt: "unsupported", client: client, outputDirectory: directory)
            XCTFail("Expected unsupported error")
        } catch let error as RevisionError {
            XCTAssertEqual(error, .unsupported("Cannot do that"))
        }
        // No write on unsupported.
        let sidecarURL = AddOnProjectStore.sidecarURL(for: base.id, in: directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarURL.path))
    }

    func testReviseWithFakeClientFailurePropagates() async throws {
        let base = try makeSwordProject()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = FakeLLMClient(result: .failure(TestError.network))
        let service = AddOnRevisionService()
        do {
            _ = try await service.revise(baseProject: base, newPrompt: "will fail", client: client, outputDirectory: directory)
            XCTFail("Expected throw")
        } catch let error as TestError {
            XCTAssertEqual(error, .network)
        }
    }

    func testLoadProjectFromSidecarURL() throws {
        let project = try makeSwordProject()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try BedrockAddOnCompiler().compile(project: project, profile: .current, outputDirectory: directory)
        let sidecarURL = AddOnProjectStore.sidecarURL(for: project.id, in: directory)
        let loaded = try AddOnProjectStore.load(from: sidecarURL)
        XCTAssertEqual(loaded, project)
    }
}

// MARK: - Test doubles

private enum TestError: LocalizedError, Equatable {
    case network
    var errorDescription: String? { "network" }
}

private enum FakeLLMResult: Sendable {
    case success(ProjectGeneration)
    case failure(TestError)
}

private struct FakeLLMClient: LLMClient {
    let result: FakeLLMResult
    func generateProject(from prompt: String) async throws -> ProjectGeneration {
        switch result {
        case .success(let gen): return gen
        case .failure(let err): throw err
        }
    }
}

private struct FailingCompiler: AddOnCompiling {
    func compile(project: AddOnProject, profile: BedrockContentProfile, outputDirectory: URL) throws -> BedrockCompilationResult {
        throw TestError.network
    }
}
