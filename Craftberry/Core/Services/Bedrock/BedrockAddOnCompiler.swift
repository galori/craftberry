import Foundation

private struct BedrockAddOnArchive: Sendable {
    public let entries: [ZipArchiveEntry]
}

public struct BedrockAddOnArtifact: Sendable {
    public let url: URL
    public let identifier: BedrockIdentifier
    public let fileName: String
    public let projectSidecarURL: URL
}

public struct BedrockCompilationResult: Sendable {
    public let artifact: BedrockAddOnArtifact
    public let report: CompilationReport
}

public enum BedrockCompilationError: LocalizedError {
    case invalidProject(CompilationReport)

    public var errorDescription: String? {
        switch self {
        case .invalidProject(let report):
            report.errors.first?.message ?? "The add-on project is invalid."
        }
    }
}

public protocol AddOnCompiling: Sendable {
    func compile(
        project: AddOnProject,
        profile: BedrockContentProfile,
        outputDirectory: URL
    ) throws -> BedrockCompilationResult
}

public final class BedrockAddOnCompiler: AddOnCompiling, Sendable {
    public init() {}

    public func compile(
        project: AddOnProject,
        profile: BedrockContentProfile,
        outputDirectory: URL
    ) throws -> BedrockCompilationResult {
        let project = try project.migratedToCurrentSchema()
        let validationReport = AddOnProjectValidator.validate(project, profile: profile)
        guard validationReport.isSuccessful else {
            throw BedrockCompilationError.invalidProject(validationReport)
        }

        let compiledArchive = try makeArchive(project: project, profile: profile)
        let archiveData = try ZipArchiveWriter.archive(entries: compiledArchive.archive.entries)
        let sidecarData = try BedrockDocumentEncoder.encode(project)
        let primaryItem = try require(
            project.items.first,
            profile: profile,
            code: "missing_required_content",
            path: "content.items",
            message: "An add-on project must contain at least one item."
        )
        let identifier = BedrockIdentifier(rawValue: "\(project.namespace):\(primaryItem.id.rawValue)")

        let projectDirectory = outputDirectory.appending(
            path: project.id.uuidString.lowercased(),
            directoryHint: .isDirectory
        )
        let sidecarURL = projectDirectory.appending(path: "project.json")
        let version = project.buildVersion.components.map(String.init).joined(separator: ".")
        let buildDirectory = projectDirectory.appending(
            path: "builds/\(version)",
            directoryHint: .isDirectory
        )
        let outputURL = buildDirectory.appending(path: "\(identifier.pathComponent).mcaddon")

        try FileManager.default.createDirectory(at: buildDirectory, withIntermediateDirectories: true)
        try sidecarData.write(to: sidecarURL, options: .atomic)
        try archiveData.write(to: outputURL, options: .atomic)

        let report = CompilationReport(
            profileID: profile.id,
            issues: validationReport.issues,
            emittedFiles: compiledArchive.emittedFiles.sorted()
        )
        return BedrockCompilationResult(
            artifact: BedrockAddOnArtifact(
                url: outputURL,
                identifier: identifier,
                fileName: outputURL.lastPathComponent,
                projectSidecarURL: sidecarURL
            ),
            report: report
        )
    }

    private func makeArchive(
        project: AddOnProject,
        profile: BedrockContentProfile
    ) throws -> (archive: BedrockAddOnArchive, emittedFiles: [String]) {
        let primaryItem = try require(
            project.items.first,
            profile: profile,
            code: "missing_required_content",
            path: "content.items",
            message: "An add-on project must contain at least one item."
        )
        let behaviorPackName = "\(primaryItem.id.rawValue)_behavior"
        let resourcePackName = "\(primaryItem.id.rawValue)_resources"
        let behaviorEntries = try behaviorPackEntries(project: project, profile: profile)
        let resourceEntries = try resourcePackEntries(project: project, profile: profile)
        let outerEntries = [
            ZipArchiveEntry(
                path: "\(behaviorPackName).mcpack",
                data: try ZipArchiveWriter.archive(entries: behaviorEntries)
            ),
            ZipArchiveEntry(
                path: "\(resourcePackName).mcpack",
                data: try ZipArchiveWriter.archive(entries: resourceEntries)
            )
        ]
        let emittedFiles = outerEntries.map(\.path)
            + behaviorEntries.map { "behavior/\($0.path)" }
            + resourceEntries.map { "resources/\($0.path)" }
        return (BedrockAddOnArchive(entries: outerEntries), emittedFiles)
    }

    private func behaviorPackEntries(
        project: AddOnProject,
        profile: BedrockContentProfile
    ) throws -> [ZipArchiveEntry] {
        let version = project.buildVersion.components
        let manifest = ManifestDocument(
            formatVersion: profile.manifestFormatVersion,
            header: ManifestDocument.Header(
                name: "\(project.displayName) Behavior",
                description: "Generated by Craftberry",
                uuid: project.packUUIDs.behaviorHeader.uuidString.lowercased(),
                version: version,
                minimumEngineVersion: profile.minimumEngineVersion.components
            ),
            modules: [ManifestDocument.Module(
                type: "data",
                uuid: project.packUUIDs.behaviorModule.uuidString.lowercased(),
                version: version
            )],
            dependencies: [ManifestDocument.Dependency(
                uuid: project.packUUIDs.resourceHeader.uuidString.lowercased(),
                version: version
            )]
        )
        let primaryVisual = try primaryVisualResource(project: project, profile: profile)
        var entries = [
            ZipArchiveEntry(path: "manifest.json", data: try BedrockDocumentEncoder.encode(manifest))
        ]
        for block in project.blocks.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
            let identifier = identifier(for: block.id, namespace: project.namespace)
            let document = BlockDocument(
                formatVersion: profile.blockFormatVersion,
                block: BlockDocument.Block(
                    description: BlockDocument.Description(
                        identifier: identifier,
                        menuCategory: BlockDocument.MenuCategory(category: "construction", group: "minecraft:itemGroup.name.blocks")
                    ),
                    components: BlockDocument.Components(
                        destroyTime: block.destroyTime,
                        mapColor: BlockDocument.MapColor(color: block.mapColor),
                        lightDampening: 15,
                        loot: "loot_tables/blocks/\(block.id.rawValue).json"
                    )
                )
            )
            entries.append(ZipArchiveEntry(path: "blocks/\(block.id.rawValue).json", data: try BedrockDocumentEncoder.encode(document)))
            let loot = LootTableDocument(pools: [LootTableDocument.Pool(rolls: 1, entries: [LootTableDocument.Entry(type: "item", name: identifier, weight: 1)])])
            entries.append(ZipArchiveEntry(path: "loot_tables/blocks/\(block.id.rawValue).json", data: try BedrockDocumentEncoder.encode(loot)))
        }
        for item in project.items.sorted(by: contentOrder) {
            let identifier = identifier(for: item.id, namespace: project.namespace)
            let document = ItemDocument(
                formatVersion: profile.itemFormatVersion,
                item: ItemDocument.Item(
                    description: ItemDocument.Description(
                        identifier: identifier,
                        menuCategory: ItemDocument.MenuCategory(
                            category: item.menuCategory.rawValue,
                            group: item.menuGroup
                        )
                    ),
                    components: ItemDocument.Components(
                        displayName: ItemDocument.DisplayName(value: "item.\(identifier).name"),
                        icon: ItemDocument.Icon(textures: ["default": item.id.rawValue]),
                        maximumStackSize: item.traits.maximumStackSize,
                        handEquipped: ItemDocument.HandEquipped(value: item.traits.handEquipped),
                        damage: item.traits.combat.map { ItemDocument.Damage(value: $0.attackBonus) },
                        durability: item.traits.durability.map {
                            ItemDocument.Durability(
                                maximumDurability: $0.maximum,
                                damageChance: ItemDocument.DamageChance(min: 100, max: 100)
                            )
                        },
                        wearable: item.traits.armor.map {
                            ItemDocument.Wearable(slot: $0.slot.bedrockSlot, protection: $0.protection)
                        },
                        food: item.traits.food.map {
                            ItemDocument.Food(
                                nutrition: $0.nutrition,
                                saturationModifier: $0.saturationModifier,
                                canAlwaysEat: $0.canAlwaysEat ? true : nil
                            )
                        },
                        fuel: item.traits.fuel.map { ItemDocument.Fuel(duration: $0.duration) }
                    )
                )
            )
            entries.append(
                ZipArchiveEntry(
                    path: "items/\(item.id.rawValue).json",
                    data: try BedrockDocumentEncoder.encode(document)
                )
            )
        }
        for recipe in project.recipes.sorted(by: recipeOrder) {
            let resultIdentifier = try resultIdentifier(
                for: recipe.result.item,
                namespace: project.namespace,
                profile: profile,
                path: "content.recipes.\(recipe.id.rawValue).result"
            )
            var key: [String: ShapedRecipeDocument.Ingredient] = [:]
            for (symbol, reference) in recipe.ingredients {
                key[symbol] = try ingredient(
                    for: reference,
                    namespace: project.namespace,
                    profile: profile,
                    path: "content.recipes.\(recipe.id.rawValue).ingredients.\(symbol)"
                )
            }
            let unlock = try recipe.unlock.enumerated().map { index, reference in
                try ingredient(
                    for: reference,
                    namespace: project.namespace,
                    profile: profile,
                    path: "content.recipes.\(recipe.id.rawValue).unlock.\(index)"
                )
            }
            let document = ShapedRecipeDocument(
                formatVersion: profile.recipeFormatVersion,
                recipe: ShapedRecipeDocument.Recipe(
                    description: ShapedRecipeDocument.Description(
                        identifier: identifier(for: recipe.id, namespace: project.namespace)
                    ),
                    tags: recipe.tags,
                    pattern: recipe.pattern,
                    key: key,
                    result: ShapedRecipeDocument.Result(item: resultIdentifier, count: recipe.result.count),
                    unlock: unlock
                )
            )
            entries.append(
                ZipArchiveEntry(
                    path: "recipes/\(recipe.id.rawValue).json",
                    data: try BedrockDocumentEncoder.encode(document)
                )
            )
        }
        for recipe in project.shapelessRecipes.sorted(by: shapelessRecipeOrder) {
            let resultIdentifier = try resultIdentifier(for: recipe.result.item, namespace: project.namespace, profile: profile, path: "content.recipes.\(recipe.id.rawValue).result")
            let ingredients = try recipe.ingredients.enumerated().map { index, reference in
                try ingredient(for: reference, namespace: project.namespace, profile: profile, path: "content.recipes.\(recipe.id.rawValue).ingredients.\(index)")
            }
            let unlock = try recipe.unlock.enumerated().map { index, reference in
                try ingredient(for: reference, namespace: project.namespace, profile: profile, path: "content.recipes.\(recipe.id.rawValue).unlock.\(index)")
            }
            let document = ShapelessRecipeDocument(formatVersion: profile.recipeFormatVersion, recipe: .init(description: .init(identifier: identifier(for: recipe.id, namespace: project.namespace)), tags: recipe.tags, ingredients: ingredients, result: .init(item: resultIdentifier, count: recipe.result.count), unlock: unlock))
            entries.append(ZipArchiveEntry(path: "recipes/\(recipe.id.rawValue).json", data: try BedrockDocumentEncoder.encode(document)))
        }
        entries.append(
            ZipArchiveEntry(path: "pack_icon.png", data: PixelArtTextureRenderer.render(primaryVisual, pixelScale: 4))
        )
        return entries
    }

    private func resourcePackEntries(
        project: AddOnProject,
        profile: BedrockContentProfile
    ) throws -> [ZipArchiveEntry] {
        let version = project.buildVersion.components
        let resourcePackDisplayName = "\(project.displayName) Resources"
        let manifest = ManifestDocument(
            formatVersion: profile.manifestFormatVersion,
            header: ManifestDocument.Header(
                name: resourcePackDisplayName,
                description: "Generated by Craftberry",
                uuid: project.packUUIDs.resourceHeader.uuidString.lowercased(),
                version: version,
                minimumEngineVersion: profile.minimumEngineVersion.components
            ),
            modules: [ManifestDocument.Module(
                type: "resources",
                uuid: project.packUUIDs.resourceModule.uuidString.lowercased(),
                version: version
            )],
            dependencies: nil
        )
        var textureData: [String: ItemTextureDocument.Texture] = [:]
        var entries = [
            ZipArchiveEntry(path: "manifest.json", data: try BedrockDocumentEncoder.encode(manifest))
        ]
        var localizationLines: [String] = []
        for item in project.items.sorted(by: contentOrder) {
            let visual = try require(
                project.visualResources.first(where: { $0.id == item.visualResourceID }),
                profile: profile,
                code: "missing_visual_resource",
                path: "content.items.\(item.id.rawValue).visualResourceID",
                message: "Item \(item.id.rawValue) references a missing visual resource."
            )
            textureData[item.id.rawValue] = ItemTextureDocument.Texture(
                textures: "textures/items/\(item.id.rawValue)"
            )
            entries.append(
                ZipArchiveEntry(
                    path: "textures/items/\(item.id.rawValue).png",
                    data: PixelArtTextureRenderer.render(visual)
                )
            )
            localizationLines.append(
                "item.\(identifier(for: item.id, namespace: project.namespace)).name=\(item.displayName)"
            )
            if let armor = item.traits.armor {
                let attachable = AttachableDocument(
                    formatVersion: "1.8.0",
                    attachable: AttachableDocument.Attachable(
                        description: AttachableDocument.Description(
                            identifier: identifier(for: item.id, namespace: project.namespace),
                            materials: ["default": "armor", "enchanted": "armor_enchanted"],
                            textures: [
                                "default": "textures/models/armor/\(armor.layerResourceID.rawValue)",
                                "enchanted": "textures/misc/enchanted_actor_glint"
                            ],
                            geometry: ["default": armor.slot.geometry],
                            scripts: AttachableDocument.Scripts(parentSetup: "\(armor.slot.layerVariable) = 0.0;"),
                            renderControllers: ["controller.render.armor"]
                        )
                    )
                )
                entries.append(
                    ZipArchiveEntry(
                        path: "attachables/\(item.id.rawValue).json",
                        data: try BedrockDocumentEncoder.encode(attachable)
                    )
                )
            }
        }
        for layer in project.visualResources.filter({ $0.kind == .armorLayerOne || $0.kind == .armorLayerTwo }).sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
            entries.append(
                ZipArchiveEntry(
                    path: "textures/models/armor/\(layer.id.rawValue).png",
                    data: PixelArtTextureRenderer.render(layer)
                )
            )
        }
        // Block terrain tiles (16×16) — distinct from the 32×32 block-item sprites emitted above.
        for block in project.blocks.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
            if let terrain = project.visualResources.first(where: { $0.id == block.terrainResourceID }) {
                entries.append(
                    ZipArchiveEntry(
                        path: "textures/blocks/\(block.id.rawValue).png",
                        data: PixelArtTextureRenderer.render(terrain)
                    )
                )
            }
        }
        if !project.blocks.isEmpty {
            var terrainData: [String: TerrainTextureDocument.Texture] = [:]
            for block in project.blocks.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
                terrainData[block.id.rawValue] = TerrainTextureDocument.Texture(textures: "textures/blocks/\(block.id.rawValue)")
            }
            let terrainTexture = TerrainTextureDocument(
                resourcePackName: resourcePackDisplayName,
                textureName: "atlas.terrain",
                padding: 8,
                numMipLevels: 4,
                textureData: terrainData
            )
            entries.append(ZipArchiveEntry(path: "textures/terrain_texture.json", data: try BedrockDocumentEncoder.encode(terrainTexture)))
            var blockEntries: [String: BlocksDocument.Entry] = [:]
            for block in project.blocks.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
                let identifier = identifier(for: block.id, namespace: project.namespace)
                blockEntries[identifier] = BlocksDocument.Entry(textures: block.id.rawValue, sound: "stone")
            }
            let blocksDocument = BlocksDocument(entries: blockEntries)
            entries.append(ZipArchiveEntry(path: "blocks.json", data: try BedrockDocumentEncoder.encode(blocksDocument)))
        }
        let textureMap = ItemTextureDocument(
            resourcePackName: resourcePackDisplayName,
            textureData: textureData
        )
        entries.append(
            ZipArchiveEntry(
                path: "textures/item_texture.json",
                data: try BedrockDocumentEncoder.encode(textureMap)
            )
        )
        entries.append(
            ZipArchiveEntry(path: "texts/languages.json", data: try BedrockDocumentEncoder.encode(["en_US"]))
        )
        entries.append(
            ZipArchiveEntry(
                path: "texts/en_US.lang",
                data: Data((localizationLines.joined(separator: "\n") + "\n").utf8)
            )
        )
        entries.append(
            ZipArchiveEntry(
                path: "pack_icon.png",
                data: PixelArtTextureRenderer.render(try primaryVisualResource(project: project, profile: profile), pixelScale: 4)
            )
        )
        return entries
    }

    private func primaryVisualResource(
        project: AddOnProject,
        profile: BedrockContentProfile
    ) throws -> VisualResource {
        let item = try require(
            project.items.sorted(by: contentOrder).first,
            profile: profile,
            code: "missing_required_content",
            path: "content.items",
            message: "An add-on project must contain at least one item."
        )
        return try require(
            project.visualResources.first(where: { $0.id == item.visualResourceID }),
            profile: profile,
            code: "missing_visual_resource",
            path: "content.items.\(item.id.rawValue).visualResourceID",
            message: "Item \(item.id.rawValue) references a missing visual resource."
        )
    }

    private func ingredient(
        for reference: ContentReference,
        namespace: String,
        profile: BedrockContentProfile,
        path: String
    ) throws -> ShapedRecipeDocument.Ingredient {
        switch reference {
        case .vanilla(let identifier):
            return ShapedRecipeDocument.Ingredient(item: identifier)
        case .tag(let identifier):
            return ShapedRecipeDocument.Ingredient(tag: identifier)
        case .generated(let id):
            return ShapedRecipeDocument.Ingredient(item: self.identifier(for: id, namespace: namespace))
        }
    }

    private func resultIdentifier(
        for reference: ContentReference,
        namespace: String,
        profile: BedrockContentProfile,
        path: String
    ) throws -> String {
        switch reference {
        case .vanilla(let identifier): identifier
        case .generated(let id): self.identifier(for: id, namespace: namespace)
        case .tag:
            throw BedrockCompilationError.invalidProject(
                CompilationReport(
                    profileID: profile.id,
                    issues: [CompilationIssue(
                        severity: .error,
                        code: "tag_result_unsupported",
                        path: path,
                        message: "A recipe result cannot be a tag."
                    )]
                )
            )
        }
    }

    private func identifier(for id: ContentID, namespace: String) -> String {
        "\(namespace):\(id.rawValue)"
    }

    private func require<T>(
        _ value: T?,
        profile: BedrockContentProfile,
        code: String,
        path: String,
        message: String
    ) throws -> T {
        guard let value else {
            throw BedrockCompilationError.invalidProject(
                CompilationReport(
                    profileID: profile.id,
                    issues: [CompilationIssue(severity: .error, code: code, path: path, message: message)]
                )
            )
        }
        return value
    }

    private func contentOrder(_ lhs: ItemDefinition, _ rhs: ItemDefinition) -> Bool {
        lhs.id.rawValue < rhs.id.rawValue
    }

    private func recipeOrder(_ lhs: ShapedRecipeDefinition, _ rhs: ShapedRecipeDefinition) -> Bool {
        lhs.id.rawValue < rhs.id.rawValue
    }

    private func shapelessRecipeOrder(_ lhs: ShapelessRecipeDefinition, _ rhs: ShapelessRecipeDefinition) -> Bool {
        lhs.id.rawValue < rhs.id.rawValue
    }
}
