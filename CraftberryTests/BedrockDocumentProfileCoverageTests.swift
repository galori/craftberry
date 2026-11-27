import Foundation
import XCTest
#if canImport(CraftberryCore)
@testable import CraftberryCore
#else
@testable import Craftberry
#endif

final class BedrockDocumentProfileCoverageTests: XCTestCase {
    func testGeneratedBlockUsesThePinnedMenuCategoryFieldName() throws {
        let project = try AddOnProject.materialBlockSet(originalPrompt: "schema fixture", identity: .generate())
        let entries = try behaviorEntries(for: project)
        let blockEntry = try XCTUnwrap(entries.first { $0.path.hasPrefix("blocks/") && $0.path.hasSuffix(".json") })
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: blockEntry.data) as? [String: Any])
        let block = try XCTUnwrap(document["minecraft:block"] as? [String: Any])
        let description = try XCTUnwrap(block["description"] as? [String: Any])
        let menuCategory = try XCTUnwrap(description["menu_category"] as? [String: Any])

        XCTAssertEqual(menuCategory["category"] as? String, "construction")
        XCTAssertNil(description["menuCategory"])
    }

    func testSmithingTransformMatchesThePinnedVanillaRecipeShape() throws {
        let project = try AddOnProject.materialSmithingSet(originalPrompt: "schema fixture", identity: .generate())
        let entries = try behaviorEntries(for: project)
        let recipeEntry = try XCTUnwrap(entries.first { $0.path.hasSuffix("_sword_smithing_recipe.json") })
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: recipeEntry.data) as? [String: Any])
        let recipe = try XCTUnwrap(document["minecraft:recipe_smithing_transform"] as? [String: Any])

        XCTAssertEqual(recipe["template"] as? String, "minecraft:netherite_upgrade_smithing_template")
        XCTAssertEqual(recipe["base"] as? String, "minecraft:diamond_sword")
        XCTAssertEqual(recipe["addition"] as? String, project.items.first(where: { $0.id.rawValue.hasSuffix("_ingot") }).map { "\(project.namespace):\($0.id.rawValue)" })
    }

    func testGeneratedEntityDeclaresReferencedAgeableEvents() throws {
        let project = try AddOnProject.materialEntitySet(originalPrompt: "schema fixture", identity: .generate())
        let entity = try XCTUnwrap(project.entities.first)
        let entries = try behaviorEntries(for: project)
        let entityEntry = try XCTUnwrap(entries.first { $0.path == "entities/\(entity.id.rawValue).json" })
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: entityEntry.data) as? [String: Any])
        let entityDocument = try XCTUnwrap(document["minecraft:entity"] as? [String: Any])
        let events = try XCTUnwrap(entityDocument["events"] as? [String: Any])
        let componentGroups = try XCTUnwrap(entityDocument["component_groups"] as? [String: Any])

        let adult = try XCTUnwrap(componentGroups["\(entity.id.rawValue)_adult"] as? [String: Any])
        let adultScale = try XCTUnwrap(adult["minecraft:scale"] as? [String: Any])
        XCTAssertEqual(adultScale["value"] as? Double, entity.scale)

        let spawned = try XCTUnwrap(events["minecraft:entity_spawned"] as? [String: Any])
        let spawnedAdd = try XCTUnwrap(spawned["add"] as? [String: Any])
        XCTAssertEqual(spawnedAdd["component_groups"] as? [String], ["\(entity.id.rawValue)_adult"])

        let born = try XCTUnwrap(events["minecraft:entity_born"] as? [String: Any])
        let bornAdd = try XCTUnwrap(born["add"] as? [String: Any])
        XCTAssertEqual(bornAdd["component_groups"] as? [String], ["\(entity.id.rawValue)_baby"])

        let grewUp = try XCTUnwrap(events["minecraft:ageable_grow_up"] as? [String: Any])
        let removed = try XCTUnwrap(grewUp["remove"] as? [String: Any])
        let added = try XCTUnwrap(grewUp["add"] as? [String: Any])
        XCTAssertEqual(removed["component_groups"] as? [String], ["\(entity.id.rawValue)_baby"])
        XCTAssertEqual(added["component_groups"] as? [String], ["\(entity.id.rawValue)_adult"])
    }

    private func behaviorEntries(for project: AddOnProject) throws -> [ZipArchiveEntry] {
        let outputDirectory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        let result = try BedrockAddOnCompiler().compile(project: project, profile: .current, outputDirectory: outputDirectory)
        let packs = try ZipArchiveReader.readEntries(at: result.artifact.url)
        let behaviorPack = try XCTUnwrap(packs.first { $0.path.hasSuffix("_behavior.mcpack") })
        return try ZipArchiveReader.readEntries(data: behaviorPack.data)
    }

    private func makeScratchDirectory() throws -> URL {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scratchRoot = projectRoot.appending(path: ".scratch", directoryHint: .isDirectory)
        let outputDirectory = scratchRoot.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        return outputDirectory
    }
}
