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
            // Crop blocks use growth states 0..(stages-1) validated against bedrock-samples 1.26.30.5 (921fafb0):
            // behavior_pack blocks use description.states with range {min,max} and permutations on query.block_state.
            // See resource_pack/blocks.json and metadata/json_schemas/server/block/1.21.110/States.json at 921fafb0.
            let growthStateKey = "craftberry:growth"
            let states: [String: BlockDocument.Description.StateValue]? = {
                guard let stages = block.growthStages else { return nil }
                return [growthStateKey: .init(values: .init(min: 0, max: stages - 1))]
            }()
            let permutations: [BlockDocument.Block.Permutation]? = {
                guard let stages = block.growthStages else { return nil }
                // Emit one permutation per growth stage to prove states wiring; keep components minimal.
                return (0..<stages).map { stage in
                    // Filter to that exact growth value; vanilla wheat uses similar query.block_state checks.
                    .init(condition: "query.block_state('\(growthStateKey)') == \(stage)", components: nil)
                }
            }()
            let document = BlockDocument(
                formatVersion: profile.blockFormatVersion,
                block: BlockDocument.Block(
                    description: BlockDocument.Description(
                        identifier: identifier,
                        menuCategory: BlockDocument.MenuCategory(category: "construction", group: "minecraft:itemGroup.name.blocks"),
                        states: states
                    ),
                    components: BlockDocument.Components(
                        destroyTime: block.destroyTime,
                        mapColor: BlockDocument.MapColor(color: block.mapColor),
                        lightDampening: 15,
                        loot: "loot_tables/blocks/\(block.id.rawValue).json"
                    ),
                    permutations: permutations
                )
            )
            entries.append(ZipArchiveEntry(path: "blocks/\(block.id.rawValue).json", data: try BedrockDocumentEncoder.encode(document)))
            // Ore loot drops the ingot; crop loot drops produce; storage self-drops. No worldgen features emitted:
            // feature placement (features/ + feature_rules/) would require scatter/ore placement configs not yet
            // stable against the pinned 921fafb0 samples without Blockception vendoring, so this slice stays block+loot only.
            let lootName: String = {
                if let dropID = block.lootDropID { return self.identifier(for: dropID, namespace: project.namespace) }
                return identifier
            }()
            let loot = LootTableDocument(pools: [LootTableDocument.Pool(rolls: 1, entries: [LootTableDocument.Entry(type: "item", name: lootName, weight: 1)])])
            entries.append(ZipArchiveEntry(path: "loot_tables/blocks/\(block.id.rawValue).json", data: try BedrockDocumentEncoder.encode(loot)))
        }
        for entity in project.entities.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
            let identifier = identifier(for: entity.id, namespace: project.namespace)
            let adultGroupName = "\(entity.id.rawValue)_adult"
            let babyGroupName = "\(entity.id.rawValue)_baby"
            let lootTablePath = "loot_tables/entities/\(entity.id.rawValue).json"
            let entityDocument = EntityDocument(
                formatVersion: profile.entityFormatVersion,
                entity: EntityDocument.Entity(
                    description: EntityDocument.Description(
                        identifier: identifier,
                        isSpawnable: true,
                        isSummonable: true,
                        spawnCategory: "creature"
                    ),
                    componentGroups: [
                        babyGroupName: EntityDocument.ComponentGroup(
                            isBaby: EntityDocument.EmptyComponent(),
                            scale: EntityDocument.Scale(value: 0.5),
                            ageable: EntityDocument.Ageable(
                                duration: 1200,
                                feedItems: ["wheat"],
                                growUp: EntityDocument.GrowUp(event: "minecraft:ageable_grow_up", target: "self")
                            ),
                            experienceReward: nil,
                            loot: nil,
                            breedable: nil
                        ),
                        adultGroupName: EntityDocument.ComponentGroup(
                            isBaby: nil,
                            scale: nil,
                            ageable: nil,
                            experienceReward: EntityDocument.ExperienceReward(onDeath: "query.last_hit_by_player ? Math.Random(1,3) : 0"),
                            loot: EntityDocument.Loot(table: lootTablePath),
                            breedable: EntityDocument.Breedable(
                                requireTame: false,
                                breedsWith: [identifier: EntityDocument.EmptyComponent()],
                                breedItems: ["wheat"]
                            )
                        )
                    ],
                    components: EntityDocument.Components(
                        typeFamily: EntityDocument.TypeFamily(family: [entity.id.rawValue, "mob"]),
                        breathable: EntityDocument.Breathable(totalSupply: 15, suffocateTime: 0),
                        collisionBox: EntityDocument.CollisionBox(width: 0.6, height: 0.8),
                        nameable: EntityDocument.EmptyComponent(),
                        health: EntityDocument.Health(value: entity.health, max: entity.health),
                        movement: EntityDocument.Movement(value: 0.25),
                        physics: EntityDocument.EmptyComponent(),
                        pushable: EntityDocument.Pushable(isPushable: true, isPushableByPiston: true),
                        scale: EntityDocument.Scale(value: entity.scale)
                    )
                )
            )
            entries.append(ZipArchiveEntry(path: "entities/\(entity.id.rawValue).json", data: try BedrockDocumentEncoder.encode(entityDocument)))
        }
        for rule in project.spawnRules.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
            let entity = try require(
                project.entities.first(where: { $0.id == rule.entityID }),
                profile: profile,
                code: "missing_spawn_rule_entity",
                path: "content.spawnRules.\(rule.id.rawValue).entityID",
                message: "Spawn rule references missing entity \(rule.entityID.rawValue)."
            )
            let identifier = identifier(for: entity.id, namespace: project.namespace)
            let spawnDocument = SpawnRuleDocument(
                formatVersion: profile.spawnRuleFormatVersion,
                spawnRules: SpawnRuleDocument.SpawnRules(
                    description: SpawnRuleDocument.Description(identifier: identifier, populationControl: "animal"),
                    conditions: [
                        SpawnRuleDocument.Condition(
                            spawnsOnSurface: SpawnRuleDocument.EmptyComponent(),
                            spawnsOnBlockFilter: "minecraft:grass_block",
                            brightnessFilter: SpawnRuleDocument.BrightnessFilter(min: 7, max: 15, adjustForWeather: false),
                            weight: SpawnRuleDocument.Weight(default: 10),
                            herd: SpawnRuleDocument.Herd(minSize: 2, maxSize: 4),
                            biomeFilter: SpawnRuleDocument.BiomeFilter(test: "has_biome_tag", operator: "==", value: "animal")
                        )
                    ]
                )
            )
            entries.append(ZipArchiveEntry(path: "spawn_rules/\(rule.id.rawValue).json", data: try BedrockDocumentEncoder.encode(spawnDocument)))
        }
        for loot in project.entityLootTables.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
            let entity = try require(
                project.entities.first(where: { $0.id == loot.entityID }),
                profile: profile,
                code: "missing_entity_loot_entity",
                path: "content.entityLootTables.\(loot.id.rawValue).entityID",
                message: "Entity loot references missing entity \(loot.entityID.rawValue)."
            )
            let lootItemName: String = {
                switch loot.item {
                case .vanilla(let id): return id
                case .generated(let contentID): return identifier(for: contentID, namespace: project.namespace)
                case .tag(let tag): return tag
                }
            }()
            let lootDocument = LootTableDocument(
                pools: [
                    LootTableDocument.Pool(
                        rolls: 1,
                        entries: [
                            LootTableDocument.Entry(type: "item", name: lootItemName, weight: 1)
                        ]
                    )
                ]
            )
            entries.append(ZipArchiveEntry(path: "loot_tables/entities/\(entity.id.rawValue).json", data: try BedrockDocumentEncoder.encode(lootDocument)))
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
        for recipe in project.furnaceRecipes.sorted(by: furnaceRecipeOrder) {
            let resultIdentifier = try resultIdentifier(for: recipe.result.item, namespace: project.namespace, profile: profile, path: "content.recipes.\(recipe.id.rawValue).result")
            let furnaceInput: FurnaceRecipeDocument.InputValue = {
                switch recipe.input {
                case .vanilla(let identifier): return .item(identifier)
                case .generated(let id): return .item(identifier(for: id, namespace: project.namespace))
                case .tag(let identifier): return .tag(identifier)
                }
            }()
            let unlock = try recipe.unlock.enumerated().map { index, reference in
                try ingredient(for: reference, namespace: project.namespace, profile: profile, path: "content.recipes.\(recipe.id.rawValue).unlock.\(index)")
            }
            let document = FurnaceRecipeDocument(
                formatVersion: profile.recipeFormatVersion,
                recipe: FurnaceRecipeDocument.Recipe(
                    description: ShapedRecipeDocument.Description(identifier: identifier(for: recipe.id, namespace: project.namespace)),
                    tags: recipe.tags,
                    input: furnaceInput,
                    output: resultIdentifier,
                    unlock: unlock
                )
            )
            entries.append(ZipArchiveEntry(path: "recipes/\(recipe.id.rawValue).json", data: try BedrockDocumentEncoder.encode(document)))
        }
        for recipe in project.smithingTrimRecipes.sorted(by: smithingTrimRecipeOrder) {
            let document = SmithingTrimRecipeDocument(
                formatVersion: profile.recipeFormatVersion,
                recipe: SmithingTrimRecipeDocument.Recipe(
                    description: ShapedRecipeDocument.Description(identifier: identifier(for: recipe.id, namespace: project.namespace)),
                    tags: recipe.tags,
                    template: smithingIngredient(for: recipe.template, namespace: project.namespace),
                    base: smithingIngredient(for: recipe.base, namespace: project.namespace),
                    addition: smithingIngredient(for: recipe.addition, namespace: project.namespace)
                )
            )
            entries.append(ZipArchiveEntry(path: "recipes/\(recipe.id.rawValue).json", data: try BedrockDocumentEncoder.encode(document)))
        }
        for recipe in project.smithingTransformRecipes.sorted(by: smithingTransformRecipeOrder) {
            let resultIdentifier = try resultIdentifier(for: recipe.result.item, namespace: project.namespace, profile: profile, path: "content.recipes.\(recipe.id.rawValue).result")
            let document = SmithingTransformRecipeDocument(
                formatVersion: profile.recipeFormatVersion,
                recipe: SmithingTransformRecipeDocument.Recipe(
                    description: ShapedRecipeDocument.Description(identifier: identifier(for: recipe.id, namespace: project.namespace)),
                    tags: recipe.tags,
                    template: smithingTransformIngredient(for: recipe.template, namespace: project.namespace),
                    base: smithingTransformIngredient(for: recipe.base, namespace: project.namespace),
                    addition: smithingTransformIngredient(for: recipe.addition, namespace: project.namespace),
                    result: resultIdentifier
                )
            )
            entries.append(ZipArchiveEntry(path: "recipes/\(recipe.id.rawValue).json", data: try BedrockDocumentEncoder.encode(document)))
        }
        for recipe in project.brewingMixRecipes.sorted(by: brewingMixRecipeOrder) {
            let inputString = try brewingString(for: recipe.input, namespace: project.namespace)
            let reagentString = try brewingString(for: recipe.reagent, namespace: project.namespace)
            let outputString = try brewingString(for: recipe.output, namespace: project.namespace)
            let document = BrewingMixRecipeDocument(
                formatVersion: profile.recipeFormatVersion,
                recipe: BrewingMixRecipeDocument.Recipe(
                    description: ShapedRecipeDocument.Description(identifier: identifier(for: recipe.id, namespace: project.namespace)),
                    tags: recipe.tags,
                    input: inputString,
                    reagent: reagentString,
                    output: outputString
                )
            )
            entries.append(ZipArchiveEntry(path: "recipes/\(recipe.id.rawValue).json", data: try BedrockDocumentEncoder.encode(document)))
        }
        for recipe in project.brewingContainerRecipes.sorted(by: brewingContainerRecipeOrder) {
            let inputString = try brewingString(for: recipe.input, namespace: project.namespace)
            let reagentString = try brewingString(for: recipe.reagent, namespace: project.namespace)
            let outputString = try brewingString(for: recipe.output, namespace: project.namespace)
            let document = BrewingContainerRecipeDocument(
                formatVersion: profile.recipeFormatVersion,
                recipe: BrewingContainerRecipeDocument.Recipe(
                    description: ShapedRecipeDocument.Description(identifier: identifier(for: recipe.id, namespace: project.namespace)),
                    tags: recipe.tags,
                    input: inputString,
                    reagent: reagentString,
                    output: outputString
                )
            )
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
        for entity in project.entities.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
            let identifier = identifier(for: entity.id, namespace: project.namespace)
            let spawnEggTextureName = entity.spawnEggResourceID.rawValue
            let clientEntity = ClientEntityDocument(
                formatVersion: profile.clientEntityFormatVersion,
                clientEntity: ClientEntityDocument.ClientEntity(
                    description: ClientEntityDocument.Description(
                        identifier: identifier,
                        materials: ["default": "entity_alphatest"],
                        textures: ["default": "textures/entity/\(entity.id.rawValue)"],
                        geometry: ["default": "geometry.pig"],
                        renderControllers: ["controller.render.pig"],
                        spawnEgg: ClientEntityDocument.SpawnEgg(texture: spawnEggTextureName)
                    )
                )
            )
            entries.append(
                ZipArchiveEntry(
                    path: "entity/\(entity.id.rawValue).entity.json",
                    data: try BedrockDocumentEncoder.encode(clientEntity)
                )
            )
            localizationLines.append("entity.\(identifier).name=\(entity.displayName)")
            localizationLines.append("item.spawn_egg.entity.\(identifier).name=\(entity.displayName) Spawn Egg")
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

    private func brewingMixRecipeOrder(_ lhs: BrewingMixRecipeDefinition, _ rhs: BrewingMixRecipeDefinition) -> Bool {
        lhs.id.rawValue < rhs.id.rawValue
    }

    private func brewingContainerRecipeOrder(_ lhs: BrewingContainerRecipeDefinition, _ rhs: BrewingContainerRecipeDefinition) -> Bool {
        lhs.id.rawValue < rhs.id.rawValue
    }

    private func furnaceRecipeOrder(_ lhs: FurnaceRecipeDefinition, _ rhs: FurnaceRecipeDefinition) -> Bool {
        lhs.id.rawValue < rhs.id.rawValue
    }

    private func smithingTrimRecipeOrder(_ lhs: SmithingTrimRecipeDefinition, _ rhs: SmithingTrimRecipeDefinition) -> Bool {
        lhs.id.rawValue < rhs.id.rawValue
    }

    private func smithingTransformRecipeOrder(_ lhs: SmithingTransformRecipeDefinition, _ rhs: SmithingTransformRecipeDefinition) -> Bool {
        lhs.id.rawValue < rhs.id.rawValue
    }

    private func brewingString(for reference: ContentReference, namespace: String) throws -> String {
        switch reference {
        case .vanilla(let identifier): return identifier
        case .generated(let id): return identifier(for: id, namespace: namespace)
        case .tag(let identifier): return identifier
        }
    }

    private func smithingIngredient(for reference: ContentReference, namespace: String) -> SmithingTrimRecipeDocument.IngredientValue {
        switch reference {
        case .vanilla(let identifier): .item(identifier)
        case .generated(let id): .item(identifier(for: id, namespace: namespace))
        case .tag(let identifier): .tag(identifier)
        }
    }

    private func smithingTransformIngredient(for reference: ContentReference, namespace: String) -> SmithingTransformRecipeDocument.IngredientValue {
        switch reference {
        case .vanilla(let identifier): .item(identifier)
        case .generated(let id): .item(identifier(for: id, namespace: namespace))
        case .tag(let identifier): .tag(identifier)
        }
    }
}
