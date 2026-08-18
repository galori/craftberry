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
        for structure in project.structures.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
            let structureIdentifier = identifier(for: structure.id, namespace: project.namespace)
            let blockIdentifier = identifier(for: structure.blockID, namespace: project.namespace)
            let mcData = try MCStructureEncoder.encodeHut(blockIdentifier: blockIdentifier, size: structure.size)
            entries.append(ZipArchiveEntry(path: "structures/\(structure.id.rawValue).mcstructure", data: mcData))

            let featureIdentifier = "\(structureIdentifier)_feature"
            let featureDocument = StructureTemplateFeatureDocument(
                formatVersion: "1.13.0",
                feature: .init(
                    description: .init(identifier: featureIdentifier),
                    structureName: structureIdentifier,
                    constraints: .init(grounded: .init(), unburied: .init()),
                    adjustmentRadius: 0
                )
            )
            entries.append(ZipArchiveEntry(path: "features/\(structure.id.rawValue)_feature.json", data: try BedrockDocumentEncoder.encode(featureDocument)))

            let ruleIdentifier = "\(structureIdentifier)_rule"
            let ruleDocument = FeatureRuleDocument(
                formatVersion: "1.13.0",
                rules: .init(
                    description: .init(identifier: ruleIdentifier, placesFeature: featureIdentifier),
                    conditions: .init(
                        placementPass: "surface_pass",
                        biomeFilter: [.init(test: "has_biome_tag", operator: "==", value: "plains")]
                    ),
                    distribution: .init(
                        iterations: 1,
                        x: .init(distribution: "uniform", extent: [0, 0]),
                        y: .init(distribution: "uniform", extent: [0, 0]),
                        z: .init(distribution: "uniform", extent: [0, 0])
                    )
                )
            )
            entries.append(ZipArchiveEntry(path: "feature_rules/\(structure.id.rawValue)_rule.json", data: try BedrockDocumentEncoder.encode(ruleDocument)))
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

public enum BedrockWorldGameMode: String, CaseIterable, Codable, Sendable {
    case creative
    case survival

    var levelDatValue: Int32 {
        switch self {
        case .creative: 1
        case .survival: 0
        }
    }
}

public struct BedrockWorldArtifact: Sendable {
    public let url: URL
    public let identifier: BedrockIdentifier
    public let fileName: String
    public let gameMode: BedrockWorldGameMode
    public let projectSidecarURL: URL

    public init(
        url: URL,
        identifier: BedrockIdentifier,
        fileName: String,
        gameMode: BedrockWorldGameMode,
        projectSidecarURL: URL
    ) {
        self.url = url
        self.identifier = identifier
        self.fileName = fileName
        self.gameMode = gameMode
        self.projectSidecarURL = projectSidecarURL
    }
}

public struct BedrockWorldCompilationResult: Sendable {
    public let artifact: BedrockWorldArtifact
    public let report: CompilationReport

    public init(artifact: BedrockWorldArtifact, report: CompilationReport) {
        self.artifact = artifact
        self.report = report
    }
}

public protocol AddOnWorldExporting: Sendable {
    func compileWorld(
        project: AddOnProject,
        addOn: BedrockCompilationResult,
        gameMode: BedrockWorldGameMode,
        outputDirectory: URL
    ) throws -> BedrockWorldCompilationResult
}

public enum BedrockWorldCompilationError: LocalizedError {
    case missingPack(String)
    case malformedPackManifest(String)

    public var errorDescription: String? {
        switch self {
        case .missingPack(let name): "The compiled add-on is missing its \(name) pack."
        case .malformedPackManifest(let name): "The compiled \(name) pack manifest is invalid."
        }
    }
}

public final class BedrockWorldExporter: AddOnWorldExporting, Sendable {
    private let templateEntries: [ZipArchiveEntry]

    public init(templateEntries: [ZipArchiveEntry]? = nil) {
        self.templateEntries = templateEntries ?? Self.loadBundledTemplateEntries()
    }

    public func compileWorld(
        project: AddOnProject,
        addOn: BedrockCompilationResult,
        gameMode: BedrockWorldGameMode,
        outputDirectory: URL
    ) throws -> BedrockWorldCompilationResult {
        let outerArchive = try ZipArchiveReader.readEntries(at: addOn.artifact.url)
        let behaviorArchive = try requirePack(named: "behavior", in: outerArchive)
        let resourceArchive = try requirePack(named: "resource", in: outerArchive)
        let behavior = try unpack(behaviorArchive)
        let resource = try unpack(resourceArchive)
        let behaviorManifest = try manifest(from: behavior, name: "behavior")
        let resourceManifest = try manifest(from: resource, name: "resource")

        let worldName = "\(project.displayName) (\(gameMode.rawValue.capitalized))"
        let templateLevelData = templateEntries.first { $0.path == "level.dat" }?.data
        let levelData = templateLevelData.map {
            patchLevelDat($0, worldName: worldName, gameMode: gameMode)
        } ?? makeLevelDat(project: project, profileVersion: addOn.report.profileID, gameMode: gameMode, worldName: worldName)
        var worldEntries = [
            ZipArchiveEntry(path: "level.dat", data: levelData),
            ZipArchiveEntry(path: "levelname.txt", data: Data(worldName.utf8)),
            ZipArchiveEntry(path: "world_behavior_packs.json", data: try packReferencesJSON(manifest: behaviorManifest)),
            ZipArchiveEntry(path: "world_resource_packs.json", data: try packReferencesJSON(manifest: resourceManifest))
        ]
        if let levelDataOld = templateEntries.first(where: { $0.path == "level.dat_old" })?.data {
            worldEntries.append(ZipArchiveEntry(
                path: "level.dat_old",
                data: patchLevelDat(levelDataOld, worldName: worldName, gameMode: gameMode)
            ))
        }
        worldEntries += templateEntries.filter { $0.path == "world_icon.jpeg" || $0.path.hasPrefix("db/") }
        worldEntries += behavior.map { ZipArchiveEntry(path: "behavior_packs/\(packDirectoryName(for: behaviorArchive.path))/\($0.path)", data: $0.data) }
            + resource.map { ZipArchiveEntry(path: "resource_packs/\(packDirectoryName(for: resourceArchive.path))/\($0.path)", data: $0.data) }
        if !worldEntries.contains(where: { $0.path == "db/CURRENT" }) {
            worldEntries += makeDatabaseEntries()
        }

        let archiveData = try ZipArchiveWriter.archive(entries: worldEntries)
        let worldURL = addOn.artifact.url.deletingPathExtension()
            .deletingLastPathComponent()
            .appending(path: "\(addOn.artifact.url.deletingPathExtension().lastPathComponent)_\(gameMode.rawValue).mcworld")
        try archiveData.write(to: worldURL, options: .atomic)

        return BedrockWorldCompilationResult(
            artifact: BedrockWorldArtifact(
                url: worldURL,
                identifier: addOn.artifact.identifier,
                fileName: worldURL.lastPathComponent,
                gameMode: gameMode,
                projectSidecarURL: addOn.artifact.projectSidecarURL
            ),
            report: CompilationReport(
                profileID: addOn.report.profileID,
                issues: addOn.report.issues,
                emittedFiles: addOn.report.emittedFiles + worldEntries.map(\.path).sorted()
            )
        )
    }

    private func requirePack(named kind: String, in archive: [ZipArchiveEntry]) throws -> ZipArchiveEntry {
        let suffix = kind == "resource" ? "_resources.mcpack" : "_behavior.mcpack"
        guard let pack = archive.first(where: { $0.path.hasSuffix(suffix) }) else {
            throw BedrockWorldCompilationError.missingPack(kind)
        }
        return pack
    }

    private func unpack(_ archive: ZipArchiveEntry) throws -> [ZipArchiveEntry] {
        try ZipArchiveReader.readEntries(data: archive.data)
    }

    private func manifest(from entries: [ZipArchiveEntry], name: String) throws -> PackManifest {
        guard let manifestEntry = entries.first(where: { $0.path == "manifest.json" }),
              let object = try JSONSerialization.jsonObject(with: manifestEntry.data) as? [String: Any],
              let header = object["header"] as? [String: Any],
              let uuid = header["uuid"] as? String
        else {
            throw BedrockWorldCompilationError.malformedPackManifest(name)
        }
        let version: [Int]?
        if let values = header["version"] as? [Int] {
            version = values
        } else if let values = header["version"] as? [NSNumber] {
            version = values.map { $0.intValue }
        } else {
            version = nil
        }
        guard let version else {
            throw BedrockWorldCompilationError.malformedPackManifest(name)
        }
        return PackManifest(uuid: uuid, version: version)
    }

    private func packReferencesJSON(manifest: PackManifest) throws -> Data {
        try JSONSerialization.data(withJSONObject: [["pack_id": manifest.uuid, "version": manifest.version]], options: [.sortedKeys])
    }

    private func packDirectoryName(for packPath: String) -> String {
        String(packPath.dropLast(".mcpack".count))
    }

    private static func loadBundledTemplateEntries() -> [ZipArchiveEntry] {
        guard let root = Bundle.main.url(forResource: "BedrockWorldTemplate", withExtension: nil),
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL, !url.hasDirectoryPath,
                  let data = try? Data(contentsOf: url) else {
                return nil
            }
            let rootComponents = root.standardizedFileURL.pathComponents
            let fileComponents = url.standardizedFileURL.pathComponents
            guard fileComponents.count > rootComponents.count else { return nil }
            let path = fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
            return ZipArchiveEntry(path: path, data: data)
        }
        .sorted { $0.path < $1.path }
    }

    private func patchLevelDat(
        _ data: Data,
        worldName: String,
        gameMode: BedrockWorldGameMode
    ) -> Data {
        var patched = data
        patched = replaceNBTString(named: "LevelName", with: worldName, in: patched)
        patched = replaceNBTInt(named: "GameType", with: Int32(gameMode.levelDatValue), in: patched)
        patched = replaceNBTByte(
            named: "hasBeenLoadedInCreative",
            with: gameMode == .creative ? 1 : 0,
            in: patched
        )
        // The template is an add-on playground. Keep commands available so the generated world
        // can be staged and inspected immediately after import, without requiring the user to
        // enable cheats and recreate the world before using the bundled packs.
        patched = replaceNBTByte(named: "commandsEnabled", with: 1, in: patched)
        patched = replaceNBTByte(named: "cheatsEnabled", with: 1, in: patched)
        guard patched.count >= 8 else { return patched }
        var size = Data()
        size.appendLittleEndian(UInt32(patched.count - 8))
        patched.replaceSubrange(4..<8, with: size)
        return patched
    }

    private func replaceNBTString(named name: String, with value: String, in data: Data) -> Data {
        let prefix = nbtTagPrefix(type: 8, name: name)
        guard let range = data.range(of: prefix),
              let valueLength = data.littleEndianUInt16(at: range.upperBound) else {
            return data
        }
        let valueStart = range.upperBound + 2
        let valueEnd = valueStart + Int(valueLength)
        guard valueEnd <= data.count else { return data }
        let valueData = Data(value.utf8)
        var replacement = Data()
        replacement.appendLittleEndian(UInt16(valueData.count))
        replacement.append(valueData)
        var patched = data
        patched.replaceSubrange(range.upperBound..<valueEnd, with: replacement)
        return patched
    }

    private func replaceNBTInt(named name: String, with value: Int32, in data: Data) -> Data {
        let prefix = nbtTagPrefix(type: 3, name: name)
        guard let range = data.range(of: prefix), range.upperBound + 4 <= data.count else {
            return data
        }
        var replacement = Data()
        replacement.appendLittleEndian(UInt32(bitPattern: value))
        var patched = data
        patched.replaceSubrange(range.upperBound..<(range.upperBound + 4), with: replacement)
        return patched
    }

    private func replaceNBTByte(named name: String, with value: UInt8, in data: Data) -> Data {
        let prefix = nbtTagPrefix(type: 1, name: name)
        guard let range = data.range(of: prefix), range.upperBound < data.count else {
            return data
        }
        var patched = data
        patched.replaceSubrange(range.upperBound..<(range.upperBound + 1), with: [value])
        return patched
    }

    private func nbtTagPrefix(type: UInt8, name: String) -> Data {
        var prefix = Data([type])
        prefix.appendLittleEndian(UInt16(name.utf8.count))
        prefix.append(Data(name.utf8))
        return prefix
    }

    private func makeDatabaseEntries() -> [ZipArchiveEntry] {
        var versionEdit = Data()
        versionEdit.append(1)
        appendVarint(UInt64("leveldb.BytewiseComparator".utf8.count), to: &versionEdit)
        versionEdit.append(contentsOf: Data("leveldb.BytewiseComparator".utf8))
        versionEdit.append(3)
        appendVarint(2, to: &versionEdit)
        versionEdit.append(4)
        appendVarint(0, to: &versionEdit)

        var manifest = Data()
        manifest.appendLittleEndian(maskedCRC32C(Data([1]) + versionEdit))
        manifest.appendLittleEndian(UInt16(versionEdit.count))
        manifest.append(1)
        manifest.append(versionEdit)

        return [
            ZipArchiveEntry(path: "db/CURRENT", data: Data("MANIFEST-000001\n".utf8)),
            ZipArchiveEntry(path: "db/MANIFEST-000001", data: manifest),
            ZipArchiveEntry(path: "db/000001.log", data: Data())
        ]
    }

    private func appendVarint(_ value: UInt64, to data: inout Data) {
        var value = value
        while value >= 0x80 {
            data.append(UInt8(value) | 0x80)
            value >>= 7
        }
        data.append(UInt8(value))
    }

    private func maskedCRC32C(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = crc & 1 == 1 ? (crc >> 1) ^ 0x82F6_3B78 : crc >> 1
            }
        }
        crc ^= 0xFFFF_FFFF
        return ((crc >> 15) | (crc << 17)) &+ 0xA282_EAD8
    }

    private func makeLevelDat(
        project: AddOnProject,
        profileVersion: String,
        gameMode: BedrockWorldGameMode,
        worldName: String
    ) -> Data {
        let version = profileVersion.split(separator: "-").last?.split(separator: ".").compactMap { Int($0) } ?? [1, 26, 30]
        let gameVersion = Array((version + [0, 0, 0]).prefix(5))
        let seedPart = Checksum.crc32(Data(project.id.uuidString.utf8))
        let seed = Int64(bitPattern: UInt64(seedPart) << 32 | UInt64(seedPart ^ 0xA5A5_A5A5))
        let versionString = version.map(String.init).joined(separator: ".")

        var nbt = Data()
        nbt.append(10)
        nbt.appendLittleEndian(UInt16(0))
        nbt.appendNBTString("BiomeOverride", "minecraft:plains")
        nbt.appendNBTByte("CenterMapsToOrigin", 0)
        nbt.appendNBTByte("ConfirmedPlatformLockedContent", 0)
        nbt.appendNBTInt("Difficulty", 1)
        nbt.appendNBTString("FlatWorldLayers", "{\"biome_id\":1,\"block_layers\":[{\"block_name\":\"minecraft:bedrock\",\"count\":1},{\"block_name\":\"minecraft:dirt\",\"count\":2},{\"block_name\":\"minecraft:grass_block\",\"count\":1}],\"encoding_version\":6,\"preset_id\":\"ClassicFlat\",\"world_version\":\"version.post_1_18\"}")
        nbt.appendNBTByte("ForceGameType", 0)
        nbt.appendNBTInt("GameType", gameMode.levelDatValue)
        nbt.appendNBTByte("HasUncompleteWorldFileOnDisk", 0)
        nbt.appendNBTString("InventoryVersion", versionString)
        nbt.appendNBTByte("IsHardcore", 0)
        nbt.appendNBTByte("LANBroadcast", 0)
        nbt.appendNBTByte("LANBroadcastIntent", 0)
        nbt.appendNBTInt("LimitedWorldOriginX", 0)
        nbt.appendNBTInt("LimitedWorldOriginY", 64)
        nbt.appendNBTInt("LimitedWorldOriginZ", 0)
        nbt.appendNBTInt("NetherScale", 8)
        nbt.appendNBTInt("NetworkVersion", 2168)
        nbt.appendNBTInt("Platform", 2)
        nbt.appendNBTInt("PlatformBroadcastIntent", 2)
        nbt.appendNBTByte("PlayerHasDied", 0)
        nbt.appendNBTByte("SpawnV1Villagers", 0)
        nbt.appendNBTInt("WorldVersion", 1)
        nbt.appendNBTInt("XBLBroadcastIntent", 2)
        nbt.appendNBTInt("Generator", 1)
        nbt.appendNBTInt("SpawnX", 0)
        nbt.appendNBTInt("SpawnY", 64)
        nbt.appendNBTInt("SpawnZ", 0)
        nbt.appendNBTString("LevelName", worldName)
        nbt.appendNBTLong("RandomSeed", seed)
        nbt.appendNBTLong("LastPlayed", 0)
        nbt.appendNBTLong("Time", 0)
        nbt.appendNBTInt("StorageVersion", 10)
        nbt.appendNBTString("baseGameVersion", versionString)
        nbt.appendNBTListInt("lastOpenedWithVersion", gameVersion)
        nbt.appendNBTListInt("MinimumCompatibleClientVersion", gameVersion)
        nbt.appendNBTByte("hasBeenLoadedInCreative", gameMode == .creative ? 1 : 0)
        nbt.appendNBTByte("hasLockedBehaviorPack", 1)
        nbt.appendNBTByte("hasLockedResourcePack", 1)
        nbt.appendNBTByte("spawnMobs", 1)
        nbt.appendNBTByte("texturePacksRequired", 0)
        nbt.appendNBTByte("MultiplayerGame", 0)
        nbt.appendNBTByte("MultiplayerGameIntent", 0)
        nbt.append(0)

        var output = Data()
        output.appendLittleEndian(UInt32(10))
        output.appendLittleEndian(UInt32(nbt.count))
        output.append(nbt)
        return output
    }
}

private struct PackManifest {
    let uuid: String
    let version: [Int]
}

private extension Data {
    mutating func appendNBTName(_ name: String) {
        let data = Data(name.utf8)
        appendLittleEndian(UInt16(data.count))
        append(data)
    }

    mutating func appendNBTInt(_ name: String, _ value: Int32) {
        append(3)
        appendNBTName(name)
        appendLittleEndian(UInt32(bitPattern: value))
    }

    mutating func appendNBTByte(_ name: String, _ value: UInt8) {
        append(1)
        appendNBTName(name)
        append(value)
    }

    mutating func appendNBTLong(_ name: String, _ value: Int64) {
        append(4)
        appendNBTName(name)
        let raw = UInt64(bitPattern: value)
        appendLittleEndian(UInt32(truncatingIfNeeded: raw))
        appendLittleEndian(UInt32(truncatingIfNeeded: raw >> 32))
    }

    mutating func appendNBTString(_ name: String, _ value: String) {
        append(8)
        appendNBTName(name)
        let data = Data(value.utf8)
        appendLittleEndian(UInt16(data.count))
        append(data)
    }

    mutating func appendNBTListInt(_ name: String, _ values: [Int]) {
        append(9)
        appendNBTName(name)
        append(3)
        appendLittleEndian(UInt32(values.count))
        for value in values {
            appendLittleEndian(UInt32(bitPattern: Int32(value)))
        }
    }
}
