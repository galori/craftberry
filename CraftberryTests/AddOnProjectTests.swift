import Foundation
import XCTest
#if canImport(CraftberryCore)
@testable import CraftberryCore
#else
@testable import Craftberry
#endif

final class AddOnProjectTests: XCTestCase {
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
            schemaVersion: 2,
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
