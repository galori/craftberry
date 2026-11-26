import Foundation
import XCTest
#if canImport(CraftberryCore)
@testable import CraftberryCore
#else
@testable import Craftberry
#endif

final class GeneratedVanillaItemCatalogTests: XCTestCase {
    func testGeneratedCatalogMatchesTheExplicitSupportedSubset() throws {
        let allowlistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Config/vanilla-catalog-allowlist.json")
        let data = try Data(contentsOf: allowlistURL)
        let allowlist = try JSONDecoder().decode(VanillaCatalogAllowlist.self, from: data)

        XCTAssertEqual(allowlist.profileID, BedrockContentProfile.current.id)
        XCTAssertEqual(allowlist.sampleVersion, BedrockContentProfile.current.sampleVersion)
        XCTAssertEqual(allowlist.sourceCommit, BedrockContentProfile.current.sourceCommit)
        XCTAssertEqual(GeneratedVanillaItemCatalog.sourceVersion, allowlist.sampleVersion)
        XCTAssertEqual(GeneratedVanillaItemCatalog.sourceCommit, allowlist.sourceCommit)
        XCTAssertEqual(Set(allowlist.materialSources), GeneratedVanillaItemCatalog.materialSources)
        XCTAssertEqual(Set(allowlist.smithingTemplates), GeneratedVanillaItemCatalog.smithingTemplates)
        XCTAssertEqual(Set(allowlist.smithingBases), GeneratedVanillaItemCatalog.smithingBases)
        XCTAssertEqual(Set(allowlist.brewingInputs), GeneratedVanillaItemCatalog.brewingInputs)
        XCTAssertEqual(Set(allowlist.brewingReagents), GeneratedVanillaItemCatalog.brewingReagents)
        XCTAssertEqual(allowlist.itemTags, [GeneratedVanillaItemCatalog.trimmableArmorTag])
        XCTAssertEqual(Set(allowlist.itemTags), GeneratedVanillaItemCatalog.itemTags)
        XCTAssertEqual(Set(allowlist.recipeForms), GeneratedVanillaItemCatalog.recipeForms)
        let categorizedIdentifiers = Set(
            allowlist.materialSources + allowlist.smithingTemplates + allowlist.smithingBases + allowlist.brewingInputs + allowlist.brewingReagents
        )
        XCTAssertEqual(GeneratedVanillaItemCatalog.identifiers.subtracting(categorizedIdentifiers), Set(allowlist.additionalIdentifiers))
        XCTAssertEqual(GeneratedVanillaItemCatalog.identifiers, categorizedIdentifiers.union(allowlist.additionalIdentifiers))
    }

    func testStableRecipeFormInventoryCoversEveryTypedRecipeNode() throws {
        let allowlistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Config/vanilla-catalog-allowlist.json")
        let allowlist = try JSONDecoder().decode(VanillaCatalogAllowlist.self, from: Data(contentsOf: allowlistURL))

        XCTAssertEqual(Set(allowlist.recipeForms), [
            "minecraft:recipe_shaped",
            "minecraft:recipe_shapeless",
            "minecraft:recipe_furnace",
            "minecraft:recipe_smithing_transform",
            "minecraft:recipe_smithing_trim",
            "minecraft:recipe_brewing_mix",
            "minecraft:recipe_brewing_container"
        ])

        let sword = try AddOnProject.materialSwordSet(originalPrompt: "catalog", identity: .generate())
        let furnace = try AddOnProject.materialFurnaceSet(originalPrompt: "catalog", identity: .generate())
        let smithing = try AddOnProject.materialSmithingSet(originalPrompt: "catalog", identity: .generate())
        let brewing = try AddOnProject.materialBrewingSet(originalPrompt: "catalog", identity: .generate())
        let forms = Set((sword.content + furnace.content + smithing.content + brewing.content).compactMap(recipeForm))

        XCTAssertEqual(forms, Set(allowlist.recipeForms))
    }

    private func recipeForm(_ node: AddOnContentNode) -> String? {
        switch node {
        case .shapedRecipe: "minecraft:recipe_shaped"
        case .shapelessRecipe: "minecraft:recipe_shapeless"
        case .furnaceRecipe: "minecraft:recipe_furnace"
        case .smithingTransformRecipe: "minecraft:recipe_smithing_transform"
        case .smithingTrimRecipe: "minecraft:recipe_smithing_trim"
        case .brewingMixRecipe: "minecraft:recipe_brewing_mix"
        case .brewingContainerRecipe: "minecraft:recipe_brewing_container"
        default: nil
        }
    }
}

private struct VanillaCatalogAllowlist: Decodable {
    let profileID: String
    let sampleVersion: String
    let sourceCommit: String
    let materialSources: [String]
    let additionalIdentifiers: [String]
    let smithingTemplates: [String]
    let smithingBases: [String]
    let brewingInputs: [String]
    let brewingReagents: [String]
    let itemTags: [String]
    let recipeForms: [String]
}
