import Foundation
import XCTest
#if canImport(CraftberryCore)
@testable import CraftberryCore
#else
@testable import Craftberry
#endif

final class BedrockCompilerTests: XCTestCase {
    func testCompilerPersistsProjectSidecarBesideVersionedBuild() throws {
        let project = try makeProject()
        let outputDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let result = try BedrockAddOnCompiler().compile(
            project: project,
            profile: .current,
            outputDirectory: outputDirectory
        )

        let projectDirectory = outputDirectory.appending(path: project.id.uuidString.lowercased())
        XCTAssertEqual(result.artifact.projectSidecarURL, projectDirectory.appending(path: "project.json"))
        XCTAssertEqual(
            result.artifact.url,
            projectDirectory
                .appending(path: "builds/1.0.0", directoryHint: .isDirectory)
                .appending(path: "azure_sword_a1b2c3.mcaddon")
        )
        XCTAssertEqual(
            try JSONDecoder().decode(AddOnProject.self, from: Data(contentsOf: result.artifact.projectSidecarURL)),
            project
        )
        XCTAssertTrue(result.report.isSuccessful)
        XCTAssertEqual(result.report.profileID, BedrockContentProfile.current.id)
        XCTAssertTrue(result.report.emittedFiles.contains("azure_sword_a1b2c3_behavior.mcpack"))
        XCTAssertTrue(result.report.emittedFiles.contains("azure_sword_a1b2c3_resources.mcpack"))
    }

    func testCompilerValidatesTheWholeGraphBeforeWritingAnything() throws {
        let project = try makeProject()
        let item = try XCTUnwrap(project.items.first)
        let invalidProject = AddOnProject(
            id: project.id,
            namespace: project.namespace,
            displayName: project.displayName,
            packUUIDs: project.packUUIDs,
            buildVersion: project.buildVersion,
            targetProfileID: project.targetProfileID,
            originalPrompt: project.originalPrompt,
            content: project.content + [.item(item)]
        )
        let outputDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        XCTAssertThrowsError(
            try BedrockAddOnCompiler().compile(
                project: invalidProject,
                profile: .current,
                outputDirectory: outputDirectory
            )
        ) { error in
            guard case BedrockCompilationError.invalidProject(let report) = error else {
                return XCTFail("Expected an invalid-project report, got \(error)")
            }
            XCTAssertEqual(report.errors.map(\.code), ["duplicate_item_id"])
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    func testCompilerUsesPinnedProfileAndStablePackIdentity() throws {
        let project = try makeProject()
        let outputDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        let result = try BedrockAddOnCompiler().compile(
            project: project,
            profile: .current,
            outputDirectory: outputDirectory
        )
        let addOn = try ZipArchiveReader.readEntries(at: result.artifact.url)
        let behaviorPack = try pack(named: "azure_sword_a1b2c3_behavior.mcpack", in: addOn)
        let resourcePack = try pack(named: "azure_sword_a1b2c3_resources.mcpack", in: addOn)
        let behaviorManifest = try json(named: "manifest.json", in: behaviorPack)
        let resourceManifest = try json(named: "manifest.json", in: resourcePack)

        let behaviorHeader = try XCTUnwrap(behaviorManifest["header"] as? [String: Any])
        let behaviorModules = try XCTUnwrap(behaviorManifest["modules"] as? [[String: Any]])
        let dependencies = try XCTUnwrap(behaviorManifest["dependencies"] as? [[String: Any]])
        let resourceHeader = try XCTUnwrap(resourceManifest["header"] as? [String: Any])
        let resourceModules = try XCTUnwrap(resourceManifest["modules"] as? [[String: Any]])

        XCTAssertEqual(behaviorHeader["min_engine_version"] as? [Int], [1, 26, 30])
        XCTAssertEqual(behaviorHeader["uuid"] as? String, project.packUUIDs.behaviorHeader.uuidString.lowercased())
        XCTAssertEqual(behaviorModules.first?["uuid"] as? String, project.packUUIDs.behaviorModule.uuidString.lowercased())
        XCTAssertEqual(resourceHeader["min_engine_version"] as? [Int], [1, 26, 30])
        XCTAssertEqual(resourceHeader["uuid"] as? String, project.packUUIDs.resourceHeader.uuidString.lowercased())
        XCTAssertEqual(resourceModules.first?["uuid"] as? String, project.packUUIDs.resourceModule.uuidString.lowercased())
        XCTAssertEqual(dependencies.first?["uuid"] as? String, project.packUUIDs.resourceHeader.uuidString.lowercased())
        XCTAssertEqual(dependencies.first?["version"] as? [Int], [1, 0, 0])
    }

    func testCompilerPackagingIsDeterministicForTheSameSemanticProject() throws {
        let project = try makeProject()
        let firstDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let secondDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: firstDirectory)
            try? FileManager.default.removeItem(at: secondDirectory)
        }

        let first = try BedrockAddOnCompiler().compile(
            project: project,
            profile: .current,
            outputDirectory: firstDirectory
        )
        let second = try BedrockAddOnCompiler().compile(
            project: project,
            profile: .current,
            outputDirectory: secondDirectory
        )

        XCTAssertEqual(try Data(contentsOf: first.artifact.url), try Data(contentsOf: second.artifact.url))
    }

    func testCompilerCreatesACompositeAddOnWithBothPacks() throws {
        let project = try makeProject()
        let outputDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let result = try BedrockAddOnCompiler().compile(
            project: project,
            profile: .current,
            outputDirectory: outputDirectory
        )
        let artifact = result.artifact
        let archive = try ZipArchiveReader.readEntries(at: artifact.url)

        XCTAssertEqual(artifact.identifier.rawValue, "craftberry:azure_sword_a1b2c3")
        XCTAssertEqual(artifact.url.pathExtension, "mcaddon")
        XCTAssertEqual(artifact.fileName, "azure_sword_a1b2c3.mcaddon")
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.url.path))
        XCTAssertEqual(Set(archive.map(\.path)), Set(["azure_sword_a1b2c3_behavior.mcpack", "azure_sword_a1b2c3_resources.mcpack"]))
        XCTAssertTrue(archive.allSatisfy { $0.data.starts(with: [0x50, 0x4B, 0x03, 0x04]) })
    }

    func testCompilerEmitsItemRecipeAndOriginalPngTexture() throws {
        let outputDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        let result = try BedrockAddOnCompiler().compile(
            project: makeProject(),
            profile: .current,
            outputDirectory: outputDirectory
        )
        let archive = try ZipArchiveReader.readEntries(at: result.artifact.url)
        let behaviorPack = try pack(named: "azure_sword_a1b2c3_behavior.mcpack", in: archive)
        let resourcePack = try pack(named: "azure_sword_a1b2c3_resources.mcpack", in: archive)

        let item = try XCTUnwrap(behaviorPack.first(where: { $0.path == "items/azure_sword_a1b2c3.json" }))
        XCTAssertTrue(String(decoding: item.data, as: UTF8.self).contains("minecraft:damage"))
        XCTAssertTrue(String(decoding: item.data, as: UTF8.self).contains("\"value\" : 20"))
        let recipe = try XCTUnwrap(behaviorPack.first(where: { $0.path == "recipes/azure_sword_a1b2c3_recipe.json" }))
        let recipeJSON = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: recipe.data) as? [String: Any]
        )
        let shapedRecipe = try XCTUnwrap(recipeJSON["minecraft:recipe_shaped"] as? [String: Any])
        XCTAssertEqual(shapedRecipe["pattern"] as? [String], [" M ", " M ", " S "])
        let unlock = try XCTUnwrap(shapedRecipe["unlock"] as? [[String: String]])
        XCTAssertEqual(unlock, [["item": "minecraft:diamond"]])

        let texture = try XCTUnwrap(resourcePack.first(where: { $0.path == "textures/items/azure_sword_a1b2c3.png" }))
        XCTAssertEqual(Array(texture.data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        XCTAssertEqual(PNGInspector.dimensions(of: texture.data), .init(width: 32, height: 32))

        let itemJSON = String(decoding: item.data, as: UTF8.self)
        let itemObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: item.data) as? [String: Any])
        let itemBody = try XCTUnwrap(itemObject["minecraft:item"] as? [String: Any])
        let components = try XCTUnwrap(itemBody["components"] as? [String: Any])
        XCTAssertEqual(itemObject["format_version"] as? String, "1.21.100")
        XCTAssertEqual(
            (components["minecraft:hand_equipped"] as? [String: Bool])?["value"],
            true
        )
        XCTAssertTrue(itemJSON.contains("\"textures\" : {"))
        XCTAssertTrue(itemJSON.contains("\"default\" : \"azure_sword_a1b2c3\""))
        XCTAssertTrue(itemJSON.contains("\"value\" : \"item.craftberry:azure_sword_a1b2c3.name\""))
        XCTAssertTrue(itemJSON.contains("\"group\" : \"minecraft:itemGroup.name.sword\""))

        let textureMap = try XCTUnwrap(resourcePack.first(where: { $0.path == "textures/item_texture.json" }))
        let textureMapJSON = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: textureMap.data) as? [String: Any]
        )
        let textureData = try XCTUnwrap(textureMapJSON["texture_data"] as? [String: Any])
        XCTAssertEqual(
            (textureData["azure_sword_a1b2c3"] as? [String: String])?["textures"],
            "textures/items/azure_sword_a1b2c3"
        )
        XCTAssertNil(textureData["craftberry:azure_sword_a1b2c3"])

        let localization = try XCTUnwrap(resourcePack.first(where: { $0.path == "texts/en_US.lang" }))
        XCTAssertEqual(
            String(decoding: localization.data, as: UTF8.self),
            "item.craftberry:azure_sword_a1b2c3.name=Azure Sword\n"
        )

        let languages = try XCTUnwrap(resourcePack.first(where: { $0.path == "texts/languages.json" }))
        let languagesJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: languages.data) as? [String])
        XCTAssertEqual(languagesJSON, ["en_US"])
    }

    private func makeProject() throws -> AddOnProject {
        try AddOnProject.sword(
            displayName: "Azure Sword",
            color: .blue,
            attackBonus: 20,
            durability: 500,
            craftingIngredient: "minecraft:diamond",
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
            ),
            profile: .current
        )
    }

    private func pack(named name: String, in archive: [ZipArchiveEntry]) throws -> [ZipArchiveEntry] {
        try ZipArchiveReader.readEntries(
            data: try XCTUnwrap(archive.first(where: { $0.path == name })?.data)
        )
    }

    private func json(named name: String, in archive: [ZipArchiveEntry]) throws -> [String: Any] {
        let entry = try XCTUnwrap(archive.first(where: { $0.path == name }))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: entry.data) as? [String: Any])
    }
}
