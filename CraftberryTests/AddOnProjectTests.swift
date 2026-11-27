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
            blockFormatVersion: BedrockContentProfile.current.blockFormatVersion,
            entityFormatVersion: BedrockContentProfile.current.entityFormatVersion,
            spawnRuleFormatVersion: BedrockContentProfile.current.spawnRuleFormatVersion,
            clientEntityFormatVersion: BedrockContentProfile.current.clientEntityFormatVersion,
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

    func testMaterialBlockSetCreatesExpectedIngotAndBlock() throws {
        let project = try AddOnProject.materialBlockSet(
            materialName: "Azure", color: .blue, sourceItem: "minecraft:diamond", sourceCount: 4,
            destroyTime: 3.0, mapColor: "#5CDBD5",
            shortDescription: "test", originalPrompt: "test", identity: testIdentity()
        )
        XCTAssertEqual(project.items.map(\.id), [ContentID("azure_a1b2c3_ingot"), ContentID("azure_a1b2c3_block")])
        XCTAssertEqual(project.blocks.map(\.id), [ContentID("azure_a1b2c3_block")])
        XCTAssertEqual(project.visualResources.count, 3)
        XCTAssertTrue(AddOnProjectValidator.validate(project, profile: .current).isSuccessful)
        let book = RecipeBook(project: project)
        XCTAssertEqual(book.rows.count, 2)
    }

    func testMaterialSwordSetCreatesDerivedItemsAndRecipes() throws {
        let project = try AddOnProject.materialSwordSet(
            materialName: "Azure", sourceItem: "minecraft:diamond", sourceCount: 4,
            originalPrompt: "Azure diamond material set", identity: testIdentity()
        )

        XCTAssertEqual(project.schemaVersion, AddOnProject.currentSchemaVersion)
        XCTAssertEqual(project.items.map(\.id), [ContentID("azure_a1b2c3_ingot"), ContentID("azure_a1b2c3_sword")])
        XCTAssertEqual(project.items.first?.displayName, "Azure Ingot")
        XCTAssertEqual(project.items.first?.traits, ItemTraits())
        XCTAssertEqual(project.shapelessRecipes.first?.ingredients, Array(repeating: .vanilla("minecraft:diamond"), count: 4))
        XCTAssertEqual(project.recipes.first?.pattern, [" I ", " I ", " S "])
        XCTAssertEqual(project.recipes.first?.ingredients["I"], .generated(ContentID("azure_a1b2c3_ingot")))
        XCTAssertTrue(AddOnProjectValidator.validate(project, profile: .current).isSuccessful)
    }

    func testMaterialHostileEntitySetUsesHostileArchetype() throws {
        let project = try AddOnProject.materialHostileEntitySet(
            materialName: "Azure",
            sourceItem: "minecraft:diamond",
            sourceCount: 4,
            health: 24,
            originalPrompt: "hostile entity",
            identity: testIdentity()
        )

        XCTAssertEqual(project.entities.count, 1)
        XCTAssertEqual(project.entities[0].archetype, .hostile)
        XCTAssertEqual(project.entities[0].health, 24)
        XCTAssertEqual(project.entities[0].displayName, "Azure Creature")
        let spawnEgg = try XCTUnwrap(project.items.first { $0.id.rawValue.hasSuffix("_spawn_egg") })
        XCTAssertEqual(spawnEgg.traits.entityPlacer?.entityID, project.entities[0].id)
    }

    func testMusicRecordSetIsRejectedByTheExperimentsOffStableProfile() throws {
        let project = try AddOnProject.musicRecordSet(
            title: "First Light",
            color: .cyan,
            style: .dreamy,
            originalPrompt: "A cyan dreamy music record called First Light",
            identity: testIdentity()
        )

        XCTAssertEqual(project.items.count, 1)
        let record = try XCTUnwrap(project.items.first)
        XCTAssertEqual(record.displayName, "First Light")
        XCTAssertEqual(record.traits.maximumStackSize, 1)
        XCTAssertEqual(record.traits.musicRecord?.style, .dreamy)
        XCTAssertEqual(project.recipes.count, 1)
        XCTAssertEqual(project.recipes.first?.pattern, ["DDD", "DRD", "DDD"])
        XCTAssertEqual(project.recipes.first?.ingredients["D"], .vanilla("minecraft:diamond"))
        XCTAssertEqual(project.recipes.first?.ingredients["R"], .vanilla("minecraft:redstone"))
        XCTAssertEqual(project.visualResources.first?.kind, .musicDiscPixelArt)
        let report = AddOnProjectValidator.validate(project, profile: .current)
        XCTAssertTrue(report.errors.contains { $0.code == "unsupported_item_trait" })
    }

    func testMaterialBossEntitySetHasBoundedHealthPhaseAndDeterministicIngotReward() throws {
        let project = try AddOnProject.materialBossEntitySet(
            materialName: "Azure",
            sourceItem: "minecraft:diamond",
            sourceCount: 4,
            health: 40,
            originalPrompt: "a two-phase Azure boss",
            identity: testIdentity()
        )

        let entity = try XCTUnwrap(project.entities.first)
        XCTAssertEqual(entity.archetype, .boss)
        XCTAssertEqual(entity.displayName, "Azure Boss")
        XCTAssertEqual(entity.health, 40)
        let reward = try XCTUnwrap(project.entityLootTables.first)
        XCTAssertEqual(reward.entityID, entity.id)
        XCTAssertEqual(reward.item, .generated(ContentID("azure_a1b2c3_ingot")))
        XCTAssertEqual(reward.minCount, 1)
        XCTAssertEqual(reward.maxCount, 1)
        XCTAssertTrue(project.spawnRules.isEmpty, "A boss is summoned from its egg instead of appearing as a natural spawn.")
        XCTAssertTrue(AddOnProjectValidator.validate(project, profile: .current).isSuccessful)
    }

    func testMaterialBossEntitySetRejectsHealthOutsideSupportedPhaseRange() {
        XCTAssertThrowsError(try AddOnProject.materialBossEntitySet(health: 19, originalPrompt: "boss")) {
            XCTAssertEqual($0 as? AddOnProjectError, .invalidBossHealth)
        }
        XCTAssertThrowsError(try AddOnProject.materialBossEntitySet(health: 41, originalPrompt: "boss")) {
            XCTAssertEqual($0 as? AddOnProjectError, .invalidBossHealth)
        }
    }

    func testMaterialEntitySetBossArchetypeUsesTheCompleteBossTemplate() throws {
        let project = try AddOnProject.materialEntitySet(
            materialName: "Azure",
            archetype: .boss,
            originalPrompt: "Azure boss",
            identity: testIdentity()
        )

        XCTAssertEqual(project.entities.first?.archetype, .boss)
        XCTAssertEqual(project.entities.first?.displayName, "Azure Boss")
        XCTAssertEqual(project.entities.first?.health, 40)
        XCTAssertTrue(project.spawnRules.isEmpty)
        XCTAssertEqual(project.entityLootTables.first?.item, .generated(ContentID("azure_a1b2c3_ingot")))
        XCTAssertEqual(project.entityLootTables.first?.minCount, 1)
        XCTAssertEqual(project.entityLootTables.first?.maxCount, 1)
    }

    func testMaterialEntitySetPreservesPassiveDefaultHealthAndRejectsInvalidBossOverrides() throws {
        let passive = try AddOnProject.materialEntitySet(originalPrompt: "passive", identity: testIdentity())
        XCTAssertEqual(passive.entities.first?.health, 10)

        for health in [19, 41] {
            XCTAssertThrowsError(try AddOnProject.materialEntitySet(
                health: health,
                archetype: .boss,
                originalPrompt: "boss",
                identity: testIdentity()
            )) {
                XCTAssertEqual($0 as? AddOnProjectError, .invalidBossHealth)
            }
        }
    }

    func testMaterialEntitySetLinksBodyTextureResource() throws {
        let project = try AddOnProject.materialEntitySet(
            materialName: "Azure",
            sourceItem: "minecraft:diamond",
            sourceCount: 4,
            health: 10,
            originalPrompt: "entity",
            identity: testIdentity()
        )

        let entity = try XCTUnwrap(project.entities.first)
        let texture = try XCTUnwrap(project.visualResources.first { $0.id == entity.textureResourceID })
        XCTAssertEqual(texture.kind, .entityTexture)
    }

    func testProjectValidationRejectsMissingEntityTextureResource() throws {
        let project = try AddOnProject.materialEntitySet(
            materialName: "Azure",
            sourceItem: "minecraft:diamond",
            sourceCount: 4,
            health: 10,
            originalPrompt: "entity",
            identity: testIdentity()
        )
        let textureID = try XCTUnwrap(project.entities.first?.textureResourceID)
        let invalidProject = AddOnProject(schemaVersion: project.schemaVersion, id: project.id, namespace: project.namespace, displayName: project.displayName, packUUIDs: project.packUUIDs, buildVersion: project.buildVersion, targetProfileID: project.targetProfileID, originalPrompt: project.originalPrompt, content: project.content.filter {
            if case .visualResource(let resource) = $0 { return resource.id != textureID }
            return true
        })
        XCTAssertEqual(AddOnProjectValidator.validate(invalidProject, profile: .current).errors.map(\.code), ["missing_entity_texture_resource"])
    }

    func testProjectValidationRejectsWrongKindEntityTextureResource() throws {
        let project = try AddOnProject.materialEntitySet(
            materialName: "Azure",
            sourceItem: "minecraft:diamond",
            sourceCount: 4,
            health: 10,
            originalPrompt: "entity",
            identity: testIdentity()
        )
        let textureID = try XCTUnwrap(project.entities.first?.textureResourceID)
        let invalidProject = AddOnProject(schemaVersion: project.schemaVersion, id: project.id, namespace: project.namespace, displayName: project.displayName, packUUIDs: project.packUUIDs, buildVersion: project.buildVersion, targetProfileID: project.targetProfileID, originalPrompt: project.originalPrompt, content: project.content.map {
            if case .visualResource(let resource) = $0, resource.id == textureID {
                return .visualResource(VisualResource(id: resource.id, kind: .ingotPixelArt, color: resource.color))
            }
            return $0
        })
        XCTAssertEqual(AddOnProjectValidator.validate(invalidProject, profile: .current).errors.map(\.code), ["invalid_entity_texture_resource"])
    }

    func testEntityDefinitionDecodesLegacySidecarWithoutTextureResource() throws {
        let project = try AddOnProject.materialEntitySet(
            materialName: "Azure",
            sourceItem: "minecraft:diamond",
            sourceCount: 4,
            health: 10,
            originalPrompt: "entity",
            identity: testIdentity()
        )
        let entity = try XCTUnwrap(project.entities.first)
        var payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(entity)) as? [String: Any]
        payload?.removeValue(forKey: "textureResourceID")
        let legacyData = try JSONSerialization.data(withJSONObject: payload ?? [:])
        let decoded = try JSONDecoder().decode(EntityDefinition.self, from: legacyData)
        XCTAssertEqual(decoded.textureResourceID, entity.id)
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
        XCTAssertEqual(migrated.schemaVersion, AddOnProject.currentSchemaVersion)
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

        XCTAssertEqual(project.schemaVersion, AddOnProject.currentSchemaVersion)
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

    func testV3CropSidecarMigratesPlantingAndGrowthResources() throws {
        let project = try AddOnProject.materialCropSet(
            materialName: "Azure",
            sourceItem: "minecraft:diamond",
            originalPrompt: "Azure crop",
            identity: testIdentity()
        )
        var sidecar = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as? [String: Any])
        sidecar["schemaVersion"] = 3
        var content = try XCTUnwrap(sidecar["content"] as? [[String: Any]])
        for index in content.indices {
            guard var value = content[index]["value"] as? [String: Any] else { continue }
            if content[index]["type"] as? String == "block" {
                value["seedItemID"] = nil
                value["growthStageResourceIDs"] = nil
            } else if content[index]["type"] as? String == "item",
                      var traits = value["traits"] as? [String: Any] {
                traits["blockPlacer"] = nil
                value["traits"] = traits
            } else if content[index]["type"] as? String == "visualResource" {
                value["growthStage"] = nil
                value["growthStageCount"] = nil
            }
            content[index]["value"] = value
        }
        content.removeAll { node in
            guard node["type"] as? String == "visualResource",
                  let value = node["value"] as? [String: Any] else { return false }
            return contentIDString(value["id"])?.contains("_crop_stage_") == true
        }
        sidecar["content"] = content
        var packUUIDs = try XCTUnwrap(sidecar["packUUIDs"] as? [String: Any])
        packUUIDs["behaviorScriptModule"] = nil
        sidecar["packUUIDs"] = packUUIDs

        let decoded = try JSONDecoder().decode(AddOnProject.self, from: JSONSerialization.data(withJSONObject: sidecar))
        let migrated = try decoded.migratedToCurrentSchema()
        let migratedAgain = try decoded.migratedToCurrentSchema()
        let crop = try XCTUnwrap(migrated.blocks.first)
        let seedID = try XCTUnwrap(crop.seedItemID)
        XCTAssertEqual(seedID, ContentID("azure_a1b2c3_seed"))
        XCTAssertEqual(crop.growthStageResourceIDs?.count, 8)
        XCTAssertEqual(migrated.items.first(where: { $0.id == seedID })?.traits.blockPlacer?.blockID, crop.id)
        XCTAssertEqual(migrated.visualResources.filter { $0.growthStage != nil }.count, 8)
        XCTAssertTrue(AddOnProjectValidator.validate(migrated, profile: .current).isSuccessful)
        XCTAssertTrue(crop.growthStageResourceIDs?.allSatisfy { id in migrated.visualResources.contains { $0.id == id } } == true)
        XCTAssertNotNil(migrated.packUUIDs.behaviorScriptModule)
        XCTAssertEqual(migrated.packUUIDs.behaviorScriptModule, migratedAgain.packUUIDs.behaviorScriptModule)
    }

    func testV3CropMigrationRecoversUniqueSeedRecipeAndVisualLink() throws {
        let project = try AddOnProject.materialCropSet(
            materialName: "Azure",
            sourceItem: "minecraft:diamond",
            originalPrompt: "Azure crop",
            identity: testIdentity()
        )
        var sidecar = try legacyV3Sidecar(from: project)
        var content = try XCTUnwrap(sidecar["content"] as? [[String: Any]])
        let legacySeedID = "turnip_kernel"
        for index in content.indices {
            guard var value = content[index]["value"] as? [String: Any] else { continue }
            if content[index]["type"] as? String == "item",
               contentIDString(value["id"]) == "azure_a1b2c3_seed" {
                value["id"] = replacingContentID(value["id"], with: legacySeedID)
                value["visualResourceID"] = replacingContentID(value["visualResourceID"], with: legacySeedID)
            } else if content[index]["type"] as? String == "shapelessRecipe",
                      var result = value["result"] as? [String: Any],
                      var resultItem = result["item"] as? [String: Any],
                      contentIDString(resultItem["value"]) == "azure_a1b2c3_seed" {
                resultItem["value"] = replacingContentID(resultItem["value"], with: legacySeedID)
                result["item"] = resultItem
                value["result"] = result
            } else if content[index]["type"] as? String == "visualResource",
                      contentIDString(value["id"]) == "azure_a1b2c3_seed" {
                value["id"] = replacingContentID(value["id"], with: legacySeedID)
            }
            content[index]["value"] = value
        }
        sidecar["content"] = content

        let legacy = try decodeProject(sidecar)
        let migrated = try legacy.migratedToCurrentSchema()

        XCTAssertEqual(migrated.blocks.first?.seedItemID, ContentID(legacySeedID))
        XCTAssertEqual(migrated.items.first(where: { $0.id == ContentID(legacySeedID) })?.traits.blockPlacer?.blockID, migrated.blocks.first?.id)
        XCTAssertTrue(AddOnProjectValidator.validate(migrated, profile: .current).isSuccessful)
    }

    func testV3CropMigrationLeavesSeedUnsetWhenRecipeAndVisualEvidenceIsAmbiguous() throws {
        let project = try AddOnProject.materialCropSet(
            materialName: "Azure",
            sourceItem: "minecraft:diamond",
            originalPrompt: "Azure crop",
            identity: testIdentity()
        )
        var sidecar = try legacyV3Sidecar(from: project)
        var content = try XCTUnwrap(sidecar["content"] as? [[String: Any]])
        let firstSeedID = "turnip_kernel"
        for index in content.indices {
            guard var value = content[index]["value"] as? [String: Any] else { continue }
            if content[index]["type"] as? String == "item",
               contentIDString(value["id"]) == "azure_a1b2c3_seed" {
                value["id"] = replacingContentID(value["id"], with: firstSeedID)
                value["visualResourceID"] = replacingContentID(value["visualResourceID"], with: firstSeedID)
            } else if content[index]["type"] as? String == "shapelessRecipe",
                      var result = value["result"] as? [String: Any],
                      var resultItem = result["item"] as? [String: Any],
                      contentIDString(resultItem["value"]) == "azure_a1b2c3_seed" {
                resultItem["value"] = replacingContentID(resultItem["value"], with: firstSeedID)
                result["item"] = resultItem
                value["result"] = result
            } else if content[index]["type"] as? String == "visualResource",
                      contentIDString(value["id"]) == "azure_a1b2c3_seed" {
                value["id"] = replacingContentID(value["id"], with: firstSeedID)
            }
            content[index]["value"] = value
        }
        sidecar["content"] = content

        let secondSeedID = ContentID("turnip_kernel_2")
        let secondSeed = ItemDefinition(
            id: secondSeedID,
            displayName: "Turnip Kernels II",
            menuCategory: .items,
            menuGroup: nil,
            traits: ItemTraits(),
            visualResourceID: secondSeedID
        )
        let secondVisual = VisualResource(id: secondSeedID, kind: .seedPixelArt, color: .blue)
        let secondRecipe = ShapelessRecipeDefinition(
            id: ContentID("turnip_seed_recipe_2"),
            tags: ["crafting_table"],
            ingredients: [.vanilla("minecraft:emerald")],
            result: RecipeResult(item: .generated(secondSeedID), count: 1),
            unlock: [.vanilla("minecraft:emerald")]
        )
        try appendContentNode(.item(secondSeed), to: &sidecar)
        try appendContentNode(.visualResource(secondVisual), to: &sidecar)
        try appendContentNode(.shapelessRecipe(secondRecipe), to: &sidecar)

        let migrated = try decodeProject(sidecar).migratedToCurrentSchema()

        XCTAssertNil(migrated.blocks.first?.seedItemID)
    }

    func testV3CropMigrationDoesNotReplaceAnExistingTerrainVisualWhenAllocatingStages() throws {
        let project = try AddOnProject.materialCropSet(
            materialName: "Azure",
            sourceItem: "minecraft:diamond",
            originalPrompt: "Azure crop",
            identity: testIdentity()
        )
        var sidecar = try legacyV3Sidecar(from: project)
        let cropID = try XCTUnwrap(project.blocks.first?.id)
        let conflictingVisualID = ContentID("\(cropID.rawValue)_stage_1")
        var content = try XCTUnwrap(sidecar["content"] as? [[String: Any]])
        let conflictingVisual = VisualResource(id: conflictingVisualID, kind: .blockTerrain, color: .blue)
        let encodedNode = try JSONEncoder().encode(AddOnContentNode.visualResource(conflictingVisual))
        content.append(try XCTUnwrap(JSONSerialization.jsonObject(with: encodedNode) as? [String: Any]))
        sidecar["content"] = content
        let otherBlock = BlockDefinition(
            id: ContentID("ordinary_block"),
            displayName: "Ordinary block",
            destroyTime: 1,
            mapColor: "#5CDBD5",
            terrainResourceID: conflictingVisualID
        )
        try appendContentNode(.block(otherBlock), to: &sidecar)

        let migrated = try decodeProject(sidecar).migratedToCurrentSchema()

        XCTAssertNotEqual(migrated.blocks.first?.growthStageResourceIDs?[1], conflictingVisualID)
        XCTAssertEqual(migrated.blocks.first(where: { $0.id == otherBlock.id })?.terrainResourceID, conflictingVisualID)
        XCTAssertEqual(migrated.visualResources.first(where: { $0.id == conflictingVisualID })?.kind, .blockTerrain)
    }

    func testMaterialCropSetDerivesStableScriptModuleUUIDAndPreservesSuppliedValue() throws {
        let identity = testIdentity()
        let first = try AddOnProject.materialCropSet(originalPrompt: "crop", identity: identity)
        let second = try AddOnProject.materialCropSet(originalPrompt: "crop", identity: identity)

        XCTAssertEqual(first.packUUIDs.behaviorScriptModule, second.packUUIDs.behaviorScriptModule)
        XCTAssertNotNil(first.packUUIDs.behaviorScriptModule)

        let suppliedUUID = UUID(uuidString: "20000000-0000-4000-8000-000000000099")!
        let identityWithScriptUUID = AddOnProjectIdentity(
            projectID: identity.projectID,
            namespace: identity.namespace,
            contentSuffix: identity.contentSuffix,
            packUUIDs: PackUUIDs(
                behaviorHeader: identity.packUUIDs.behaviorHeader,
                behaviorModule: identity.packUUIDs.behaviorModule,
                resourceHeader: identity.packUUIDs.resourceHeader,
                resourceModule: identity.packUUIDs.resourceModule,
                behaviorScriptModule: suppliedUUID
            )
        )
        let supplied = try AddOnProject.materialCropSet(originalPrompt: "crop", identity: identityWithScriptUUID)
        XCTAssertEqual(supplied.packUUIDs.behaviorScriptModule, suppliedUUID)

        var legacySidecar = try legacyV3Sidecar(from: first)
        var legacyPackUUIDs = try XCTUnwrap(legacySidecar["packUUIDs"] as? [String: Any])
        legacyPackUUIDs["behaviorScriptModule"] = suppliedUUID.uuidString
        legacySidecar["packUUIDs"] = legacyPackUUIDs
        let migratedWithExplicitUUID = try decodeProject(legacySidecar).migratedToCurrentSchema()
        XCTAssertEqual(migratedWithExplicitUUID.packUUIDs.behaviorScriptModule, suppliedUUID)
    }

    func testLegacyCropMigrationPreservesInvalidStageCountsForValidation() throws {
        let project = try AddOnProject.materialCropSet(
            materialName: "Azure",
            sourceItem: "minecraft:diamond",
            originalPrompt: "Azure crop",
            identity: testIdentity()
        )
        let originalSidecar = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as? [String: Any]
        )

        for stageCount in [0, -1] {
            var sidecar = originalSidecar
            sidecar["schemaVersion"] = 3
            var content = try XCTUnwrap(sidecar["content"] as? [[String: Any]])
            for index in content.indices where content[index]["type"] as? String == "block" {
                var value = try XCTUnwrap(content[index]["value"] as? [String: Any])
                value["growthStages"] = stageCount
                value["seedItemID"] = nil
                value["growthStageResourceIDs"] = nil
                content[index]["value"] = value
            }
            sidecar["content"] = content
            var packUUIDs = try XCTUnwrap(sidecar["packUUIDs"] as? [String: Any])
            packUUIDs["behaviorScriptModule"] = nil
            sidecar["packUUIDs"] = packUUIDs

            let decoded = try JSONDecoder().decode(
                AddOnProject.self,
                from: JSONSerialization.data(withJSONObject: sidecar)
            )
            let migrated = try decoded.migratedToCurrentSchema()
            let crop = try XCTUnwrap(migrated.blocks.first)
            let report = AddOnProjectValidator.validate(migrated, profile: .current)

            XCTAssertEqual(crop.growthStages, stageCount)
            XCTAssertTrue(report.errors.contains { $0.code == "invalid_block_growth_stages" })
        }
    }

    func testOldItemTraitsDecodeWithoutBlockPlacer() throws {
        let legacyTraits = Data(#"{"handEquipped":false,"maximumStackSize":64}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(ItemTraits.self, from: legacyTraits).blockPlacer)
    }

    func testGrowingCropRequiresStableScriptModuleIdentifier() throws {
        let project = try AddOnProject.materialCropSet(
            materialName: "Azure",
            sourceItem: "minecraft:diamond",
            originalPrompt: "Azure crop",
            identity: testIdentity()
        )
        let invalidProject = AddOnProject(
            id: project.id,
            namespace: project.namespace,
            displayName: project.displayName,
            packUUIDs: PackUUIDs(
                behaviorHeader: project.packUUIDs.behaviorHeader,
                behaviorModule: project.packUUIDs.behaviorModule,
                resourceHeader: project.packUUIDs.resourceHeader,
                resourceModule: project.packUUIDs.resourceModule
            ),
            buildVersion: project.buildVersion,
            targetProfileID: project.targetProfileID,
            originalPrompt: project.originalPrompt,
            content: project.content
        )

        let report = AddOnProjectValidator.validate(invalidProject, profile: .current)

        XCTAssertEqual(report.errors.map(\.code), ["missing_crop_script_module_uuid"])
        XCTAssertEqual(report.errors.first?.path, "packUUIDs.behaviorScriptModule")
    }

    func testCropSeedMustBeUsableOnFarmland() throws {
        let project = try AddOnProject.materialCropSet(
            originalPrompt: "crop",
            identity: testIdentity()
        )
        let crop = try XCTUnwrap(project.blocks.first)
        let seed = try XCTUnwrap(project.items.first { $0.id == crop.seedItemID })
        let invalidSeed = ItemDefinition(
            id: seed.id,
            displayName: seed.displayName,
            menuCategory: seed.menuCategory,
            menuGroup: seed.menuGroup,
            traits: ItemTraits(blockPlacer: BlockPlacerTrait(blockID: crop.id, useOn: ["minecraft:dirt"])),
            visualResourceID: seed.visualResourceID
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
                if case .item(let item) = node, item.id == seed.id { return .item(invalidSeed) }
                return node
            }
        )

        let report = AddOnProjectValidator.validate(invalidProject, profile: .current)

        XCTAssertTrue(report.errors.contains { $0.code == "crop_seed_requires_farmland" })

        let ordinaryBlockProject = try AddOnProject.materialBlockSet(
            materialName: "Azure",
            sourceItem: "minecraft:diamond",
            originalPrompt: "ordinary block",
            identity: testIdentity()
        )
        let ordinaryBlock = try XCTUnwrap(ordinaryBlockProject.blocks.first)
        let ordinaryItem = try XCTUnwrap(ordinaryBlockProject.items.first { $0.id == ordinaryBlock.id })
        let ordinaryPlacer = ItemDefinition(
            id: ordinaryItem.id,
            displayName: ordinaryItem.displayName,
            menuCategory: ordinaryItem.menuCategory,
            menuGroup: ordinaryItem.menuGroup,
            traits: ItemTraits(blockPlacer: BlockPlacerTrait(blockID: ordinaryBlock.id, useOn: ["minecraft:dirt"])),
            visualResourceID: ordinaryItem.visualResourceID
        )
        let ordinaryProjectWithPlacer = AddOnProject(
            id: ordinaryBlockProject.id,
            namespace: ordinaryBlockProject.namespace,
            displayName: ordinaryBlockProject.displayName,
            packUUIDs: ordinaryBlockProject.packUUIDs,
            buildVersion: ordinaryBlockProject.buildVersion,
            targetProfileID: ordinaryBlockProject.targetProfileID,
            originalPrompt: ordinaryBlockProject.originalPrompt,
            content: ordinaryBlockProject.content.map { node in
                if case .item(let item) = node, item.id == ordinaryItem.id { return .item(ordinaryPlacer) }
                return node
            }
        )
        XCTAssertTrue(AddOnProjectValidator.validate(ordinaryProjectWithPlacer, profile: .current).isSuccessful)
        XCTAssertEqual(ordinaryProjectWithPlacer.items.first(where: { $0.id == ordinaryItem.id })?.traits.blockPlacer?.useOn, ["minecraft:dirt"])
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
            Set<String>(report.errors.map(\.code)),
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
            Set<String>(report.errors.map(\.code)),
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
            Set<String>(report.errors.map(\.code)),
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
                maximumStackSize: 65,
                enchantment: EnchantmentTrait(value: -1)
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
            Set<String>(report.errors.map(\.code)),
            ["duplicate_pack_uuid", "invalid_attack_bonus", "invalid_durability", "invalid_stack_size", "invalid_enchantment"]
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
            Set<String>(report.errors.map(\.code)),
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
            blockFormatVersion: BedrockContentProfile.current.blockFormatVersion,
            entityFormatVersion: BedrockContentProfile.current.entityFormatVersion,
            spawnRuleFormatVersion: BedrockContentProfile.current.spawnRuleFormatVersion,
            clientEntityFormatVersion: BedrockContentProfile.current.clientEntityFormatVersion,
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
            Set<String>(report.errors.map(\.code)),
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

    private func legacyV3Sidecar(from project: AddOnProject) throws -> [String: Any] {
        var sidecar = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as? [String: Any])
        sidecar["schemaVersion"] = 3
        var content = try XCTUnwrap(sidecar["content"] as? [[String: Any]])
        for index in content.indices {
            guard var value = content[index]["value"] as? [String: Any] else { continue }
            if content[index]["type"] as? String == "block" {
                value["seedItemID"] = nil
                value["growthStageResourceIDs"] = nil
            } else if content[index]["type"] as? String == "item",
                      var traits = value["traits"] as? [String: Any] {
                traits["blockPlacer"] = nil
                value["traits"] = traits
            } else if content[index]["type"] as? String == "visualResource" {
                value["growthStage"] = nil
                value["growthStageCount"] = nil
            }
            content[index]["value"] = value
        }
        content.removeAll { node in
            guard node["type"] as? String == "visualResource",
                  let value = node["value"] as? [String: Any] else { return false }
            return contentIDString(value["id"])?.contains("_crop_stage_") == true
        }
        sidecar["content"] = content
        var packUUIDs = try XCTUnwrap(sidecar["packUUIDs"] as? [String: Any])
        packUUIDs["behaviorScriptModule"] = nil
        sidecar["packUUIDs"] = packUUIDs
        return sidecar
    }

    private func decodeProject(_ sidecar: [String: Any]) throws -> AddOnProject {
        try JSONDecoder().decode(AddOnProject.self, from: JSONSerialization.data(withJSONObject: sidecar))
    }

    private func appendContentNode(_ node: AddOnContentNode, to sidecar: inout [String: Any]) throws {
        var content = try XCTUnwrap(sidecar["content"] as? [[String: Any]])
        let encoded = try JSONEncoder().encode(node)
        content.append(try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any]))
        sidecar["content"] = content
    }

    private func contentIDString(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        return (value as? [String: Any])?["rawValue"] as? String
    }

    private func replacingContentID(_ existing: Any?, with rawValue: String) -> Any {
        guard var object = existing as? [String: Any] else { return rawValue }
        object["rawValue"] = rawValue
        return object
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
