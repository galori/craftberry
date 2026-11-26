import Foundation
import XCTest
#if canImport(CraftberryCore)
@testable import CraftberryCore
#else
@testable import Craftberry
#endif

final class BedrockCompilerTests: XCTestCase {
    func testCompilerRejectsMusicRecordsInTheExperimentsOffStableProfile() throws {
        let project = try AddOnProject.musicRecordSet(
            title: "First Light",
            color: .cyan,
            style: .dreamy,
            originalPrompt: "First Light record",
            identity: makeIdentity()
        )
        let outputDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        XCTAssertThrowsError(
            try BedrockAddOnCompiler().compile(
                project: project,
                profile: .current,
                outputDirectory: outputDirectory
            )
        ) { error in
            guard case BedrockCompilationError.invalidProject(let report) = error else {
                return XCTFail("Expected the stable profile to reject custom music records, got \(error)")
            }
            XCTAssertTrue(report.errors.contains { $0.code == "unsupported_item_trait" })
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    func testMusicRecordAudioRendererCreatesDistinctEightSecondPCMTracks() {
        let tracks = MusicRecordStyle.allCases.map(MusicRecordAudioRenderer.render(style:))

        XCTAssertEqual(MusicRecordAudioRenderer.duration, 8)
        XCTAssertEqual(tracks.count, 4)
        XCTAssertEqual(Set(tracks).count, tracks.count, "Each supported style should synthesize a distinct original track.")
        for track in tracks {
            XCTAssertEqual(String(decoding: track.prefix(4), as: UTF8.self), "RIFF")
            XCTAssertEqual(String(decoding: track[8..<12], as: UTF8.self), "WAVE")
            XCTAssertEqual(track.count, 44 + Int(MusicRecordAudioRenderer.sampleRate) * 2 * 8)
        }

        let plainID = ContentID("dawn")
        let suffixedID = ContentID("dawn_disc")
        XCTAssertEqual(MusicRecordAudioRenderer.trackIdentifier(for: plainID), "dawn")
        XCTAssertEqual(MusicRecordAudioRenderer.trackIdentifier(for: suffixedID), "dawn_disc")
        XCTAssertNotEqual(
            MusicRecordAudioRenderer.soundEventIdentifier(for: plainID),
            MusicRecordAudioRenderer.soundEventIdentifier(for: suffixedID)
        )
    }

    func testCompilerEmitsImportedInventoryPixelsForSelectedItem() throws {
        let base = try AddOnProject.materialSwordSet(
            materialName: "Azure",
            sourceItem: "minecraft:diamond",
            sourceCount: 4,
            originalPrompt: "Azure sword",
            identity: makeIdentity()
        )
        var importedPixels = Data(capacity: 32 * 32 * 4)
        for index in 0..<(32 * 32) {
            importedPixels.append(contentsOf: [
                UInt8(index % 256),
                UInt8((index * 2) % 256),
                UInt8((index * 5) % 256),
                255
            ])
        }
        let project = AddOnProject(
            id: base.id,
            namespace: base.namespace,
            displayName: base.displayName,
            shortDescription: base.shortDescription,
            packUUIDs: base.packUUIDs,
            buildVersion: base.buildVersion,
            targetProfileID: base.targetProfileID,
            originalPrompt: base.originalPrompt,
            content: base.content.map { node in
                guard case .visualResource(let visual) = node, visual.kind == .swordPixelArt else { return node }
                return .visualResource(VisualResource(
                    id: visual.id,
                    kind: visual.kind,
                    color: visual.color,
                    customPixels: importedPixels
                ))
            }
        )
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try BedrockAddOnCompiler().compile(project: project, profile: .current, outputDirectory: directory)
        let outer = try ZipArchiveReader.readEntries(at: result.artifact.url)
        let resourcePack = try pack(named: "azure_a1b2c3_ingot_resources.mcpack", in: outer)
        let texture = try XCTUnwrap(resourcePack.first { $0.path == "textures/items/azure_a1b2c3_sword.png" })
        let visual = try XCTUnwrap(project.visualResources.first { $0.kind == .swordPixelArt })

        XCTAssertEqual(texture.data, PixelArtTextureRenderer.render(visual))
    }

    func testCompilerKeepsPreviousSidecarWhenArchivePublicationFails() throws {
        let project = try AddOnProject.sword(
            displayName: "Azure Sword",
            originalPrompt: "A blue diamond sword",
            identity: makeIdentity()
        )
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let compiler = BedrockAddOnCompiler()
        let initialResult = try compiler.compile(project: project, profile: .current, outputDirectory: directory)
        let previousSidecar = try Data(contentsOf: initialResult.artifact.projectSidecarURL)

        let nextVersion = project.buildVersion.nextPatch()
        let nextBuildDirectory = initialResult.artifact.url
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: nextVersion.components.map(String.init).joined(separator: "."), directoryHint: .isDirectory)
        let blockedArchiveURL = nextBuildDirectory.appending(path: initialResult.artifact.fileName)
        try FileManager.default.createDirectory(at: blockedArchiveURL, withIntermediateDirectories: true)
        let revised = AddOnProject(
            id: project.id,
            namespace: project.namespace,
            displayName: project.displayName,
            shortDescription: project.shortDescription,
            packUUIDs: project.packUUIDs,
            buildVersion: nextVersion,
            targetProfileID: project.targetProfileID,
            originalPrompt: "A revised blue diamond sword",
            content: project.content
        )

        XCTAssertThrowsError(try compiler.compile(project: revised, profile: .current, outputDirectory: directory))
        XCTAssertEqual(try Data(contentsOf: initialResult.artifact.projectSidecarURL), previousSidecar)
    }

    func testCompilerRestoresPreviousArchiveWhenSidecarPublicationFails() throws {
        let project = try makeProject()
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let compiler = BedrockAddOnCompiler()
        let initialResult = try compiler.compile(project: project, profile: .current, outputDirectory: directory)
        let previousArchive = try Data(contentsOf: initialResult.artifact.url)
        let changedPixels = Data(repeating: 0xA5, count: 32 * 32 * 4)
        let changedProject = AddOnProject(
            id: project.id,
            namespace: project.namespace,
            displayName: project.displayName,
            shortDescription: project.shortDescription,
            packUUIDs: project.packUUIDs,
            buildVersion: project.buildVersion,
            targetProfileID: project.targetProfileID,
            originalPrompt: project.originalPrompt,
            content: project.content.map { node in
                guard case .visualResource(let resource) = node, resource.kind == .swordPixelArt else { return node }
                return .visualResource(VisualResource(
                    id: resource.id,
                    kind: resource.kind,
                    color: resource.color,
                    customPixels: changedPixels
                ))
            }
        )
        let expectedDirectory = directory.appending(path: "expected", directoryHint: .isDirectory)
        let expectedResult = try compiler.compile(
            project: changedProject,
            profile: .current,
            outputDirectory: expectedDirectory
        )
        XCTAssertNotEqual(try Data(contentsOf: expectedResult.artifact.url), previousArchive)

        try FileManager.default.removeItem(at: initialResult.artifact.projectSidecarURL)
        try FileManager.default.createDirectory(
            at: initialResult.artifact.projectSidecarURL,
            withIntermediateDirectories: true
        )
        XCTAssertThrowsError(
            try compiler.compile(project: changedProject, profile: .current, outputDirectory: directory)
        )
        XCTAssertEqual(try Data(contentsOf: initialResult.artifact.url), previousArchive)
    }

    func testCompilerEmitsMaterialBrewingSetRecipesAndTextures() throws {
        let project = try AddOnProject.materialBrewingSet(materialName: "Azure", sourceItem: "minecraft:diamond", sourceCount: 4, originalPrompt: "brewing", identity: makeIdentity())
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try BedrockAddOnCompiler().compile(project: project, profile: .current, outputDirectory: directory)
        let outer = try ZipArchiveReader.readEntries(at: result.artifact.url)
        let behavior = try pack(named: "azure_a1b2c3_ingot_behavior.mcpack", in: outer)
        let resources = try pack(named: "azure_a1b2c3_ingot_resources.mcpack", in: outer)

        XCTAssertTrue(behavior.contains { $0.path == "items/azure_a1b2c3_ingot.json" })
        XCTAssertTrue(behavior.contains { $0.path == "items/azure_a1b2c3_elixir.json" })
        XCTAssertTrue(behavior.contains { $0.path == "recipes/azure_a1b2c3_ingot_recipe.json" })
        XCTAssertTrue(behavior.contains { $0.path == "recipes/azure_a1b2c3_elixir_brewing_mix_recipe.json" })
        XCTAssertTrue(behavior.contains { $0.path == "recipes/azure_a1b2c3_elixir_brewing_container_recipe.json" })

        // Pinned to vanilla brewing samples: brewing_mix and brewing_container share tags/input/reagent/output shape.
        let mix = try json(named: "recipes/azure_a1b2c3_elixir_brewing_mix_recipe.json", in: behavior)
        let mixRecipe = try XCTUnwrap(mix["minecraft:recipe_brewing_mix"] as? [String: Any])
        XCTAssertEqual(mixRecipe["tags"] as? [String], ["brewing_stand"])
        XCTAssertEqual(mixRecipe["input"] as? String, "minecraft:potion")
        XCTAssertEqual(mixRecipe["reagent"] as? String, "craftberry:azure_a1b2c3_ingot")
        XCTAssertEqual(mixRecipe["output"] as? String, "craftberry:azure_a1b2c3_elixir")
        let mixDesc = try XCTUnwrap(mixRecipe["description"] as? [String: Any])
        XCTAssertEqual(mixDesc["identifier"] as? String, "craftberry:azure_a1b2c3_elixir_brewing_mix_recipe")

        let container = try json(named: "recipes/azure_a1b2c3_elixir_brewing_container_recipe.json", in: behavior)
        let containerRecipe = try XCTUnwrap(container["minecraft:recipe_brewing_container"] as? [String: Any])
        XCTAssertEqual(containerRecipe["tags"] as? [String], ["brewing_stand"])
        XCTAssertEqual(containerRecipe["input"] as? String, "craftberry:azure_a1b2c3_elixir")
        XCTAssertEqual(containerRecipe["reagent"] as? String, "minecraft:gunpowder")
        XCTAssertEqual(containerRecipe["output"] as? String, "minecraft:splash_potion")
        let containerDesc = try XCTUnwrap(containerRecipe["description"] as? [String: Any])
        XCTAssertEqual(containerDesc["identifier"] as? String, "craftberry:azure_a1b2c3_elixir_brewing_container_recipe")

        XCTAssertEqual(mix["format_version"] as? String, "1.20.10")
        XCTAssertEqual(container["format_version"] as? String, "1.20.10")

        let textureMap = try json(named: "textures/item_texture.json", in: resources)
        let textureData = try XCTUnwrap(textureMap["texture_data"] as? [String: Any])
        XCTAssertNotNil(textureData["azure_a1b2c3_ingot"])
        XCTAssertNotNil(textureData["azure_a1b2c3_elixir"])
    }


    func testCompilerEmitsMaterialSmithingSetRecipesAndTextures() throws {
        let project = try AddOnProject.materialSmithingSet(materialName: "Azure", sourceItem: "minecraft:diamond", sourceCount: 4, originalPrompt: "smithing", identity: makeIdentity())
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try BedrockAddOnCompiler().compile(project: project, profile: .current, outputDirectory: directory)
        let outer = try ZipArchiveReader.readEntries(at: result.artifact.url)
        let behavior = try pack(named: "azure_a1b2c3_ingot_behavior.mcpack", in: outer)
        let resources = try pack(named: "azure_a1b2c3_ingot_resources.mcpack", in: outer)

        XCTAssertTrue(behavior.contains { $0.path == "items/azure_a1b2c3_ingot.json" })
        XCTAssertTrue(behavior.contains { $0.path == "items/azure_a1b2c3_sword.json" })
        XCTAssertTrue(behavior.contains { $0.path == "recipes/azure_a1b2c3_ingot_recipe.json" })
        XCTAssertTrue(behavior.contains { $0.path == "recipes/azure_a1b2c3_sword_smithing_recipe.json" })
        XCTAssertTrue(behavior.contains { $0.path == "recipes/azure_a1b2c3_trim_recipe.json" })

        // Pinned to vanilla smithing samples: transform has template/base/addition/result; trim has template/base/addition with tags.
        let transform = try json(named: "recipes/azure_a1b2c3_sword_smithing_recipe.json", in: behavior)
        let transformRecipe = try XCTUnwrap(transform["minecraft:recipe_smithing_transform"] as? [String: Any])
        XCTAssertEqual(transformRecipe["tags"] as? [String], ["smithing_table"])
        XCTAssertEqual(transformRecipe["template"] as? String, "minecraft:netherite_upgrade_smithing_template")
        XCTAssertEqual(transformRecipe["base"] as? String, "minecraft:diamond_sword")
        XCTAssertEqual(transformRecipe["addition"] as? String, "craftberry:azure_a1b2c3_ingot")
        XCTAssertEqual(transformRecipe["result"] as? String, "craftberry:azure_a1b2c3_sword")
        let transformDesc = try XCTUnwrap(transformRecipe["description"] as? [String: Any])
        XCTAssertEqual(transformDesc["identifier"] as? String, "craftberry:azure_a1b2c3_sword_smithing_recipe")

        let trim = try json(named: "recipes/azure_a1b2c3_trim_recipe.json", in: behavior)
        let trimRecipe = try XCTUnwrap(trim["minecraft:recipe_smithing_trim"] as? [String: Any])
        XCTAssertEqual(trimRecipe["tags"] as? [String], ["smithing_table"])
        XCTAssertEqual(trimRecipe["template"] as? String, "minecraft:ward_armor_trim_smithing_template")
        XCTAssertEqual((trimRecipe["base"] as? [String: String])?["tag"], "minecraft:trimmable_armors")
        XCTAssertEqual(trimRecipe["addition"] as? String, "craftberry:azure_a1b2c3_ingot")
        let trimDesc = try XCTUnwrap(trimRecipe["description"] as? [String: Any])
        XCTAssertEqual(trimDesc["identifier"] as? String, "craftberry:azure_a1b2c3_trim_recipe")

        XCTAssertEqual(transform["format_version"] as? String, "1.20.10")
        XCTAssertEqual(trim["format_version"] as? String, "1.20.10")

        let textureMap = try json(named: "textures/item_texture.json", in: resources)
        let textureData = try XCTUnwrap(textureMap["texture_data"] as? [String: Any])
        XCTAssertNotNil(textureData["azure_a1b2c3_ingot"])
        XCTAssertNotNil(textureData["azure_a1b2c3_sword"])
    }

    func testCompilerEmitsMaterialWeaponSetItemsRecipesTexturesAndLocalization() throws {
        let project = try AddOnProject.materialWeaponSet(materialName: "Azure", sourceItem: "minecraft:diamond", sourceCount: 4, originalPrompt: "weapons", identity: makeIdentity())
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try BedrockAddOnCompiler().compile(project: project, profile: .current, outputDirectory: directory)
        let outer = try ZipArchiveReader.readEntries(at: result.artifact.url)
        let behavior = try pack(named: "azure_a1b2c3_ingot_behavior.mcpack", in: outer)
        let resources = try pack(named: "azure_a1b2c3_ingot_resources.mcpack", in: outer)

        XCTAssertTrue(behavior.contains { $0.path == "items/azure_a1b2c3_dagger.json" })
        XCTAssertTrue(behavior.contains { $0.path == "items/azure_a1b2c3_spear.json" })
        XCTAssertTrue(behavior.contains { $0.path == "items/azure_a1b2c3_hammer.json" })

        let spearItem = try json(named: "items/azure_a1b2c3_spear.json", in: behavior)
        let spearBody = try XCTUnwrap(spearItem["minecraft:item"] as? [String: Any])
        let spearComponents = try XCTUnwrap(spearBody["components"] as? [String: Any])
        // Non-armor items keep their explicit stack size (only armor-slot
        // items omit it for the pre-1.26.30 wearable interaction).
        XCTAssertEqual(spearComponents["minecraft:max_stack_size"] as? Int, 1)

        let spearRecipe = try json(named: "recipes/azure_a1b2c3_spear_recipe.json", in: behavior)
        let shapedRecipe = try XCTUnwrap(spearRecipe["minecraft:recipe_shaped"] as? [String: Any])
        XCTAssertEqual(shapedRecipe["pattern"] as? [String], ["  I", " S ", "S  "])
        XCTAssertEqual((shapedRecipe["result"] as? [String: Any])?["item"] as? String, "craftberry:azure_a1b2c3_spear")
        XCTAssertEqual(shapedRecipe["unlock"] as? [[String: String]], [["item": "craftberry:azure_a1b2c3_ingot"]])

        let textureMap = try json(named: "textures/item_texture.json", in: resources)
        let textureData = try XCTUnwrap(textureMap["texture_data"] as? [String: Any])
        XCTAssertEqual((textureData["azure_a1b2c3_hammer"] as? [String: String])?["textures"], "textures/items/azure_a1b2c3_hammer")
        let hammerTexture = try XCTUnwrap(resources.first { $0.path == "textures/items/azure_a1b2c3_hammer.png" })
        XCTAssertEqual(PNGInspector.dimensions(of: hammerTexture.data), .init(width: 32, height: 32))

        let localization = try XCTUnwrap(resources.first { $0.path == "texts/en_US.lang" })
        XCTAssertTrue(String(decoding: localization.data, as: UTF8.self).contains("item.craftberry:azure_a1b2c3_dagger.name=Azure Dagger\n"))
    }

    func testCompilerEmitsMaterialToolSetItemsRecipesTexturesAndLocalization() throws {
        let project = try AddOnProject.materialToolSet(materialName: "Azure", sourceItem: "minecraft:diamond", sourceCount: 4, originalPrompt: "set", identity: makeIdentity())
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try BedrockAddOnCompiler().compile(project: project, profile: .current, outputDirectory: directory)
        let outer = try ZipArchiveReader.readEntries(at: result.artifact.url)
        let behavior = try pack(named: "azure_a1b2c3_ingot_behavior.mcpack", in: outer)
        let resources = try pack(named: "azure_a1b2c3_ingot_resources.mcpack", in: outer)

        let ingotItem = try json(named: "items/azure_a1b2c3_ingot.json", in: behavior)
        let ingotBody = try XCTUnwrap(ingotItem["minecraft:item"] as? [String: Any])
        let ingotDescription = try XCTUnwrap(ingotBody["description"] as? [String: Any])
        let ingotMenuCategory = try XCTUnwrap(ingotDescription["menu_category"] as? [String: Any])
        XCTAssertEqual(ingotMenuCategory["category"] as? String, "items")
        XCTAssertNil(ingotMenuCategory["group"])

        XCTAssertTrue(behavior.contains { $0.path == "items/azure_a1b2c3_pickaxe.json" })
        XCTAssertTrue(behavior.contains { $0.path == "items/azure_a1b2c3_axe.json" })
        XCTAssertTrue(behavior.contains { $0.path == "items/azure_a1b2c3_shovel.json" })
        XCTAssertTrue(behavior.contains { $0.path == "items/azure_a1b2c3_hoe.json" })

        let pickaxeRecipe = try json(named: "recipes/azure_a1b2c3_pickaxe_recipe.json", in: behavior)
        let shapedRecipe = try XCTUnwrap(pickaxeRecipe["minecraft:recipe_shaped"] as? [String: Any])
        XCTAssertEqual(shapedRecipe["pattern"] as? [String], ["III", " S ", " S "])
        XCTAssertEqual((shapedRecipe["result"] as? [String: Any])?["item"] as? String, "craftberry:azure_a1b2c3_pickaxe")
        XCTAssertEqual(shapedRecipe["unlock"] as? [[String: String]], [["item": "craftberry:azure_a1b2c3_ingot"]])

        let textureMap = try json(named: "textures/item_texture.json", in: resources)
        let textureData = try XCTUnwrap(textureMap["texture_data"] as? [String: Any])
        XCTAssertEqual((textureData["azure_a1b2c3_hoe"] as? [String: String])?["textures"], "textures/items/azure_a1b2c3_hoe")
        let hoeTexture = try XCTUnwrap(resources.first { $0.path == "textures/items/azure_a1b2c3_hoe.png" })
        XCTAssertEqual(PNGInspector.dimensions(of: hoeTexture.data), .init(width: 32, height: 32))

        let localization = try XCTUnwrap(resources.first { $0.path == "texts/en_US.lang" })
        XCTAssertTrue(String(decoding: localization.data, as: UTF8.self).contains("item.craftberry:azure_a1b2c3_pickaxe.name=Azure Pickaxe\n"))
    }

    func testCompilerEmitsMaterialArmorSetItemsAttachablesLayersAndLocalization() throws {
        let project = try AddOnProject.materialArmorSet(materialName: "Azure", sourceItem: "minecraft:diamond", sourceCount: 4, originalPrompt: "armor", identity: makeIdentity())
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try BedrockAddOnCompiler().compile(project: project, profile: .current, outputDirectory: directory)
        let outer = try ZipArchiveReader.readEntries(at: result.artifact.url)
        let behavior = try pack(named: "azure_a1b2c3_ingot_behavior.mcpack", in: outer)
        let resources = try pack(named: "azure_a1b2c3_ingot_resources.mcpack", in: outer)

        XCTAssertTrue(behavior.contains { $0.path == "items/azure_a1b2c3_helmet.json" })
        XCTAssertTrue(behavior.contains { $0.path == "items/azure_a1b2c3_chestplate.json" })
        XCTAssertTrue(behavior.contains { $0.path == "items/azure_a1b2c3_leggings.json" })
        XCTAssertTrue(behavior.contains { $0.path == "items/azure_a1b2c3_boots.json" })

        let helmetItem = try json(named: "items/azure_a1b2c3_helmet.json", in: behavior)
        let helmetBody = try XCTUnwrap(helmetItem["minecraft:item"] as? [String: Any])
        let helmetComponents = try XCTUnwrap(helmetBody["components"] as? [String: Any])
        let wearable = try XCTUnwrap(helmetComponents["minecraft:wearable"] as? [String: Any])
        XCTAssertEqual(wearable["slot"] as? String, "slot.armor.head")
        XCTAssertEqual(wearable["protection"] as? Int, 2)
        // Armor pin item format 1.26.60, exactly as the working Bedrock
        // Wiki custom-armor reference: older items silently refuse to
        // equip despite a clean Content Log.
        XCTAssertEqual(helmetItem["format_version"] as? String, "1.26.60")
        // No explicit hand_equipped (the wiki reference omits it).
        XCTAssertNil(helmetComponents["minecraft:hand_equipped"])
        // Explicit stack size 1 alongside wearable, exactly as the
        // working Bedrock Wiki custom-armor reference emits it.
        XCTAssertEqual(helmetComponents["minecraft:max_stack_size"] as? Int, 1)
        let tags = try XCTUnwrap(helmetComponents["minecraft:tags"] as? [String: Any])
        XCTAssertEqual(tags["tags"] as? [String], ["minecraft:is_armor"])

        let bootsRecipe = try json(named: "recipes/azure_a1b2c3_boots_recipe.json", in: behavior)
        let shapedRecipe = try XCTUnwrap(bootsRecipe["minecraft:recipe_shaped"] as? [String: Any])
        XCTAssertEqual(shapedRecipe["pattern"] as? [String], ["I I", "I I"])
        XCTAssertEqual((shapedRecipe["result"] as? [String: Any])?["item"] as? String, "craftberry:azure_a1b2c3_boots")
        XCTAssertEqual(shapedRecipe["unlock"] as? [[String: String]], [["item": "craftberry:azure_a1b2c3_ingot"]])

        // Pinned to Mojang/bedrock-samples resource_pack/attachables/diamond_helmet.json (921fafb0…): built-in
        // vanilla material, geometry, and render controller identifiers; only the texture is ours.
        let attachable = try json(named: "attachables/azure_a1b2c3_helmet.json", in: resources)
        XCTAssertEqual(attachable["format_version"] as? String, "1.8.0")
        let attachableBody = try XCTUnwrap(attachable["minecraft:attachable"] as? [String: Any])
        let description = try XCTUnwrap(attachableBody["description"] as? [String: Any])
        XCTAssertEqual(description["identifier"] as? String, "craftberry:azure_a1b2c3_helmet")
        XCTAssertEqual(description["materials"] as? [String: String], ["default": "armor", "enchanted": "armor_enchanted"])
        XCTAssertEqual((description["textures"] as? [String: String])?["default"], "textures/models/armor/azure_a1b2c3_armor_layer_1")
        XCTAssertEqual((description["textures"] as? [String: String])?["enchanted"], "textures/misc/enchanted_actor_glint")
        XCTAssertEqual(description["geometry"] as? [String: String], ["default": "geometry.humanoid.armor.helmet"])
        XCTAssertEqual((description["scripts"] as? [String: String])?["parent_setup"], "variable.helmet_layer_visible = 0.0;")
        XCTAssertEqual(description["render_controllers"] as? [String], ["controller.render.armor"])

        let leggingsAttachable = try json(named: "attachables/azure_a1b2c3_leggings.json", in: resources)
        let leggingsDescription = try XCTUnwrap((leggingsAttachable["minecraft:attachable"] as? [String: Any])?["description"] as? [String: Any])
        XCTAssertEqual((leggingsDescription["textures"] as? [String: String])?["default"], "textures/models/armor/azure_a1b2c3_armor_layer_2")

        let layerOne = try XCTUnwrap(resources.first { $0.path == "textures/models/armor/azure_a1b2c3_armor_layer_1.png" })
        XCTAssertEqual(PNGInspector.dimensions(of: layerOne.data), .init(width: 64, height: 32))
        let layerTwo = try XCTUnwrap(resources.first { $0.path == "textures/models/armor/azure_a1b2c3_armor_layer_2.png" })
        XCTAssertEqual(PNGInspector.dimensions(of: layerTwo.data), .init(width: 64, height: 32))

        // Armor layers are body textures, not inventory icons — they must not appear in item_texture.json.
        let textureMap = try json(named: "textures/item_texture.json", in: resources)
        let textureData = try XCTUnwrap(textureMap["texture_data"] as? [String: Any])
        XCTAssertNil(textureData["azure_a1b2c3_armor_layer_1"])
        XCTAssertEqual((textureData["azure_a1b2c3_helmet"] as? [String: String])?["textures"], "textures/items/azure_a1b2c3_helmet")
        let helmetIcon = try XCTUnwrap(resources.first { $0.path == "textures/items/azure_a1b2c3_helmet.png" })
        XCTAssertEqual(PNGInspector.dimensions(of: helmetIcon.data), .init(width: 32, height: 32))

        let localization = try XCTUnwrap(resources.first { $0.path == "texts/en_US.lang" })
        XCTAssertTrue(String(decoding: localization.data, as: UTF8.self).contains("item.craftberry:azure_a1b2c3_boots.name=Azure Boots\n"))
    }

    func testCompilerEmitsMaterialSetShapelessAndShapedRecipes() throws {
        let project = try AddOnProject.materialSwordSet(materialName: "Azure", sourceItem: "minecraft:diamond", sourceCount: 4, originalPrompt: "set", identity: makeIdentity())
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = try BedrockAddOnCompiler().compile(project: project, profile: .current, outputDirectory: directory)
        let outer = try ZipArchiveReader.readEntries(at: result.artifact.url)
        let behavior = try pack(named: "azure_a1b2c3_ingot_behavior.mcpack", in: outer)
        let shapeless = try XCTUnwrap(behavior.first { $0.path == "recipes/azure_a1b2c3_ingot_recipe.json" })
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: shapeless.data) as? [String: Any])
        let recipe = try XCTUnwrap(object["minecraft:recipe_shapeless"] as? [String: Any])
        XCTAssertEqual((recipe["ingredients"] as? [[String: String]])?.count, 4)
        XCTAssertEqual((recipe["result"] as? [String: Any])?["item"] as? String, "craftberry:azure_a1b2c3_ingot")
        XCTAssertTrue(behavior.contains { $0.path == "items/azure_a1b2c3_ingot.json" })
        XCTAssertTrue(behavior.contains { $0.path == "items/azure_a1b2c3_sword.json" })
        let sword = try json(named: "items/azure_a1b2c3_sword.json", in: behavior)
        let body = try XCTUnwrap(sword["minecraft:item"] as? [String: Any])
        let components = try XCTUnwrap(body["components"] as? [String: Any])
        let enchantable = try XCTUnwrap(components["minecraft:enchantable"] as? [String: Any])
        XCTAssertEqual(enchantable["slot"] as? String, "sword")
        XCTAssertEqual(enchantable["value"] as? Int, 10)
    }
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

    func testCompilerCreatesCreativeWorldWithEmbeddedPacksAndModeMetadata() throws {
        let project = try makeProject()
        let outputDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let addOn = try BedrockAddOnCompiler().compile(
            project: project,
            profile: .current,
            outputDirectory: outputDirectory
        )
        let world = try BedrockWorldExporter().compileWorld(
            project: project,
            addOn: addOn,
            gameMode: .creative,
            outputDirectory: outputDirectory
        )
        let archive = try ZipArchiveReader.readEntries(at: world.artifact.url)

        XCTAssertEqual(world.artifact.fileName, "azure_sword_a1b2c3_creative.mcworld")
        XCTAssertTrue(archive.contains { $0.path == "level.dat" })
        let currentDatabaseManifest = try XCTUnwrap(archive.first { $0.path == "db/CURRENT" })
        let manifestName = String(decoding: currentDatabaseManifest.data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(archive.contains { $0.path == "db/\(manifestName)" })
        XCTAssertEqual(String(decoding: try XCTUnwrap(archive.first { $0.path == "levelname.txt" }).data, as: UTF8.self), "Azure Sword (Creative)")
        XCTAssertTrue(archive.contains { $0.path == "behavior_packs/azure_sword_a1b2c3_behavior/manifest.json" })
        XCTAssertTrue(archive.contains { $0.path == "resource_packs/azure_sword_a1b2c3_resources/manifest.json" })

        let behaviorRefs = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: XCTUnwrap(archive.first { $0.path == "world_behavior_packs.json" }).data
        ) as? [[String: Any]])
        XCTAssertEqual(behaviorRefs.first?["pack_id"] as? String, "20000000-0000-4000-8000-000000000001")
        XCTAssertEqual(behaviorRefs.first?["version"] as? [Int], [1, 0, 0])

        let levelData = try XCTUnwrap(archive.first { $0.path == "level.dat" }).data
        XCTAssertEqual(levelData.littleEndianUInt32(at: 0), 10)
        XCTAssertEqual(levelData.littleEndianUInt32(at: 4), UInt32(levelData.count - 8))
        XCTAssertNotNil(levelData.range(of: Data("GameType".utf8)))
        XCTAssertNotNil(levelData.range(of: Data("LevelName".utf8)))
    }

    func testCompilerCreatesSurvivalWorldWithModeSpecificName() throws {
        let project = try makeProject()
        let outputDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let addOn = try BedrockAddOnCompiler().compile(
            project: project,
            profile: .current,
            outputDirectory: outputDirectory
        )
        let world = try BedrockWorldExporter().compileWorld(
            project: project,
            addOn: addOn,
            gameMode: .survival,
            outputDirectory: outputDirectory
        )
        let archive = try ZipArchiveReader.readEntries(at: world.artifact.url)

        XCTAssertEqual(world.artifact.fileName, "azure_sword_a1b2c3_survival.mcworld")
        XCTAssertEqual(String(decoding: try XCTUnwrap(archive.first { $0.path == "levelname.txt" }).data, as: UTF8.self), "Azure Sword (Survival)")
    }

    func testWorldExportPersistsBesideOriginalBuildWhenInputIsShareSnapshot() throws {
        let project = try makeProject()
        let outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: ".scratch/tests/world-share-snapshot", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let addOn = try BedrockAddOnCompiler().compile(
            project: project,
            profile: .current,
            outputDirectory: outputDirectory
        )
        let snapshotDirectory = outputDirectory
            .appending(path: SidecarRetentionService.shareSnapshotsDirectoryName, directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)
        let snapshotURL = snapshotDirectory.appending(path: addOn.artifact.fileName)
        try FileManager.default.copyItem(at: addOn.artifact.url, to: snapshotURL)
        let snapshotArtifact = BedrockAddOnArtifact(
            url: snapshotURL,
            identifier: addOn.artifact.identifier,
            fileName: addOn.artifact.fileName,
            projectSidecarURL: addOn.artifact.projectSidecarURL
        )
        let snapshotAddOn = BedrockCompilationResult(artifact: snapshotArtifact, report: addOn.report)

        let world = try BedrockWorldExporter().compileWorld(
            project: project,
            addOn: snapshotAddOn,
            gameMode: .survival,
            outputDirectory: outputDirectory
        )
        try FileManager.default.removeItem(at: snapshotDirectory)

        XCTAssertTrue(FileManager.default.fileExists(atPath: world.artifact.url.path))
        XCTAssertEqual(world.artifact.url.deletingLastPathComponent(), addOn.artifact.url.deletingLastPathComponent())
    }

    func testCompilerPreservesProvidedWorldTemplateDatabaseAndIcon() throws {
        let project = try makeProject()
        let outputDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let addOn = try BedrockAddOnCompiler().compile(
            project: project,
            profile: .current,
            outputDirectory: outputDirectory
        )
        let templateEntries = [
            ZipArchiveEntry(path: "level.dat", data: Data([1, 2, 3])),
            ZipArchiveEntry(path: "level.dat_old", data: Data([4, 5, 6])),
            ZipArchiveEntry(path: "world_icon.jpeg", data: Data([7, 8, 9])),
            ZipArchiveEntry(path: "db/CURRENT", data: Data("MANIFEST-000002\n".utf8)),
            ZipArchiveEntry(path: "db/MANIFEST-000002", data: Data([10, 11])),
            ZipArchiveEntry(path: "db/000003.log", data: Data([12, 13, 14]))
        ]

        let world = try BedrockWorldExporter(templateEntries: templateEntries).compileWorld(
            project: project,
            addOn: addOn,
            gameMode: .creative,
            outputDirectory: outputDirectory
        )
        let archive = try ZipArchiveReader.readEntries(at: world.artifact.url)

        XCTAssertEqual(archive.first { $0.path == "level.dat" }?.data, Data([1, 2, 3]))
        XCTAssertEqual(archive.first { $0.path == "level.dat_old" }?.data, Data([4, 5, 6]))
        XCTAssertEqual(archive.first { $0.path == "world_icon.jpeg" }?.data, Data([7, 8, 9]))
        XCTAssertEqual(archive.first { $0.path == "db/CURRENT" }?.data, Data("MANIFEST-000002\n".utf8))
        XCTAssertEqual(archive.first { $0.path == "db/MANIFEST-000002" }?.data, Data([10, 11]))
        XCTAssertEqual(archive.first { $0.path == "db/000003.log" }?.data, Data([12, 13, 14]))
    }

    func testCompilerPatchesProvidedWorldTemplateMetadataWithoutReplacingLevelDB() throws {
        let project = try makeProject()
        let outputDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let addOn = try BedrockAddOnCompiler().compile(
            project: project,
            profile: .current,
            outputDirectory: outputDirectory
        )
        let world = try BedrockWorldExporter(templateEntries: try sourceWorldTemplateEntries()).compileWorld(
            project: project,
            addOn: addOn,
            gameMode: .creative,
            outputDirectory: outputDirectory
        )
        let archive = try ZipArchiveReader.readEntries(at: world.artifact.url)
        let levelData = try XCTUnwrap(archive.first { $0.path == "level.dat" }?.data)
        let gameTypeTag = Data([3, 8, 0]) + Data("GameType".utf8)
        let gameTypeOffset = try XCTUnwrap(levelData.range(of: gameTypeTag)?.upperBound)
        XCTAssertEqual(levelData.littleEndianUInt32(at: gameTypeOffset), 1)

        let levelNameTag = Data([8, 9, 0]) + Data("LevelName".utf8)
        let levelNameOffset = try XCTUnwrap(levelData.range(of: levelNameTag)?.upperBound)
        let levelNameLength = try XCTUnwrap(levelData.littleEndianUInt16(at: levelNameOffset))
        XCTAssertEqual(
            String(decoding: levelData.subdata(in: (levelNameOffset + 2)..<(levelNameOffset + 2 + Int(levelNameLength))), as: UTF8.self),
            "Azure Sword (Creative)"
        )
        for name in ["commandsEnabled", "cheatsEnabled"] {
            let tag = Data([1, UInt8(name.utf8.count), 0]) + Data(name.utf8)
            let valueOffset = try XCTUnwrap(levelData.range(of: tag)?.upperBound)
            XCTAssertEqual(levelData[valueOffset], 1, "Expected (name) to be enabled in the exported world.")
        }
        XCTAssertEqual(levelData.littleEndianUInt32(at: 4), UInt32(levelData.count - 8))
        for templateEntry in try sourceWorldTemplateEntries() where templateEntry.path.hasPrefix("db/") {
            XCTAssertEqual(
                archive.first { $0.path == templateEntry.path }?.data,
                templateEntry.data,
                "Expected the bundled LevelDB entry \(templateEntry.path) to be preserved."
            )
        }
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

    func testCompilerEmitsFoodSaturationAsANumber() throws {
        let project = try AddOnProject.materialConsumableSet(originalPrompt: "food", identity: makeIdentity())
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = try BedrockAddOnCompiler().compile(project: project, profile: .current, outputDirectory: directory)
        let outer = try ZipArchiveReader.readEntries(at: result.artifact.url)
        let behavior = try pack(named: "azure_a1b2c3_ingot_behavior.mcpack", in: outer)
        let food = try json(named: "items/azure_a1b2c3_food.json", in: behavior)
        let body = try XCTUnwrap(food["minecraft:item"] as? [String: Any])
        let components = try XCTUnwrap(body["components"] as? [String: Any])
        // saturation_modifier must be a JSON number, not a string (confirmed live:
        // a string fails the whole item file and cascades into missing-icon errors).
        let foodComponent = try XCTUnwrap(components["minecraft:food"] as? [String: Any])
        XCTAssertEqual(foodComponent["nutrition"] as? Int, 6)
        XCTAssertEqual(foodComponent["saturation_modifier"] as? Double, 0.6)
        XCTAssertNil(foodComponent["can_always_eat"])
        // The engine warns when minecraft:food has no use_duration (pinned to
        // vanilla apple values from bedrock-samples).
        let animation = try XCTUnwrap(components["minecraft:use_animation"] as? [String: Any])
        XCTAssertEqual(animation["value"] as? String, "eat")
        let modifiers = try XCTUnwrap(components["minecraft:use_modifiers"] as? [String: Any])
        XCTAssertEqual(modifiers["use_duration"] as? Double, 1.6)
        XCTAssertEqual(modifiers["movement_modifier"] as? Double, 0.35)
    }

    func testCompilerEmitsMaterialOreSetWithLootAndBlock() throws {
        let project = try AddOnProject.materialOreSet(materialName: "Azure", sourceItem: "minecraft:diamond", sourceCount: 4, originalPrompt: "ore", identity: makeIdentity())
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = try BedrockAddOnCompiler().compile(project: project, profile: .current, outputDirectory: directory)
        let outer = try ZipArchiveReader.readEntries(at: result.artifact.url)
        let behavior = try pack(named: "azure_a1b2c3_ingot_behavior.mcpack", in: outer)
        let resources = try pack(named: "azure_a1b2c3_ingot_resources.mcpack", in: outer)
        XCTAssertTrue(behavior.contains { $0.path == "blocks/azure_a1b2c3_ore.json" })
        XCTAssertTrue(behavior.contains { $0.path == "loot_tables/blocks/azure_a1b2c3_ore.json" })
        let loot = try json(named: "loot_tables/blocks/azure_a1b2c3_ore.json", in: behavior)
        let pools = try XCTUnwrap(loot["pools"] as? [[String: Any]])
        let entry = try XCTUnwrap((pools.first?["entries"] as? [[String: Any]])?.first)
        XCTAssertEqual(entry["name"] as? String, "craftberry:azure_a1b2c3_ingot")
        let block = try json(named: "blocks/azure_a1b2c3_ore.json", in: behavior)
        let blockBody = try XCTUnwrap(block["minecraft:block"] as? [String: Any])
        let desc = try XCTUnwrap(blockBody["description"] as? [String: Any])
        XCTAssertNil(desc["states"])
        XCTAssertEqual(block["format_version"] as? String, "1.21.100")
        // minecraft:destroy_time does not exist in block format 1.21.100 (confirmed
        // live: the engine rejects the whole block file as "not present in the
        // Schema"); mining time goes in destructible_by_mining.seconds_to_destroy
        // per metadata/json_schemas/server/block/1.21.110/Blocks.json at 921fafb0.
        let components = try XCTUnwrap(blockBody["components"] as? [String: Any])
        XCTAssertNil(components["minecraft:destroy_time"])
        let mining = try XCTUnwrap(components["minecraft:destructible_by_mining"] as? [String: Any])
        XCTAssertEqual(mining["seconds_to_destroy"] as? Double, 3.0)
        let blocksMap = try json(named: "blocks.json", in: resources)
        XCTAssertEqual(blocksMap["format_version"] as? String, "1.21.40")
        let terrain = try json(named: "textures/terrain_texture.json", in: resources)
        XCTAssertNotNil((terrain["texture_data"] as? [String: Any])?["azure_a1b2c3_ore"])
    }

    func testCompilerEmitsPlantableGrowingCropWithStageSpecificHarvestAndScript() throws {
        let project = try AddOnProject.materialCropSet(materialName: "Azure", sourceItem: "minecraft:diamond", sourceCount: 4, originalPrompt: "crop", identity: makeIdentity())
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = try BedrockAddOnCompiler().compile(project: project, profile: .current, outputDirectory: directory)
        let outer = try ZipArchiveReader.readEntries(at: result.artifact.url)
        let behavior = try pack(named: "azure_a1b2c3_seed_behavior.mcpack", in: outer)
        let resources = try pack(named: "azure_a1b2c3_seed_resources.mcpack", in: outer)
        let seed = try json(named: "items/azure_a1b2c3_seed.json", in: behavior)
        let seedBody = try XCTUnwrap(seed["minecraft:item"] as? [String: Any])
        let seedComponents = try XCTUnwrap(seedBody["components"] as? [String: Any])
        let placer = try XCTUnwrap(seedComponents["minecraft:block_placer"] as? [String: Any])
        XCTAssertEqual(placer["block"] as? String, "craftberry:azure_a1b2c3_crop")
        XCTAssertEqual(placer["use_on"] as? [String], ["minecraft:farmland"])

        let block = try json(named: "blocks/azure_a1b2c3_crop.json", in: behavior)
        let blockBody = try XCTUnwrap(block["minecraft:block"] as? [String: Any])
        let desc = try XCTUnwrap(blockBody["description"] as? [String: Any])
        let states = try XCTUnwrap(desc["states"] as? [String: Any])
        let growthStateKey = "craftberry:growth_azure_a1b2c3_crop"
        let componentID = "craftberry:crop_grow_azure_a1b2c3_crop"
        let geometryID = "geometry.craftberry.crop_azure_a1b2c3_crop"
        let growth = try XCTUnwrap(states[growthStateKey] as? [String: Any])
        let values = try XCTUnwrap(growth["values"] as? [String: Any])
        XCTAssertEqual(values["min"] as? Int, 0)
        XCTAssertEqual(values["max"] as? Int, 7)
        let perms = try XCTUnwrap(blockBody["permutations"] as? [[String: Any]])
        XCTAssertEqual(perms.count, 8)
        let components = try XCTUnwrap(blockBody["components"] as? [String: Any])
        let placement = try XCTUnwrap(components["minecraft:placement_filter"] as? [String: Any])
        let conditions = try XCTUnwrap(placement["conditions"] as? [[String: Any]])
        XCTAssertEqual(conditions.first?["allowed_faces"] as? [String], ["up"])
        XCTAssertEqual(conditions.first?["block_filter"] as? [String], ["minecraft:farmland"])
        XCTAssertEqual(components["minecraft:geometry"] as? String, geometryID)
        XCTAssertEqual(components["minecraft:collision_box"] as? Bool, false)
        XCTAssertEqual(components["minecraft:loot"] as? String, "loot_tables/blocks/azure_a1b2c3_crop_seeds.json")
        XCTAssertEqual(components[componentID] as? [String: Int], ["stage_count": 8])
        for (stage, permutation) in perms.enumerated() {
            XCTAssertEqual(permutation["condition"] as? String, "query.block_state('\(growthStateKey)') == \(stage)")
            let permutationComponents = try XCTUnwrap(permutation["components"] as? [String: Any])
            let materialInstances = try XCTUnwrap(permutationComponents["minecraft:material_instances"] as? [String: Any])
            let allFaces = try XCTUnwrap(materialInstances["*"] as? [String: Any])
            XCTAssertEqual(allFaces["texture"] as? String, "azure_a1b2c3_crop_stage_\(stage)")
            XCTAssertEqual(allFaces["render_method"] as? String, "alpha_test")
            let expectedLoot = stage == 7 ? "loot_tables/blocks/azure_a1b2c3_crop_harvest.json" : nil
            XCTAssertEqual(permutationComponents["minecraft:loot"] as? String, expectedLoot)
        }

        let unripeLoot = try json(named: "loot_tables/blocks/azure_a1b2c3_crop_seeds.json", in: behavior)
        let unripePools = try XCTUnwrap(unripeLoot["pools"] as? [[String: Any]])
        let unripeEntry = try XCTUnwrap((unripePools.first?["entries"] as? [[String: Any]])?.first)
        XCTAssertEqual(unripeEntry["name"] as? String, "craftberry:azure_a1b2c3_seed")
        let loot = try json(named: "loot_tables/blocks/azure_a1b2c3_crop_harvest.json", in: behavior)
        let pools = try XCTUnwrap(loot["pools"] as? [[String: Any]])
        let harvestItems = pools.compactMap { ($0["entries"] as? [[String: Any]])?.first?["name"] as? String }
        XCTAssertEqual(harvestItems, ["craftberry:azure_a1b2c3_produce", "craftberry:azure_a1b2c3_seed"])

        let manifest = try json(named: "manifest.json", in: behavior)
        let modules = try XCTUnwrap(manifest["modules"] as? [[String: Any]])
        let scriptModule = try XCTUnwrap(modules.first(where: { $0["type"] as? String == "script" }))
        XCTAssertEqual(scriptModule["language"] as? String, "javascript")
        XCTAssertEqual(scriptModule["entry"] as? String, "scripts/craftberry.js")
        let dependencies = try XCTUnwrap(manifest["dependencies"] as? [[String: Any]])
        XCTAssertTrue(dependencies.contains { $0["module_name"] as? String == "@minecraft/server" && $0["version"] as? String == "2.0.0" })
        let scriptEntry = try XCTUnwrap(behavior.first(where: { $0.path == "scripts/craftberry.js" }))
        let script = try XCTUnwrap(String(data: scriptEntry.data, encoding: .utf8))
        XCTAssertTrue(script.contains("onRandomTick"))
        XCTAssertTrue(script.contains("stage + 1"))
        XCTAssertTrue(script.contains("stage >= stageCount - 1"))
        XCTAssertTrue(script.contains(componentID))
        XCTAssertTrue(script.contains(growthStateKey))

        let stageTextures = (0..<8).compactMap { stage in
            resources.first { $0.path == "textures/blocks/azure_a1b2c3_crop_stage_\(stage).png" }?.data
        }
        XCTAssertEqual(stageTextures.count, 8)
        XCTAssertEqual(Set(stageTextures.map { $0.base64EncodedString() }).count, 8)
        let terrain = try json(named: "textures/terrain_texture.json", in: resources)
        let terrainData = try XCTUnwrap(terrain["texture_data"] as? [String: Any])
        for stage in 0..<8 {
            XCTAssertNotNil(terrainData["azure_a1b2c3_crop_stage_\(stage)"])
        }
        let geometry = try json(named: "models/blocks/azure_a1b2c3_crop.geo.json", in: resources)
        let geometries = try XCTUnwrap(geometry["minecraft:geometry"] as? [[String: Any]])
        let geometryDescription = try XCTUnwrap(geometries.first?["description"] as? [String: Any])
        XCTAssertEqual(geometryDescription["identifier"] as? String, geometryID)
        XCTAssertEqual(geometryDescription["texture_width"] as? Int, 16)
        XCTAssertEqual(geometryDescription["texture_height"] as? Int, 16)
        let bones = try XCTUnwrap(geometries.first?["bones"] as? [[String: Any]])
        XCTAssertEqual((bones.first?["cubes"] as? [[String: Any]])?.count, 2)
    }

    func testCropRuntimeIdentifiersAreIsolatedAcrossGeneratedPacks() throws {
        let first = try AddOnProject.materialCropSet(
            materialName: "Azure",
            originalPrompt: "first crop",
            identity: makeIdentity()
        )
        let second = try AddOnProject.materialCropSet(
            materialName: "Azure",
            originalPrompt: "second crop",
            identity: AddOnProjectIdentity(
                projectID: UUID(uuidString: "10000000-0000-4000-8000-000000000002")!,
                namespace: "craftberry",
                contentSuffix: "d4e5f6",
                packUUIDs: PackUUIDs(
                    behaviorHeader: UUID(uuidString: "20000000-0000-4000-8000-000000000011")!,
                    behaviorModule: UUID(uuidString: "20000000-0000-4000-8000-000000000012")!,
                    resourceHeader: UUID(uuidString: "20000000-0000-4000-8000-000000000013")!,
                    resourceModule: UUID(uuidString: "20000000-0000-4000-8000-000000000014")!,
                    behaviorScriptModule: UUID(uuidString: "20000000-0000-4000-8000-000000000015")!
                )
            )
        )
        let directory = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let compiler = BedrockAddOnCompiler()
        let firstResult = try compiler.compile(project: first, profile: .current, outputDirectory: directory)
        let secondResult = try compiler.compile(project: second, profile: .current, outputDirectory: directory)

        let runtimeIdentifiers = try [first, second].map { project -> (String, String, String) in
            let block = try XCTUnwrap(project.blocks.first)
            let stateKey = "\(project.namespace):growth_\(block.id.rawValue)"
            let componentID = "\(project.namespace):crop_grow_\(block.id.rawValue)"
            let geometryID = "geometry.craftberry.crop_\(block.id.rawValue)"
            return (stateKey, componentID, geometryID)
        }
        XCTAssertEqual(Set(runtimeIdentifiers.map(\.0)).count, 2)
        XCTAssertEqual(Set(runtimeIdentifiers.map(\.1)).count, 2)
        XCTAssertEqual(Set(runtimeIdentifiers.map(\.2)).count, 2)

        let compiledProjects = [
            (first, firstResult, runtimeIdentifiers[0]),
            (second, secondResult, runtimeIdentifiers[1])
        ]
        for (project, result, identifiers) in compiledProjects {
            let blockID = try XCTUnwrap(project.blocks.first?.id.rawValue)
            let outer = try ZipArchiveReader.readEntries(at: result.artifact.url)
            let behavior = try pack(named: "\(project.items[0].id.rawValue)_behavior.mcpack", in: outer)
            let resources = try pack(named: "\(project.items[0].id.rawValue)_resources.mcpack", in: outer)
            let block = try json(named: "blocks/\(blockID).json", in: behavior)
            let blockBody = try XCTUnwrap(block["minecraft:block"] as? [String: Any])
            let description = try XCTUnwrap(blockBody["description"] as? [String: Any])
            let states = try XCTUnwrap(description["states"] as? [String: Any])
            XCTAssertNotNil(states[identifiers.0])
            let components = try XCTUnwrap(blockBody["components"] as? [String: Any])
            XCTAssertEqual(components[identifiers.1] as? [String: Int], ["stage_count": 8])
            XCTAssertEqual(components["minecraft:geometry"] as? String, identifiers.2)
            let permutations = try XCTUnwrap(blockBody["permutations"] as? [[String: Any]])
            XCTAssertTrue(permutations.allSatisfy { ($0["condition"] as? String)?.contains(identifiers.0) == true })

            let scriptEntry = try XCTUnwrap(behavior.first(where: { $0.path == "scripts/craftberry.js" }))
            let script = try XCTUnwrap(String(data: scriptEntry.data, encoding: .utf8))
            XCTAssertTrue(script.contains(identifiers.1))
            XCTAssertTrue(script.contains(identifiers.0))

            let geometry = try json(named: "models/blocks/\(blockID).geo.json", in: resources)
            let geometryList = try XCTUnwrap(geometry["minecraft:geometry"] as? [[String: Any]])
            let geometryDescription = try XCTUnwrap(geometryList.first?["description"] as? [String: Any])
            XCTAssertEqual(geometryDescription["identifier"] as? String, identifiers.2)
        }
    }

    func testCompilerEmitsMaterialEntitySetWithSpawnAndLoot() throws {
        let project = try AddOnProject.materialEntitySet(materialName: "Azure", sourceItem: "minecraft:diamond", sourceCount: 4, health: 10, originalPrompt: "entity", identity: makeIdentity())
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        addTeardownBlock { _ = try? FileManager.default.removeItem(at: directory) }
        let result = try BedrockAddOnCompiler().compile(project: project, profile: .current, outputDirectory: directory)
        let outer = try ZipArchiveReader.readEntries(at: result.artifact.url)
        let behavior = try pack(named: "azure_a1b2c3_ingot_behavior.mcpack", in: outer)
        let resources = try pack(named: "azure_a1b2c3_ingot_resources.mcpack", in: outer)
        XCTAssertTrue(behavior.contains { $0.path == "entities/azure_a1b2c3_creature.json" })
        XCTAssertTrue(behavior.contains { $0.path == "spawn_rules/azure_a1b2c3_spawn_rule.json" })
        XCTAssertTrue(behavior.contains { $0.path == "loot_tables/entities/azure_a1b2c3_creature.json" })
        XCTAssertTrue(resources.contains { $0.path == "entity/azure_a1b2c3_creature.entity.json" })
        // Entity pinned to chicken 1.26.10
        let entity = try json(named: "entities/azure_a1b2c3_creature.json", in: behavior)
        XCTAssertEqual(entity["format_version"] as? String, "1.26.10")
        let entityBody = try XCTUnwrap(entity["minecraft:entity"] as? [String: Any])
        let desc = try XCTUnwrap(entityBody["description"] as? [String: Any])
        XCTAssertEqual(desc["identifier"] as? String, "craftberry:azure_a1b2c3_creature")
        XCTAssertEqual(desc["is_spawnable"] as? Bool, true)
        XCTAssertEqual(desc["spawn_category"] as? String, "creature")
        let components = try XCTUnwrap(entityBody["components"] as? [String: Any])
        let health = try XCTUnwrap(components["minecraft:health"] as? [String: Any])
        XCTAssertEqual(health["value"] as? Int, 10)
        // Pushability pinned to chicken 1.26.10: the legacy minecraft:pushable was split
        // into pushable_by_entity/pushable_by_block, and the engine rejects the whole
        // entity file when the legacy key is present (confirmed live via Content Log).
        XCTAssertNil(components["minecraft:pushable"])
        XCTAssertNotNil(components["minecraft:pushable_by_entity"] as? [String: Any])
        XCTAssertNotNil(components["minecraft:pushable_by_block"] as? [String: Any])
        // Spawn rule pinned to chicken 1.8.0
        let spawn = try json(named: "spawn_rules/azure_a1b2c3_spawn_rule.json", in: behavior)
        XCTAssertEqual(spawn["format_version"] as? String, "1.8.0")
        let spawnBody = try XCTUnwrap(spawn["minecraft:spawn_rules"] as? [String: Any])
        let spawnDesc = try XCTUnwrap(spawnBody["description"] as? [String: Any])
        XCTAssertEqual(spawnDesc["identifier"] as? String, "craftberry:azure_a1b2c3_creature")
        XCTAssertEqual(spawnDesc["population_control"] as? String, "animal")
        // Loot
        let loot = try json(named: "loot_tables/entities/azure_a1b2c3_creature.json", in: behavior)
        let pools = try XCTUnwrap(loot["pools"] as? [[String: Any]])
        let entry = try XCTUnwrap((pools.first?["entries"] as? [[String: Any]])?.first)
        XCTAssertEqual(entry["name"] as? String, "minecraft:feather")
        // Client entity pinned to 1.10.0 with pig geometry
        let client = try json(named: "entity/azure_a1b2c3_creature.entity.json", in: resources)
        XCTAssertEqual(client["format_version"] as? String, "1.10.0")
        let clientBody = try XCTUnwrap(client["minecraft:client_entity"] as? [String: Any])
        let clientDesc = try XCTUnwrap(clientBody["description"] as? [String: Any])
        XCTAssertEqual(clientDesc["identifier"] as? String, "craftberry:azure_a1b2c3_creature")
        XCTAssertEqual((clientDesc["materials"] as? [String: String])?["default"], "entity_alphatest")
        XCTAssertEqual((clientDesc["geometry"] as? [String: String])?["default"], "geometry.pig")
        XCTAssertEqual((clientDesc["render_controllers"] as? [String])?.first, "controller.render.azure_a1b2c3_creature")
        // Render controller pinned to pig.render_controllers.json minus its saddle texture
        // array: the shared pig controller errors on our single-texture entity (confirmed
        // live via Content Log), so each entity ships its own minimal controller.
        let controller = try json(named: "render_controllers/azure_a1b2c3_creature.render_controllers.json", in: resources)
        XCTAssertEqual(controller["format_version"] as? String, "1.8.0")
        let controllers = try XCTUnwrap(controller["render_controllers"] as? [String: Any])
        let ours = try XCTUnwrap(controllers["controller.render.azure_a1b2c3_creature"] as? [String: Any])
        XCTAssertEqual(ours["geometry"] as? String, "Geometry.default")
        XCTAssertEqual((ours["materials"] as? [[String: String]])?.first?["*"], "Material.default")
        XCTAssertEqual(ours["textures"] as? [String], ["Texture.default"])
        // Entity body texture (pig-UV placeholder in material colors). A missing texture
        // leaves the creature unrenderable, so assert exact bytes, not just presence.
        let bodyTexture = try XCTUnwrap(resources.first { $0.path == "textures/entity/azure_a1b2c3_creature.png" })
        XCTAssertEqual(PNGInspector.dimensions(of: bodyTexture.data), .init(width: 64, height: 32))
        let spawnEgg = try XCTUnwrap(clientDesc["spawn_egg"] as? [String: String])
        XCTAssertEqual(spawnEgg["texture"], "azure_a1b2c3_spawn_egg")
        // Spawn egg item
        XCTAssertTrue(behavior.contains { $0.path == "items/azure_a1b2c3_spawn_egg.json" })
        XCTAssertTrue(behavior.contains { $0.path == "recipes/azure_a1b2c3_spawn_egg_recipe.json" })
        let textureMap = try json(named: "textures/item_texture.json", in: resources)
        let textureData = try XCTUnwrap(textureMap["texture_data"] as? [String: Any])
        XCTAssertNotNil(textureData["azure_a1b2c3_spawn_egg"])
        // The egg must place its entity when used; without minecraft:entity_placer it is
        // a plain generic item and tapping a block with it spawns nothing (confirmed live:
        // /testfor found no monster after using the crafted egg).
        let spawnEggItem = try json(named: "items/azure_a1b2c3_spawn_egg.json", in: behavior)
        let spawnEggItemBody = try XCTUnwrap(spawnEggItem["minecraft:item"] as? [String: Any])
        let spawnEggComponents = try XCTUnwrap(spawnEggItemBody["components"] as? [String: Any])
        let placer = try XCTUnwrap(spawnEggComponents["minecraft:entity_placer"] as? [String: Any])
        XCTAssertEqual(placer["entity"] as? String, "craftberry:azure_a1b2c3_creature")
    }

    func testCompilerEmitsHostilePlayerTargetingBehaviorPinnedToZombieSample() throws {
        let project = try AddOnProject.materialHostileEntitySet(
            materialName: "Azure",
            sourceItem: "minecraft:diamond",
            sourceCount: 4,
            health: 24,
            originalPrompt: "hostile entity",
            identity: makeIdentity()
        )
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = try BedrockAddOnCompiler().compile(project: project, profile: .current, outputDirectory: directory)
        let outer = try ZipArchiveReader.readEntries(at: result.artifact.url)
        let behavior = try pack(named: "azure_a1b2c3_ingot_behavior.mcpack", in: outer)
        let entity = try json(named: "entities/azure_a1b2c3_creature.json", in: behavior)
        let entityBody = try XCTUnwrap(entity["minecraft:entity"] as? [String: Any])
        let description = try XCTUnwrap(entityBody["description"] as? [String: Any])
        XCTAssertEqual(description["spawn_category"] as? String, "monster")
        let components = try XCTUnwrap(entityBody["components"] as? [String: Any])
        let typeFamily = try XCTUnwrap(components["minecraft:type_family"] as? [String: Any])
        XCTAssertEqual(typeFamily["family"] as? [String], ["azure_a1b2c3_creature", "monster", "mob"])
        let attack = try XCTUnwrap(components["minecraft:attack"] as? [String: Any])
        XCTAssertEqual(attack["damage"] as? Int, 3)
        XCTAssertNotNil(components["minecraft:behavior.melee_box_attack"])
        let target = try XCTUnwrap(components["minecraft:behavior.nearest_attackable_target"] as? [String: Any])
        XCTAssertEqual(target["must_see"] as? Bool, true)
        let entityTypes = try XCTUnwrap(target["entity_types"] as? [[String: Any]])
        let filters = try XCTUnwrap(entityTypes.first?["filters"] as? [String: Any])
        let anyOf = try XCTUnwrap(filters["any_of"] as? [[String: Any]])
        XCTAssertEqual(anyOf.first?["value"] as? String, "player")

        let spawn = try json(named: "spawn_rules/azure_a1b2c3_spawn_rule.json", in: behavior)
        let spawnRules = try XCTUnwrap(spawn["minecraft:spawn_rules"] as? [String: Any])
        let spawnDescription = try XCTUnwrap(spawnRules["description"] as? [String: Any])
        XCTAssertEqual(spawnDescription["identifier"] as? String, "craftberry:azure_a1b2c3_creature")
        XCTAssertEqual(spawnDescription["population_control"] as? String, "monster")
        let conditions = try XCTUnwrap(spawnRules["conditions"] as? [[String: Any]])
        let condition = try XCTUnwrap(conditions.first)
        XCTAssertNotNil(condition["minecraft:spawns_on_surface"] as? [String: Any])
        XCTAssertNotNil(condition["minecraft:spawns_underground"] as? [String: Any])
        XCTAssertNil(condition["minecraft:spawns_on_block_filter"])
        XCTAssertNil(condition["minecraft:herd"])
        let difficulty = try XCTUnwrap(condition["minecraft:difficulty_filter"] as? [String: Any])
        XCTAssertEqual(difficulty["min"] as? String, "easy")
        XCTAssertEqual(difficulty["max"] as? String, "hard")
        let weight = try XCTUnwrap(condition["minecraft:weight"] as? [String: Any])
        XCTAssertEqual(weight["default"] as? Int, 100)
        let biomeFilter = try XCTUnwrap(condition["minecraft:biome_filter"] as? [String: Any])
        let allOf = try XCTUnwrap(biomeFilter["all_of"] as? [[String: Any]])
        XCTAssertEqual(allOf.count, 2)
        XCTAssertEqual(allOf[0]["test"] as? String, "has_biome_tag")
        XCTAssertNil(allOf[0]["operator"])
        XCTAssertEqual(allOf[0]["value"] as? String, "monster")
        XCTAssertEqual(allOf[1]["operator"] as? String, "!=")
        XCTAssertEqual(allOf[1]["value"] as? String, "sulfur_caves")
        let brightness = try XCTUnwrap(condition["minecraft:brightness_filter"] as? [String: Any])
        XCTAssertEqual(brightness["min"] as? Int, 0)
        XCTAssertEqual(brightness["max"] as? Int, 7)
        XCTAssertEqual(brightness["adjust_for_weather"] as? Bool, true)
    }

    func testCompilerEmitsBossPhaseAndRewardUsingPinnedEntityPatterns() throws {
        let project = try AddOnProject.materialBossEntitySet(
            materialName: "Azure",
            sourceItem: "minecraft:diamond",
            sourceCount: 4,
            health: 40,
            originalPrompt: "a two-phase Azure boss",
            identity: makeIdentity()
        )
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = try BedrockAddOnCompiler().compile(project: project, profile: .current, outputDirectory: directory)
        let outer = try ZipArchiveReader.readEntries(at: result.artifact.url)
        let behavior = try pack(named: "azure_a1b2c3_ingot_behavior.mcpack", in: outer)
        let entity = try json(named: "entities/azure_a1b2c3_creature.json", in: behavior)
        let entityBody = try XCTUnwrap(entity["minecraft:entity"] as? [String: Any])
        let components = try XCTUnwrap(entityBody["components"] as? [String: Any])
        let phaseOneAttack = try XCTUnwrap(components["minecraft:attack"] as? [String: Any])
        XCTAssertEqual(phaseOneAttack["damage"] as? Int, 1)
        let boss = try XCTUnwrap(components["minecraft:boss"] as? [String: Any])
        XCTAssertEqual(boss["hud_range"] as? Int, 55)
        XCTAssertEqual(boss["should_darken_sky"] as? Bool, false)

        let componentGroups = try XCTUnwrap(entityBody["component_groups"] as? [String: Any])
        let phaseOne = try XCTUnwrap(componentGroups["azure_a1b2c3_creature_boss_phase_one"] as? [String: Any])
        let phaseOneSensor = try XCTUnwrap(phaseOne["minecraft:environment_sensor"] as? [String: Any])
        let triggers = try XCTUnwrap(phaseOneSensor["triggers"] as? [[String: Any]])
        let phaseTrigger = try XCTUnwrap(triggers.first)
        let filters = try XCTUnwrap(phaseTrigger["filters"] as? [String: Any])
        XCTAssertEqual(filters["test"] as? String, "actor_health")
        XCTAssertEqual(filters["subject"] as? String, "self")
        XCTAssertEqual(filters["operator"] as? String, "<=")
        XCTAssertEqual(filters["value"] as? Int, 20)
        XCTAssertEqual(phaseTrigger["event"] as? String, "craftberry:azure_a1b2c3_creature_boss_phase_two")

        let phaseTwo = try XCTUnwrap(componentGroups["azure_a1b2c3_creature_boss_phase_two"] as? [String: Any])
        let phaseAttack = try XCTUnwrap(phaseTwo["minecraft:attack"] as? [String: Any])
        XCTAssertEqual(phaseAttack["damage"] as? Int, 12)
        let phaseMovement = try XCTUnwrap(phaseTwo["minecraft:movement"] as? [String: Any])
        XCTAssertEqual(phaseMovement["value"] as? Double, 0.45)
        let phaseScale = try XCTUnwrap(phaseTwo["minecraft:scale"] as? [String: Any])
        XCTAssertEqual(phaseScale["value"] as? Double, 1.25)

        let events = try XCTUnwrap(entityBody["events"] as? [String: Any])
        let spawn = try XCTUnwrap(events["minecraft:entity_spawned"] as? [String: Any])
        let spawnAdd = try XCTUnwrap(spawn["add"] as? [String: Any])
        XCTAssertEqual(
            spawnAdd["component_groups"] as? [String],
            ["azure_a1b2c3_creature_adult", "azure_a1b2c3_creature_boss_phase_one"]
        )
        let adultGroup = try XCTUnwrap(componentGroups["azure_a1b2c3_creature_adult"] as? [String: Any])
        let entityLoot = try XCTUnwrap(adultGroup["minecraft:loot"] as? [String: Any])
        XCTAssertEqual(entityLoot["table"] as? String, "loot_tables/entities/azure_a1b2c3_creature.json")
        let phaseEvent = try XCTUnwrap(events["craftberry:azure_a1b2c3_creature_boss_phase_two"] as? [String: Any])
        let phaseAdd = try XCTUnwrap(phaseEvent["add"] as? [String: Any])
        XCTAssertEqual(phaseAdd["component_groups"] as? [String], ["azure_a1b2c3_creature_boss_phase_two"])
        let phaseRemove = try XCTUnwrap(phaseEvent["remove"] as? [String: Any])
        XCTAssertEqual(phaseRemove["component_groups"] as? [String], ["azure_a1b2c3_creature_boss_phase_one"])

        let loot = try json(named: "loot_tables/entities/azure_a1b2c3_creature.json", in: behavior)
        let pools = try XCTUnwrap(loot["pools"] as? [[String: Any]])
        XCTAssertEqual(pools.first?["rolls"] as? Int, 1)
        let entries = try XCTUnwrap(pools.first?["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?["name"] as? String, "craftberry:azure_a1b2c3_ingot")
        XCTAssertEqual(entries.first?["weight"] as? Int, 1)

        let resources = try pack(named: "azure_a1b2c3_ingot_resources.mcpack", in: outer)
        let localization = try XCTUnwrap(String(data: XCTUnwrap(resources.first { $0.path == "texts/en_US.lang" }).data, encoding: .utf8))
        XCTAssertTrue(localization.contains("entity.craftberry:azure_a1b2c3_creature.name=Azure Boss"))
    }

    func testCompilerEmitsMaterialStructureSetWithHutAndFeature() throws {
        let project = try AddOnProject.materialStructureSet(materialName: "Azure", sourceItem: "minecraft:diamond", sourceCount: 4, originalPrompt: "hut", identity: makeIdentity())
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = try BedrockAddOnCompiler().compile(project: project, profile: .current, outputDirectory: directory)
        let outer = try ZipArchiveReader.readEntries(at: result.artifact.url)
        let behavior = try pack(named: "azure_a1b2c3_ingot_behavior.mcpack", in: outer)
        XCTAssertTrue(behavior.contains { $0.path == "blocks/azure_a1b2c3_block.json" })
        XCTAssertTrue(behavior.contains { $0.path == "structures/craftberry/azure_a1b2c3_hut.mcstructure" })
        XCTAssertTrue(behavior.contains { $0.path == "features/azure_a1b2c3_hut_feature.json" })
        XCTAssertTrue(behavior.contains { $0.path == "feature_rules/azure_a1b2c3_hut_rule.json" })
        let mc = try XCTUnwrap(behavior.first { $0.path == "structures/craftberry/azure_a1b2c3_hut.mcstructure" })
        XCTAssertGreaterThan(mc.data.count, 80)
        let directory2 = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory2) }
        let result2 = try BedrockAddOnCompiler().compile(project: project, profile: .current, outputDirectory: directory2)
        let outer2 = try ZipArchiveReader.readEntries(at: result2.artifact.url)
        let behavior2 = try pack(named: "azure_a1b2c3_ingot_behavior.mcpack", in: outer2)
        let mc2 = try XCTUnwrap(behavior2.first { $0.path == "structures/craftberry/azure_a1b2c3_hut.mcstructure" })
        XCTAssertEqual(mc.data, mc2.data)
        let feature = try json(named: "features/azure_a1b2c3_hut_feature.json", in: behavior)
        let structureFeature = try XCTUnwrap(feature["minecraft:structure_template_feature"] as? [String: Any])
        let desc = try XCTUnwrap(structureFeature["description"] as? [String: Any])
        XCTAssertEqual(desc["identifier"] as? String, "craftberry:azure_a1b2c3_hut_feature")
        XCTAssertEqual(structureFeature["structure_name"] as? String, "craftberry:azure_a1b2c3_hut")
        XCTAssertEqual(structureFeature["adjustment_radius"] as? Int, 0)
        let constraints = try XCTUnwrap(structureFeature["constraints"] as? [String: Any])
        XCTAssertNotNil(constraints["grounded"])
        XCTAssertNotNil(constraints["unburied"])
        XCTAssertEqual(feature["format_version"] as? String, "1.13.0")
        let rule = try json(named: "feature_rules/azure_a1b2c3_hut_rule.json", in: behavior)
        let ruleBody = try XCTUnwrap(rule["minecraft:feature_rules"] as? [String: Any])
        let ruleDesc = try XCTUnwrap(ruleBody["description"] as? [String: Any])
        XCTAssertEqual(ruleDesc["identifier"] as? String, "craftberry:azure_a1b2c3_hut_rule")
        XCTAssertEqual(ruleDesc["places_feature"] as? String, "craftberry:azure_a1b2c3_hut_feature")
        XCTAssertEqual(rule["format_version"] as? String, "1.13.0")
        // Scatter extents require maximum greater than minimum (confirmed live: [0,0]
        // fails the rule with "Bad value for extent"). Minimal valid scatter keeps the
        // hut near its station for locate-based verification.
        let distribution = try XCTUnwrap(ruleBody["distribution"] as? [String: Any])
        for axis in ["x", "y", "z"] {
            let scatter = try XCTUnwrap(distribution[axis] as? [String: Any], "missing \(axis) scatter")
            XCTAssertEqual(scatter["extent"] as? [Int], [0, 1], "invalid \(axis) extent")
        }
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

    private func makeIdentity() -> AddOnProjectIdentity {
        AddOnProjectIdentity(
            projectID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
            namespace: "craftberry",
            contentSuffix: "a1b2c3",
            packUUIDs: PackUUIDs(
                behaviorHeader: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!,
                behaviorModule: UUID(uuidString: "20000000-0000-4000-8000-000000000002")!,
                resourceHeader: UUID(uuidString: "20000000-0000-4000-8000-000000000003")!,
                resourceModule: UUID(uuidString: "20000000-0000-4000-8000-000000000004")!,
                behaviorScriptModule: UUID(uuidString: "20000000-0000-4000-8000-000000000005")!
            )
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

    private func sourceWorldTemplateEntries() throws -> [ZipArchiveEntry] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Craftberry/Resources/BedrockWorldTemplate", directoryHint: .isDirectory)
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        return try enumerator.compactMap { item in
            guard let url = item as? URL, !url.hasDirectoryPath else { return nil }
            let path = url.path.replacingOccurrences(of: root.path + "/", with: "")
            return ZipArchiveEntry(path: path, data: try Data(contentsOf: url))
        }.sorted { $0.path < $1.path }
    }
}
