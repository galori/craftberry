import Foundation
import XCTest
#if canImport(CraftberryCore)
@testable import CraftberryCore
#else
@testable import Craftberry
#endif

final class AddOnProjectTests: XCTestCase {
    func testMaterialWeaponSetCreatesIngotAndMeleeWeapons() throws {
        let project = try AddOnProject.materialWeaponSet(
            materialName: "Azure",
            sourceItem: "minecraft:diamond",
            sourceCount: 4,
            originalPrompt: "Azure weapons",
            identity: testIdentity()
        )

        XCTAssertEqual(
            project.items.map(\.id),
            [
                ContentID("azure_a1b2c3_ingot"),
                ContentID("azure_a1b2c3_sword"),
                ContentID("azure_a1b2c3_dagger"),
                ContentID("azure_a1b2c3_spear"),
                ContentID("azure_a1b2c3_hammer")
            ]
        )
        XCTAssertEqual(project.items.map(\.displayName), ["Azure Ingot", "Azure Sword", "Azure Dagger", "Azure Spear", "Azure Hammer"])
        XCTAssertEqual(project.shapelessRecipes.first?.ingredients, Array(repeating: .vanilla("minecraft:diamond"), count: 4))
        XCTAssertEqual(project.recipes.map(\.pattern), [[" I ", " I ", " S "], [" I ", " S "], ["  I", " S ", "S  "], ["III", " S ", " S "]])
        XCTAssertEqual(project.items.first { $0.id == ContentID("azure_a1b2c3_dagger") }?.traits.combat?.attackBonus, 7)
        XCTAssertEqual(project.items.first { $0.id == ContentID("azure_a1b2c3_hammer") }?.traits.combat?.attackBonus, 13)
        XCTAssertTrue(AddOnProjectValidator.validate(project, profile: .current).isSuccessful)
    }

    func testRecipeBookRowsCoverMaterialWeaponSetIncludingIngotRecipe() throws {
        let project = try AddOnProject.materialWeaponSet(materialName: "Azure", sourceItem: "minecraft:diamond", sourceCount: 4, originalPrompt: "Azure weapons", identity: testIdentity())
        let book = RecipeBook(project: project)

        XCTAssertEqual(book.rows.map { $0.item.displayName }, ["Azure Ingot", "Azure Sword", "Azure Dagger", "Azure Spear", "Azure Hammer"])
        XCTAssertEqual(book.rows.first?.summary, "4 Diamond -> Azure Ingot")
        XCTAssertEqual(book.rows.first { $0.item.displayName == "Azure Hammer" }?.summary, "3 Azure Ingot + 2 Stick -> Azure Hammer")
    }

    func testMaterialArmorSetCreatesIngotAndArmorPieces() throws {
        let project = try AddOnProject.materialArmorSet(
            materialName: "Azure",
            sourceItem: "minecraft:diamond",
            sourceCount: 4,
            originalPrompt: "Azure armor",
            identity: testIdentity()
        )

        XCTAssertEqual(
            project.items.map(\.id),
            [
                ContentID("azure_a1b2c3_ingot"),
                ContentID("azure_a1b2c3_helmet"),
                ContentID("azure_a1b2c3_chestplate"),
                ContentID("azure_a1b2c3_leggings"),
                ContentID("azure_a1b2c3_boots")
            ]
        )
        XCTAssertEqual(project.items.map(\.displayName), ["Azure Ingot", "Azure Helmet", "Azure Chestplate", "Azure Leggings", "Azure Boots"])
        XCTAssertEqual(project.shapelessRecipes.first?.ingredients, Array(repeating: .vanilla("minecraft:diamond"), count: 4))
        XCTAssertEqual(project.recipes.map(\.pattern), [["III", "I I"], ["I I", "III", "III"], ["III", "I I", "I I"], ["I I", "I I"]])
        // Default total protection (15) splits by the vanilla 3:8:6:3 ratio, matching iron's tier.
        XCTAssertEqual(project.items.compactMap { $0.traits.armor?.protection }, [2, 6, 5, 2])
        XCTAssertEqual(project.items.compactMap { $0.traits.armor?.slot }, [.head, .chest, .legs, .feet])
        let leggings = try XCTUnwrap(project.items.first { $0.id == ContentID("azure_a1b2c3_leggings") })
        let helmet = try XCTUnwrap(project.items.first { $0.id == ContentID("azure_a1b2c3_helmet") })
        XCTAssertNotEqual(leggings.traits.armor?.layerResourceID, helmet.traits.armor?.layerResourceID)
        XCTAssertTrue(AddOnProjectValidator.validate(project, profile: .current).isSuccessful)
    }

    func testMaterialArmorSetWithMaximumProtectionMatchesDiamondTier() throws {
        let project = try AddOnProject.materialArmorSet(
            materialName: "Azure",
            sourceItem: "minecraft:diamond",
            sourceCount: 4,
            protection: 20,
            originalPrompt: "Azure armor",
            identity: testIdentity()
        )
        XCTAssertEqual(project.items.compactMap { $0.traits.armor?.protection }, [3, 8, 6, 3])
    }

    func testRecipeBookRowsCoverMaterialArmorSetIncludingIngotRecipe() throws {
        let project = try AddOnProject.materialArmorSet(materialName: "Azure", sourceItem: "minecraft:diamond", sourceCount: 4, originalPrompt: "Azure armor", identity: testIdentity())
        let book = RecipeBook(project: project)

        XCTAssertEqual(book.rows.map { $0.item.displayName }, ["Azure Ingot", "Azure Helmet", "Azure Chestplate", "Azure Leggings", "Azure Boots"])
        XCTAssertEqual(book.rows.first?.summary, "4 Diamond -> Azure Ingot")
        XCTAssertEqual(book.rows.first { $0.item.displayName == "Azure Helmet" }?.summary, "5 Azure Ingot -> Azure Helmet")
    }

    func testMaterialArmorSetRejectsProtectionOutsideSupportedRange() throws {
        XCTAssertThrowsError(try AddOnProject.materialArmorSet(protection: 3, originalPrompt: "armor", identity: testIdentity())) {
            XCTAssertEqual($0 as? AddOnProjectError, .invalidArmorProtection)
        }
        XCTAssertThrowsError(try AddOnProject.materialArmorSet(protection: 21, originalPrompt: "armor", identity: testIdentity())) {
            XCTAssertEqual($0 as? AddOnProjectError, .invalidArmorProtection)
        }
    }

    func testProjectValidationRejectsUnsupportedArmorTrait() throws {
        let project = try AddOnProject.materialArmorSet(originalPrompt: "armor", identity: testIdentity())
        let profile = BedrockContentProfile(
            id: BedrockContentProfile.current.id,
            sampleVersion: BedrockContentProfile.current.sampleVersion,
            sourceCommit: BedrockContentProfile.current.sourceCommit,
            minimumEngineVersion: BedrockContentProfile.current.minimumEngineVersion,
            manifestFormatVersion: BedrockContentProfile.current.manifestFormatVersion,
            itemFormatVersion: BedrockContentProfile.current.itemFormatVersion,
            recipeFormatVersion: BedrockContentProfile.current.recipeFormatVersion,
            supportedItemTraits: [.durability],
            vanillaItemIdentifiers: BedrockContentProfile.current.vanillaItemIdentifiers,
            vanillaItemTags: BedrockContentProfile.current.vanillaItemTags
        )

        let report = AddOnProjectValidator.validate(project, profile: profile)

        XCTAssertTrue(report.errors.contains { $0.code == "unsupported_item_trait" })
    }

    func testMaterialToolSetCreatesIngotAndFiveTools() throws {
        let project = try AddOnProject.materialToolSet(
            materialName: "Azure",
            sourceItem: "minecraft:diamond",
            sourceCount: 4,
            originalPrompt: "Azure tools",
            identity: testIdentity()
        )

        XCTAssertEqual(
            project.items.map(\.id),
            [
                ContentID("azure_a1b2c3_ingot"),
                ContentID("azure_a1b2c3_sword"),
                ContentID("azure_a1b2c3_pickaxe"),
                ContentID("azure_a1b2c3_axe"),
                ContentID("azure_a1b2c3_shovel"),
                ContentID("azure_a1b2c3_hoe")
            ]
        )
        XCTAssertEqual(project.items.map(\.displayName), ["Azure Ingot", "Azure Sword", "Azure Pickaxe", "Azure Axe", "Azure Shovel", "Azure Hoe"])
        XCTAssertEqual(project.shapelessRecipes.first?.ingredients, Array(repeating: .vanilla("minecraft:diamond"), count: 4))
        XCTAssertEqual(project.recipes.map(\.pattern), [[" I ", " I ", " S "], ["III", " S ", " S "], ["II ", "IS ", " S "], [" I ", " S ", " S "], ["II ", " S ", " S "]])
        XCTAssertTrue(project.recipes.allSatisfy { $0.unlock == [.generated(ContentID("azure_a1b2c3_ingot"))] })
        XCTAssertTrue(AddOnProjectValidator.validate(project, profile: .current).isSuccessful)
    }

    func testRecipeBookRowsCoverMaterialToolSet() throws {
        let project = try AddOnProject.materialToolSet(materialName: "Azure", sourceItem: "minecraft:diamond", sourceCount: 4, originalPrompt: "Azure tools", identity: testIdentity())
        let book = RecipeBook(project: project)

        XCTAssertEqual(book.rows.count, 6)
        XCTAssertEqual(book.rows.first { $0.item.displayName == "Azure Pickaxe" }?.recipe?.gridReferences().compactMap { $0 }.count, 5)
        XCTAssertEqual(book.rows.first { $0.item.displayName == "Azure Shovel" }?.summary, "Azure Ingot + 2 Stick -> Azure Shovel")
    }

    func testMaterialSwordSetCreatesDerivedItemsAndRecipes() throws {
        let project = try AddOnProject.materialSwordSet(
            materialName: "Azure", sourceItem: "minecraft:diamond", sourceCount: 4,
            originalPrompt: "Azure diamond material set", identity: testIdentity()
        )

        XCTAssertEqual(project.schemaVersion, 3)
        XCTAssertEqual(project.items.map(\.id), [ContentID("azure_a1b2c3_ingot"), ContentID("azure_a1b2c3_sword")])
        XCTAssertEqual(project.items.first?.displayName, "Azure Ingot")
        XCTAssertEqual(project.items.first?.traits, ItemTraits())
        XCTAssertEqual(project.shapelessRecipes.first?.ingredients, Array(repeating: .vanilla("minecraft:diamond"), count: 4))
        XCTAssertEqual(project.recipes.first?.pattern, [" I ", " I ", " S "])
        XCTAssertEqual(project.recipes.first?.ingredients["I"], .generated(ContentID("azure_a1b2c3_ingot")))
        XCTAssertTrue(AddOnProjectValidator.validate(project, profile: .current).isSuccessful)
    }

    func testRecipeBookRowsCoverMaterialSwordSet() throws {
        let project = try AddOnProject.materialSwordSet(materialName: "Azure", sourceItem: "minecraft:diamond", sourceCount: 4, originalPrompt: "Azure diamond material set", identity: testIdentity())
        let book = RecipeBook(project: project)

        XCTAssertEqual(book.rows.map(\.summary), ["4 Diamond -> Azure Ingot", "2 Azure Ingot + Stick -> Azure Sword"])
    }

    func testMaterialSetRejectsInvalidShapelessIngredientCount() throws {
        let project = try AddOnProject.materialSwordSet(originalPrompt: "set", identity: testIdentity())
        let recipe = try XCTUnwrap(project.shapelessRecipes.first)
        let invalid = ShapelessRecipeDefinition(id: recipe.id, tags: recipe.tags, ingredients: [], result: recipe.result, unlock: recipe.unlock)
        let invalidProject = AddOnProject(schemaVersion: project.schemaVersion, id: project.id, namespace: project.namespace, displayName: project.displayName, packUUIDs: project.packUUIDs, buildVersion: project.buildVersion, targetProfileID: project.targetProfileID, originalPrompt: project.originalPrompt, content: project.content.map { if case .shapelessRecipe = $0 { return .shapelessRecipe(invalid) }; return $0 })
        XCTAssertEqual(AddOnProjectValidator.validate(invalidProject, profile: .current).errors.map(\.code), ["shapeless_recipe_ingredient_count"])
    }

    func testSwordSupportsEmeraldAsANonstandardSwordMaterial() throws {
        let project = try AddOnProject.sword(
            displayName: "Emerald Test Sword",
            color: .green,
            attackBonus: 14,
            durability: 500,
            craftingIngredient: "minecraft:emerald",
            originalPrompt: "An emerald sword"
        )

        XCTAssertEqual(project.items.first?.displayName, "Emerald Test Sword")
        XCTAssertEqual(project.recipes.first?.ingredients["M"], .vanilla("minecraft:emerald"))
    }

    func testRecipeBookRowsCoverSingleSword() throws {
        let project = try AddOnProject.sword(displayName: "Emerald Test Sword", craftingIngredient: "minecraft:emerald", originalPrompt: "An emerald sword", identity: testIdentity())
        let book = RecipeBook(project: project)

        XCTAssertEqual(book.rows.count, 1)
        XCTAssertEqual(book.rows.first?.summary, "2 Emerald + Stick -> Emerald Test Sword")
        XCTAssertEqual(book.rows.first?.recipe?.gridReferences().compactMap { $0 }.count, 3)
    }

    func testV1ProjectMigratesWithoutChangingIdentity() throws {
        let project = try makeSwordProject()
        let v1 = AddOnProject(schemaVersion: 1, id: project.id, namespace: project.namespace, displayName: project.displayName, packUUIDs: project.packUUIDs, buildVersion: project.buildVersion, targetProfileID: project.targetProfileID, originalPrompt: project.originalPrompt, content: project.content)
        let migrated = try v1.migratedToCurrentSchema()
        XCTAssertEqual(migrated.schemaVersion, 3)
        XCTAssertEqual(migrated.id, v1.id)
        XCTAssertEqual(migrated.packUUIDs, v1.packUUIDs)
        XCTAssertEqual(migrated.content, v1.content)
        XCTAssertFalse(migrated.shortDescription.isEmpty)
    }

    func testProjectStoresAndRoundTripsShortDescription() throws {
        let project = try AddOnProject.sword(
            displayName: "Azure Sword",
            shortDescription: "A bright custom sword tuned for quick cave runs.",
            originalPrompt: "A blue diamond sword",
            identity: testIdentity()
        )

        XCTAssertEqual(project.schemaVersion, 3)
        XCTAssertEqual(project.shortDescription, "A bright custom sword tuned for quick cave runs.")

        let sidecar = try JSONEncoder().encode(project)
        XCTAssertEqual(try JSONDecoder().decode(AddOnProject.self, from: sidecar), project)
    }

    func testV1AndV2ProjectsDecodeWithFallbackShortDescription() throws {
        let project = try AddOnProject.materialToolSet(originalPrompt: "Azure tools", identity: testIdentity())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as? [String: Any])
        object["shortDescription"] = nil

        object["schemaVersion"] = 1
        let v1Data = try JSONSerialization.data(withJSONObject: object)
        let v1 = try JSONDecoder().decode(AddOnProject.self, from: v1Data)
        XCTAssertEqual(v1.schemaVersion, 1)
        XCTAssertEqual(v1.shortDescription, "Azure adds 6 custom items with matching crafting recipes.")

        object["schemaVersion"] = 2
        let v2Data = try JSONSerialization.data(withJSONObject: object)
        let v2 = try JSONDecoder().decode(AddOnProject.self, from: v2Data)
        XCTAssertEqual(v2.schemaVersion, 2)
        XCTAssertEqual(v2.shortDescription, "Azure adds 6 custom items with matching crafting recipes.")
    }
    func testSwordArchetypeRejectsInvalidSemanticTraits() {
        XCTAssertThrowsError(
            try AddOnProject.sword(
                displayName: "Too Strong",
                color: .blue,
                attackBonus: 31,
                durability: 500,
                originalPrompt: "Too strong"
            )
        ) { error in
            XCTAssertEqual(error as? AddOnProjectError, .invalidAttackBonus)
        }

        XCTAssertThrowsError(
            try AddOnProject.sword(
                displayName: "Broken",
                color: .blue,
                attackBonus: 10,
                durability: 2,
                originalPrompt: "Broken"
            )
        ) { error in
            XCTAssertEqual(error as? AddOnProjectError, .invalidDurability)
        }
    }

    func testSwordProjectOwnsStableIdentityAndTypedReferences() throws {
        let identity = AddOnProjectIdentity(
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

        let project = try AddOnProject.sword(
            displayName: "Azure Sword",
            color: .blue,
            attackBonus: 20,
            durability: 500,
            craftingIngredient: "minecraft:diamond",
            originalPrompt: "A blue diamond sword",
            identity: identity,
            profile: .current
        )

        XCTAssertEqual(project.id, identity.projectID)
        XCTAssertEqual(project.namespace, "craftberry")
        XCTAssertEqual(project.targetProfileID, BedrockContentProfile.current.id)
        XCTAssertEqual(project.packUUIDs, identity.packUUIDs)
        XCTAssertEqual(project.buildVersion, .init(major: 1, minor: 0, patch: 0))
        XCTAssertEqual(project.items.map(\.id), [ContentID("azure_sword_a1b2c3")])
        XCTAssertEqual(project.recipes.first?.ingredients["M"], .vanilla("minecraft:diamond"))
        XCTAssertEqual(project.recipes.first?.result.item, .generated(ContentID("azure_sword_a1b2c3")))

        let sidecar = try JSONEncoder().encode(project)
        XCTAssertEqual(try JSONDecoder().decode(AddOnProject.self, from: sidecar), project)
    }

    func testProjectValidationRejectsDuplicateGeneratedItemIdentifiers() throws {
        let project = try makeSwordProject()
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

        let report = AddOnProjectValidator.validate(invalidProject, profile: .current)

        XCTAssertEqual(report.errors.map(\.code), ["duplicate_item_id"])
        XCTAssertFalse(report.isSuccessful)
    }

    func testProjectValidationRejectsDanglingGeneratedRecipeResult() throws {
        let project = try makeSwordProject()
        let recipe = try XCTUnwrap(project.recipes.first)
        let invalidRecipe = ShapedRecipeDefinition(
            id: recipe.id,
            tags: recipe.tags,
            pattern: recipe.pattern,
            ingredients: recipe.ingredients,
            result: RecipeResult(item: .generated(ContentID("missing_item")), count: 1),
            unlock: recipe.unlock
        )
        let invalidProject = replacingRecipe(in: project, with: invalidRecipe)

        let report = AddOnProjectValidator.validate(invalidProject, profile: .current)

        XCTAssertEqual(report.errors.map(\.code), ["missing_generated_reference"])
        XCTAssertEqual(report.errors.first?.path, "content.recipes.azure_sword_a1b2c3_recipe.result")
    }

    func testProjectValidationRequiresAnExplicitProfileMigration() throws {
        let project = try makeSwordProject()
        let incompatibleProject = AddOnProject(
            id: project.id,
            namespace: project.namespace,
            displayName: project.displayName,
            packUUIDs: project.packUUIDs,
            buildVersion: project.buildVersion,
            targetProfileID: "bedrock-stable-1.21.80",
            originalPrompt: project.originalPrompt,
            content: project.content
        )

        let report = AddOnProjectValidator.validate(incompatibleProject, profile: .current)

        XCTAssertEqual(report.errors.map(\.code), ["incompatible_profile"])
        XCTAssertEqual(report.errors.first?.path, "targetProfileID")
    }

    func testProjectValidationRejectsVanillaItemsOutsideThePinnedCatalog() throws {
        let project = try makeSwordProject()
        let recipe = try XCTUnwrap(project.recipes.first)
        var ingredients = recipe.ingredients
        ingredients["M"] = .vanilla("minecraft:not_in_profile")
        let invalidRecipe = ShapedRecipeDefinition(
            id: recipe.id,
            tags: recipe.tags,
            pattern: recipe.pattern,
            ingredients: ingredients,
            result: recipe.result,
            unlock: recipe.unlock
        )

        let report = AddOnProjectValidator.validate(
            replacingRecipe(in: project, with: invalidRecipe),
            profile: .current
        )

        XCTAssertEqual(report.errors.map(\.code), ["unsupported_vanilla_reference"])
    }

    func testProjectValidationRejectsRecipeDependencyCycles() throws {
        let project = try makeSwordProject()
        let firstItem = try XCTUnwrap(project.items.first)
        let firstRecipe = try XCTUnwrap(project.recipes.first)
        let secondID = ContentID("azure_ingot_a1b2c3")
        let secondItem = ItemDefinition(
            id: secondID,
            displayName: "Azure Ingot",
            menuCategory: firstItem.menuCategory,
            menuGroup: firstItem.menuGroup,
            traits: firstItem.traits,
            visualResourceID: firstItem.visualResourceID
        )
        let cyclicFirstRecipe = ShapedRecipeDefinition(
            id: firstRecipe.id,
            tags: firstRecipe.tags,
            pattern: firstRecipe.pattern,
            ingredients: ["M": .generated(secondID), "S": .vanilla("minecraft:stick")],
            result: firstRecipe.result,
            unlock: [.generated(secondID)]
        )
        let secondRecipe = ShapedRecipeDefinition(
            id: ContentID("azure_ingot_recipe"),
            tags: ["crafting_table"],
            pattern: ["A"],
            ingredients: ["A": .generated(firstItem.id)],
            result: RecipeResult(item: .generated(secondID), count: 1),
            unlock: [.generated(firstItem.id)]
        )
        let invalidProject = AddOnProject(
            id: project.id,
            namespace: project.namespace,
            displayName: project.displayName,
            packUUIDs: project.packUUIDs,
            buildVersion: project.buildVersion,
            targetProfileID: project.targetProfileID,
            originalPrompt: project.originalPrompt,
            content: project.content.compactMap { node in
                if case .shapedRecipe = node { return nil }
                return node
            } + [.item(secondItem), .shapedRecipe(cyclicFirstRecipe), .shapedRecipe(secondRecipe)]
        )

        let report = AddOnProjectValidator.validate(invalidProject, profile: .current)

        XCTAssertEqual(report.errors.map(\.code), ["recipe_dependency_cycle"])
    }

    func testProjectValidationRejectsRecipePatternsWiderThanTheCraftingGrid() throws {
        let project = try makeSwordProject()
        let recipe = try XCTUnwrap(project.recipes.first)
        let invalidRecipe = ShapedRecipeDefinition(
            id: recipe.id,
            tags: recipe.tags,
            pattern: ["MMSM"],
            ingredients: recipe.ingredients,
            result: recipe.result,
            unlock: recipe.unlock
        )

        let report = AddOnProjectValidator.validate(
            replacingRecipe(in: project, with: invalidRecipe),
            profile: .current
        )

        XCTAssertEqual(report.errors.map(\.code), ["recipe_pattern_width"])
    }

    func testProjectValidationRejectsInvalidRecipeStructure() throws {
        let project = try makeSwordProject()
        let recipe = try XCTUnwrap(project.recipes.first)
        var ingredients = recipe.ingredients
        ingredients["Z"] = .vanilla("minecraft:stick")
        let invalidRecipe = ShapedRecipeDefinition(
            id: recipe.id,
            tags: recipe.tags,
            pattern: [" M ", " M ", " S ", " S "],
            ingredients: ingredients,
            result: RecipeResult(item: recipe.result.item, count: 65),
            unlock: []
        )

        let report = AddOnProjectValidator.validate(
            replacingRecipe(in: project, with: invalidRecipe),
            profile: .current
        )

        XCTAssertEqual(
            Set(report.errors.map(\.code)),
            ["recipe_pattern_height", "recipe_result_count", "recipe_unlock_required", "unused_recipe_symbol"]
        )
    }

    func testProjectValidationRejectsMissingVisualsAndUndefinedRecipeSymbols() throws {
        let project = try makeSwordProject()
        let item = try XCTUnwrap(project.items.first)
        let recipe = try XCTUnwrap(project.recipes.first)
        let invalidItem = ItemDefinition(
            id: item.id,
            displayName: item.displayName,
            menuCategory: item.menuCategory,
            menuGroup: item.menuGroup,
            traits: item.traits,
            visualResourceID: ContentID("missing_texture")
        )
        let invalidRecipe = ShapedRecipeDefinition(
            id: recipe.id,
            tags: recipe.tags,
            pattern: [" X "],
            ingredients: [:],
            result: recipe.result,
            unlock: recipe.unlock
        )
        let invalidProject = AddOnProject(
            id: project.id,
            namespace: project.namespace,
            displayName: project.displayName,
            packUUIDs: project.packUUIDs,
            buildVersion: project.buildVersion,
            targetProfileID: project.targetProfileID,
            originalPrompt: project.originalPrompt,
            content: [.item(invalidItem), .shapedRecipe(invalidRecipe)]
        )

        let report = AddOnProjectValidator.validate(invalidProject, profile: .current)

        XCTAssertEqual(
            Set(report.errors.map(\.code)),
            ["missing_visual_resource", "undefined_recipe_symbol"]
        )
    }

    func testProjectValidationRejectsDuplicateRecipesAndVisualResources() throws {
        let project = try makeSwordProject()
        let recipe = try XCTUnwrap(project.recipes.first)
        let visual = try XCTUnwrap(project.visualResources.first)
        let invalidProject = AddOnProject(
            id: project.id,
            namespace: project.namespace,
            displayName: project.displayName,
            packUUIDs: project.packUUIDs,
            buildVersion: project.buildVersion,
            targetProfileID: project.targetProfileID,
            originalPrompt: project.originalPrompt,
            content: project.content + [.shapedRecipe(recipe), .visualResource(visual)]
        )

        let report = AddOnProjectValidator.validate(invalidProject, profile: .current)

        XCTAssertEqual(
            Set(report.errors.map(\.code)),
            ["duplicate_recipe_id", "duplicate_visual_resource_id"]
        )
    }

    func testProjectValidationRejectsInvalidItemLimitsAndReusedPackUUIDs() throws {
        let project = try makeSwordProject()
        let item = try XCTUnwrap(project.items.first)
        let invalidItem = ItemDefinition(
            id: item.id,
            displayName: item.displayName,
            menuCategory: item.menuCategory,
            menuGroup: item.menuGroup,
            traits: ItemTraits(
                combat: CombatTrait(attackBonus: 31),
                durability: DurabilityTrait(maximum: 0),
                handEquipped: true,
                maximumStackSize: 65
            ),
            visualResourceID: item.visualResourceID
        )
        let repeatedUUID = project.packUUIDs.behaviorHeader
        let invalidProject = AddOnProject(
            id: project.id,
            namespace: project.namespace,
            displayName: project.displayName,
            packUUIDs: PackUUIDs(
                behaviorHeader: repeatedUUID,
                behaviorModule: repeatedUUID,
                resourceHeader: project.packUUIDs.resourceHeader,
                resourceModule: project.packUUIDs.resourceModule
            ),
            buildVersion: project.buildVersion,
            targetProfileID: project.targetProfileID,
            originalPrompt: project.originalPrompt,
            content: project.content.map { node in
                if case .item = node { return .item(invalidItem) }
                return node
            }
        )

        let report = AddOnProjectValidator.validate(invalidProject, profile: .current)

        XCTAssertEqual(
            Set(report.errors.map(\.code)),
            ["duplicate_pack_uuid", "invalid_attack_bonus", "invalid_durability", "invalid_stack_size"]
        )
    }

    func testProjectValidationRejectsIdentifiersThatCouldEscapePackPaths() throws {
        let project = try makeSwordProject()
        let item = try XCTUnwrap(project.items.first)
        let visual = try XCTUnwrap(project.visualResources.first)
        let unsafeID = ContentID("../escaped")
        let unsafeItem = ItemDefinition(
            id: unsafeID,
            displayName: item.displayName,
            menuCategory: item.menuCategory,
            menuGroup: item.menuGroup,
            traits: item.traits,
            visualResourceID: unsafeID
        )
        let unsafeVisual = VisualResource(id: unsafeID, kind: visual.kind, color: visual.color)
        let invalidProject = AddOnProject(
            id: project.id,
            namespace: "Craftberry/../outside",
            displayName: project.displayName,
            packUUIDs: project.packUUIDs,
            buildVersion: project.buildVersion,
            targetProfileID: project.targetProfileID,
            originalPrompt: project.originalPrompt,
            content: [.item(unsafeItem), .visualResource(unsafeVisual)]
        )

        let report = AddOnProjectValidator.validate(invalidProject, profile: .current)

        XCTAssertTrue(report.errors.map(\.code).contains("invalid_namespace"))
        XCTAssertTrue(report.errors.map(\.code).contains("invalid_content_id"))
    }

    func testProjectValidationRejectsValuesThatWouldCorruptBedrockDocuments() throws {
        let project = try makeSwordProject()
        let item = try XCTUnwrap(project.items.first)
        let invalidItem = ItemDefinition(
            id: item.id,
            displayName: "Azure\nitem.injected=Injected",
            menuCategory: item.menuCategory,
            menuGroup: "itemGroup.name.sword",
            traits: item.traits,
            visualResourceID: item.visualResourceID
        )
        let invalidProject = AddOnProject(
            id: project.id,
            namespace: project.namespace,
            displayName: project.displayName,
            packUUIDs: project.packUUIDs,
            buildVersion: project.buildVersion,
            targetProfileID: project.targetProfileID,
            originalPrompt: project.originalPrompt,
            content: project.content.map { node in
                if case .item = node { return .item(invalidItem) }
                return node
            }
        )

        let report = AddOnProjectValidator.validate(invalidProject, profile: .current)

        XCTAssertEqual(
            Set(report.errors.map(\.code)),
            ["invalid_localization_value", "invalid_menu_group"]
        )
    }

    func testProjectValidationRejectsUnknownSidecarVersionsAndUnsupportedTraits() throws {
        let project = try makeSwordProject()
        let profile = BedrockContentProfile(
            id: project.targetProfileID,
            sampleVersion: BedrockContentProfile.current.sampleVersion,
            sourceCommit: BedrockContentProfile.current.sourceCommit,
            minimumEngineVersion: BedrockContentProfile.current.minimumEngineVersion,
            manifestFormatVersion: BedrockContentProfile.current.manifestFormatVersion,
            itemFormatVersion: BedrockContentProfile.current.itemFormatVersion,
            recipeFormatVersion: BedrockContentProfile.current.recipeFormatVersion,
            supportedItemTraits: [.durability, .handEquipped],
            vanillaItemIdentifiers: BedrockContentProfile.current.vanillaItemIdentifiers,
            vanillaItemTags: BedrockContentProfile.current.vanillaItemTags
        )
        let invalidProject = AddOnProject(
            schemaVersion: AddOnProject.currentSchemaVersion + 1,
            id: project.id,
            namespace: project.namespace,
            displayName: project.displayName,
            packUUIDs: project.packUUIDs,
            buildVersion: project.buildVersion,
            targetProfileID: project.targetProfileID,
            originalPrompt: project.originalPrompt,
            content: project.content
        )

        let report = AddOnProjectValidator.validate(invalidProject, profile: profile)

        XCTAssertEqual(
            Set(report.errors.map(\.code)),
            ["unsupported_project_schema_version", "unsupported_item_trait"]
        )
    }

    private func makeSwordProject() throws -> AddOnProject {
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

    private func testIdentity() -> AddOnProjectIdentity {
        AddOnProjectIdentity(projectID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!, namespace: "craftberry", contentSuffix: "a1b2c3", packUUIDs: PackUUIDs(behaviorHeader: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!, behaviorModule: UUID(uuidString: "20000000-0000-4000-8000-000000000002")!, resourceHeader: UUID(uuidString: "20000000-0000-4000-8000-000000000003")!, resourceModule: UUID(uuidString: "20000000-0000-4000-8000-000000000004")!))
    }

    private func replacingRecipe(
        in project: AddOnProject,
        with recipe: ShapedRecipeDefinition
    ) -> AddOnProject {
        AddOnProject(
            id: project.id,
            namespace: project.namespace,
            displayName: project.displayName,
            packUUIDs: project.packUUIDs,
            buildVersion: project.buildVersion,
            targetProfileID: project.targetProfileID,
            originalPrompt: project.originalPrompt,
            content: project.content.map { node in
                if case .shapedRecipe = node { return .shapedRecipe(recipe) }
                return node
            }
        )
    }
}
