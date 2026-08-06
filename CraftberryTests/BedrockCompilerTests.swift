import Foundation
import XCTest
#if canImport(CraftberryCore)
@testable import CraftberryCore
#else
@testable import Craftberry
#endif

final class BedrockCompilerTests: XCTestCase {
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

    private func makeIdentity() -> AddOnProjectIdentity {
        AddOnProjectIdentity(projectID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!, namespace: "craftberry", contentSuffix: "a1b2c3", packUUIDs: PackUUIDs(behaviorHeader: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!, behaviorModule: UUID(uuidString: "20000000-0000-4000-8000-000000000002")!, resourceHeader: UUID(uuidString: "20000000-0000-4000-8000-000000000003")!, resourceModule: UUID(uuidString: "20000000-0000-4000-8000-000000000004")!))
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
