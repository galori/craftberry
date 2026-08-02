import Foundation
import XCTest
#if canImport(CraftberryCore)
@testable import CraftberryCore
#else
@testable import Craftberry
#endif

final class BedrockCompilerTests: XCTestCase {
    func testCompilerCreatesACompositeAddOnWithBothPacks() throws {
        let specification = try SwordSpec(
            displayName: "Azure Sword",
            color: .blue,
            attackBonus: 20,
            durability: 500,
            craftingIngredient: .diamond
        )
        let outputDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let compiler = BedrockAddOnCompiler(
            suffixGenerator: { "a1b2c3" },
            uuidGenerator: { UUID(uuidString: "00000000-0000-4000-8000-000000000001")! }
        )
        let artifact = try compiler.compile(specification, outputDirectory: outputDirectory)
        let archive = try ZipArchiveReader.readEntries(at: artifact.url)

        XCTAssertEqual(artifact.identifier.rawValue, "craftberry:azure_sword_a1b2c3")
        XCTAssertEqual(artifact.url.pathExtension, "mcaddon")
        XCTAssertEqual(artifact.fileName, "azure_sword_a1b2c3.mcaddon")
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.url.path))
        XCTAssertEqual(Set(archive.map(\.path)), Set(["azure_sword_a1b2c3_behavior.mcpack", "azure_sword_a1b2c3_resources.mcpack"]))
        XCTAssertTrue(archive.allSatisfy { $0.data.starts(with: [0x50, 0x4B, 0x03, 0x04]) })
    }

    func testCompilerEmitsItemRecipeAndOriginalPngTexture() throws {
        let specification = try SwordSpec(
            displayName: "Azure Sword",
            color: .blue,
            attackBonus: 20,
            durability: 500,
            craftingIngredient: .diamond
        )
        let compiler = BedrockAddOnCompiler(
            suffixGenerator: { "a1b2c3" },
            uuidGenerator: { UUID(uuidString: "00000000-0000-4000-8000-000000000001")! }
        )
        let archive = try compiler.buildArchive(specification)
        let behaviorPack = try ZipArchiveReader.readEntries(data: try XCTUnwrap(archive.entries.first(where: { $0.path == "azure_sword_a1b2c3_behavior.mcpack" })?.data))
        let resourcePack = try ZipArchiveReader.readEntries(data: try XCTUnwrap(archive.entries.first(where: { $0.path == "azure_sword_a1b2c3_resources.mcpack" })?.data))

        let item = try XCTUnwrap(behaviorPack.first(where: { $0.path == "items/azure_sword_a1b2c3.json" }))
        XCTAssertTrue(String(decoding: item.data, as: UTF8.self).contains("minecraft:damage"))
        XCTAssertTrue(String(decoding: item.data, as: UTF8.self).contains("\"value\" : 20"))
        let recipe = try XCTUnwrap(behaviorPack.first(where: { $0.path == "recipes/azure_sword_a1b2c3.json" }))
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
}
