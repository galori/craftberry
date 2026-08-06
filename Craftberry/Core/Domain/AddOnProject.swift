import Foundation

public struct ContentID: RawRepresentable, Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

public struct PackUUIDs: Codable, Equatable, Sendable {
    public let behaviorHeader: UUID
    public let behaviorModule: UUID
    public let resourceHeader: UUID
    public let resourceModule: UUID

    public init(behaviorHeader: UUID, behaviorModule: UUID, resourceHeader: UUID, resourceModule: UUID) {
        self.behaviorHeader = behaviorHeader
        self.behaviorModule = behaviorModule
        self.resourceHeader = resourceHeader
        self.resourceModule = resourceModule
    }
}

public struct AddOnProjectIdentity: Codable, Equatable, Sendable {
    public let projectID: UUID
    public let namespace: String
    public let contentSuffix: String
    public let packUUIDs: PackUUIDs

    public init(projectID: UUID, namespace: String, contentSuffix: String, packUUIDs: PackUUIDs) {
        self.projectID = projectID
        self.namespace = namespace
        self.contentSuffix = contentSuffix
        self.packUUIDs = packUUIDs
    }

    public static func generate(
        namespace: String = "craftberry",
        suffixGenerator: @Sendable () -> String = { String(UUID().uuidString.prefix(6)).lowercased() },
        uuidGenerator: @Sendable () -> UUID = { UUID() }
    ) -> AddOnProjectIdentity {
        AddOnProjectIdentity(
            projectID: uuidGenerator(),
            namespace: namespace,
            contentSuffix: suffixGenerator(),
            packUUIDs: PackUUIDs(
                behaviorHeader: uuidGenerator(),
                behaviorModule: uuidGenerator(),
                resourceHeader: uuidGenerator(),
                resourceModule: uuidGenerator()
            )
        )
    }
}

public enum ContentReference: Codable, Equatable, Hashable, Sendable {
    case vanilla(String)
    case tag(String)
    case generated(ContentID)

    private enum CodingKeys: String, CodingKey { case kind, value }
    private enum Kind: String, Codable { case vanilla, tag, generated }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .kind) {
        case .vanilla: self = .vanilla(try values.decode(String.self, forKey: .value))
        case .tag: self = .tag(try values.decode(String.self, forKey: .value))
        case .generated: self = .generated(try values.decode(ContentID.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .vanilla(let identifier):
            try values.encode(Kind.vanilla, forKey: .kind)
            try values.encode(identifier, forKey: .value)
        case .tag(let identifier):
            try values.encode(Kind.tag, forKey: .kind)
            try values.encode(identifier, forKey: .value)
        case .generated(let id):
            try values.encode(Kind.generated, forKey: .kind)
            try values.encode(id, forKey: .value)
        }
    }
}

public struct CombatTrait: Codable, Equatable, Sendable {
    public let attackBonus: Int

    public init(attackBonus: Int) {
        self.attackBonus = attackBonus
    }
}

public struct DurabilityTrait: Codable, Equatable, Sendable {
    public let maximum: Int

    public init(maximum: Int) {
        self.maximum = maximum
    }
}

public struct ItemTraits: Codable, Equatable, Sendable {
    public let combat: CombatTrait?
    public let durability: DurabilityTrait?
    public let handEquipped: Bool
    public let maximumStackSize: Int

    public init(
        combat: CombatTrait? = nil,
        durability: DurabilityTrait? = nil,
        handEquipped: Bool = false,
        maximumStackSize: Int = 64
    ) {
        self.combat = combat
        self.durability = durability
        self.handEquipped = handEquipped
        self.maximumStackSize = maximumStackSize
    }
}

public enum ItemMenuCategory: String, Codable, Sendable {
    case equipment
    case items
}

public struct ItemDefinition: Codable, Equatable, Sendable {
    public let id: ContentID
    public let displayName: String
    public let menuCategory: ItemMenuCategory
    public let menuGroup: String
    public let traits: ItemTraits
    public let visualResourceID: ContentID

    public init(
        id: ContentID,
        displayName: String,
        menuCategory: ItemMenuCategory,
        menuGroup: String,
        traits: ItemTraits,
        visualResourceID: ContentID
    ) {
        self.id = id
        self.displayName = displayName
        self.menuCategory = menuCategory
        self.menuGroup = menuGroup
        self.traits = traits
        self.visualResourceID = visualResourceID
    }
}

public struct RecipeResult: Codable, Equatable, Sendable {
    public let item: ContentReference
    public let count: Int

    public init(item: ContentReference, count: Int) {
        self.item = item
        self.count = count
    }
}

public struct ShapedRecipeDefinition: Codable, Equatable, Sendable {
    public let id: ContentID
    public let tags: [String]
    public let pattern: [String]
    public let ingredients: [String: ContentReference]
    public let result: RecipeResult
    public let unlock: [ContentReference]

    public init(
        id: ContentID,
        tags: [String],
        pattern: [String],
        ingredients: [String: ContentReference],
        result: RecipeResult,
        unlock: [ContentReference]
    ) {
        self.id = id
        self.tags = tags
        self.pattern = pattern
        self.ingredients = ingredients
        self.result = result
        self.unlock = unlock
    }
}

public struct ShapelessRecipeDefinition: Codable, Equatable, Sendable {
    public let id: ContentID
    public let tags: [String]
    public let ingredients: [ContentReference]
    public let result: RecipeResult
    public let unlock: [ContentReference]

    public init(id: ContentID, tags: [String], ingredients: [ContentReference], result: RecipeResult, unlock: [ContentReference]) {
        self.id = id
        self.tags = tags
        self.ingredients = ingredients
        self.result = result
        self.unlock = unlock
    }
}

public enum VisualResourceKind: String, Codable, Sendable, CaseIterable {
    case swordPixelArt
    case ingotPixelArt
    case pickaxePixelArt
    case axePixelArt
    case shovelPixelArt
    case hoePixelArt
    case daggerPixelArt
    case spearPixelArt
    case hammerPixelArt
}

public struct VisualResource: Codable, Equatable, Sendable {
    public let id: ContentID
    public let kind: VisualResourceKind
    public let color: PixelArtColor

    public init(id: ContentID, kind: VisualResourceKind, color: PixelArtColor) {
        self.id = id
        self.kind = kind
        self.color = color
    }
}

public enum AddOnContentNode: Codable, Equatable, Sendable {
    case item(ItemDefinition)
    case shapedRecipe(ShapedRecipeDefinition)
    case shapelessRecipe(ShapelessRecipeDefinition)
    case visualResource(VisualResource)

    private enum CodingKeys: String, CodingKey { case type, value }
    private enum Kind: String, Codable { case item, shapedRecipe, shapelessRecipe, visualResource }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .type) {
        case .item: self = .item(try values.decode(ItemDefinition.self, forKey: .value))
        case .shapedRecipe: self = .shapedRecipe(try values.decode(ShapedRecipeDefinition.self, forKey: .value))
        case .shapelessRecipe: self = .shapelessRecipe(try values.decode(ShapelessRecipeDefinition.self, forKey: .value))
        case .visualResource: self = .visualResource(try values.decode(VisualResource.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .item(let item):
            try values.encode(Kind.item, forKey: .type)
            try values.encode(item, forKey: .value)
        case .shapedRecipe(let recipe):
            try values.encode(Kind.shapedRecipe, forKey: .type)
            try values.encode(recipe, forKey: .value)
        case .shapelessRecipe(let recipe):
            try values.encode(Kind.shapelessRecipe, forKey: .type)
            try values.encode(recipe, forKey: .value)
        case .visualResource(let resource):
            try values.encode(Kind.visualResource, forKey: .type)
            try values.encode(resource, forKey: .value)
        }
    }
}

public struct AddOnProject: Codable, Equatable, Sendable, Identifiable {
    public static let currentSchemaVersion = 3

    public let schemaVersion: Int
    public let id: UUID
    public let namespace: String
    public let displayName: String
    public let shortDescription: String
    public let packUUIDs: PackUUIDs
    public let buildVersion: VersionTriplet
    public let targetProfileID: String
    public let originalPrompt: String
    public let content: [AddOnContentNode]

    public init(
        schemaVersion: Int = AddOnProject.currentSchemaVersion,
        id: UUID,
        namespace: String,
        displayName: String,
        shortDescription: String? = nil,
        packUUIDs: PackUUIDs,
        buildVersion: VersionTriplet,
        targetProfileID: String,
        originalPrompt: String,
        content: [AddOnContentNode]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.namespace = namespace
        self.displayName = displayName
        self.shortDescription = Self.normalizedShortDescription(shortDescription, displayName: displayName, content: content)
        self.packUUIDs = packUUIDs
        self.buildVersion = buildVersion
        self.targetProfileID = targetProfileID
        self.originalPrompt = originalPrompt
        self.content = content
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, namespace, displayName, shortDescription, packUUIDs, buildVersion, targetProfileID, originalPrompt, content
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        let displayName = try values.decode(String.self, forKey: .displayName)
        let content = try values.decode([AddOnContentNode].self, forKey: .content)
        self.init(
            schemaVersion: schemaVersion,
            id: try values.decode(UUID.self, forKey: .id),
            namespace: try values.decode(String.self, forKey: .namespace),
            displayName: displayName,
            shortDescription: try values.decodeIfPresent(String.self, forKey: .shortDescription),
            packUUIDs: try values.decode(PackUUIDs.self, forKey: .packUUIDs),
            buildVersion: try values.decode(VersionTriplet.self, forKey: .buildVersion),
            targetProfileID: try values.decode(String.self, forKey: .targetProfileID),
            originalPrompt: try values.decode(String.self, forKey: .originalPrompt),
            content: content
        )
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(id, forKey: .id)
        try values.encode(namespace, forKey: .namespace)
        try values.encode(displayName, forKey: .displayName)
        try values.encode(shortDescription, forKey: .shortDescription)
        try values.encode(packUUIDs, forKey: .packUUIDs)
        try values.encode(buildVersion, forKey: .buildVersion)
        try values.encode(targetProfileID, forKey: .targetProfileID)
        try values.encode(originalPrompt, forKey: .originalPrompt)
        try values.encode(content, forKey: .content)
    }

    public var items: [ItemDefinition] {
        content.compactMap { if case .item(let item) = $0 { item } else { nil } }
    }

    public var recipes: [ShapedRecipeDefinition] {
        content.compactMap { if case .shapedRecipe(let recipe) = $0 { recipe } else { nil } }
    }

    public var shapelessRecipes: [ShapelessRecipeDefinition] {
        content.compactMap { if case .shapelessRecipe(let recipe) = $0 { recipe } else { nil } }
    }

    public var allRecipeIDs: [ContentID] { recipes.map(\.id) + shapelessRecipes.map(\.id) }

    public var visualResources: [VisualResource] {
        content.compactMap { if case .visualResource(let resource) = $0 { resource } else { nil } }
    }

    public func migratedToCurrentSchema() throws -> AddOnProject {
        guard schemaVersion <= Self.currentSchemaVersion else { throw AddOnProjectError.unsupportedProjectSchema(schemaVersion) }
        guard schemaVersion != Self.currentSchemaVersion else { return self }
        return AddOnProject(schemaVersion: Self.currentSchemaVersion, id: id, namespace: namespace, displayName: displayName, shortDescription: shortDescription, packUUIDs: packUUIDs, buildVersion: buildVersion, targetProfileID: targetProfileID, originalPrompt: originalPrompt, content: content)
    }

    public static func sword(
        displayName: String,
        color: PixelArtColor = .blue,
        attackBonus: Int = 10,
        durability: Int = 500,
        craftingIngredient: String = "minecraft:diamond",
        shortDescription: String? = nil,
        originalPrompt: String,
        identity: AddOnProjectIdentity = .generate(),
        profile: BedrockContentProfile = .current
    ) throws -> AddOnProject {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw AddOnProjectError.emptyDisplayName }
        guard trimmedName.count <= 32 else { throw AddOnProjectError.displayNameTooLong }
        guard (1...30).contains(attackBonus) else { throw AddOnProjectError.invalidAttackBonus }
        guard (50...2_000).contains(durability) else { throw AddOnProjectError.invalidDurability }
        guard profile.vanillaItemIdentifiers.contains(craftingIngredient) else {
            throw AddOnProjectError.unsupportedVanillaItem(craftingIngredient)
        }
        let contentID = ContentID(
            BedrockIdentifier.make(displayName: trimmedName, suffix: identity.contentSuffix).pathComponent
        )
        let item = ItemDefinition(
            id: contentID,
            displayName: trimmedName,
            menuCategory: .equipment,
            menuGroup: "minecraft:itemGroup.name.sword",
            traits: ItemTraits(
                combat: CombatTrait(attackBonus: attackBonus),
                durability: DurabilityTrait(maximum: durability),
                handEquipped: true,
                maximumStackSize: 1
            ),
            visualResourceID: contentID
        )
        let recipe = ShapedRecipeDefinition(
            id: ContentID("\(contentID.rawValue)_recipe"),
            tags: ["crafting_table"],
            pattern: [" M ", " M ", " S "],
            ingredients: [
                "M": .vanilla(craftingIngredient),
                "S": .vanilla("minecraft:stick")
            ],
            result: RecipeResult(item: .generated(contentID), count: 1),
            unlock: [.vanilla(craftingIngredient)]
        )
        let visual = VisualResource(id: contentID, kind: .swordPixelArt, color: color)
        return AddOnProject(
            id: identity.projectID,
            namespace: identity.namespace,
            displayName: trimmedName,
            shortDescription: shortDescription,
            packUUIDs: identity.packUUIDs,
            buildVersion: VersionTriplet(major: 1, minor: 0, patch: 0),
            targetProfileID: profile.id,
            originalPrompt: originalPrompt,
            content: [.item(item), .shapedRecipe(recipe), .visualResource(visual)]
        )
    }

    public static func materialSwordSet(
        materialName: String = "Azure",
        color: PixelArtColor = .blue,
        sourceItem: String = "minecraft:diamond",
        sourceCount: Int = 4,
        swordDisplayName: String? = nil,
        attackBonus: Int = 10,
        durability: Int = 500,
        shortDescription: String? = nil,
        originalPrompt: String,
        identity: AddOnProjectIdentity = .generate(),
        profile: BedrockContentProfile = .current
    ) throws -> AddOnProject {
        let material = materialName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !material.isEmpty else { throw AddOnProjectError.emptyDisplayName }
        guard material.count <= 24 else { throw AddOnProjectError.displayNameTooLong }
        guard (1...9).contains(sourceCount) else { throw AddOnProjectError.invalidIngredientCount }
        guard (1...30).contains(attackBonus) else { throw AddOnProjectError.invalidAttackBonus }
        guard (50...2_000).contains(durability) else { throw AddOnProjectError.invalidDurability }
        guard profile.materialSourceIdentifiers.contains(sourceItem) else { throw AddOnProjectError.unsupportedVanillaItem(sourceItem) }
        let stem = BedrockIdentifier.make(displayName: material, suffix: identity.contentSuffix).pathComponent
        let ingotID = ContentID("\(stem)_ingot")
        let swordID = ContentID("\(stem)_sword")
        let ingot = ItemDefinition(id: ingotID, displayName: "\(material) Ingot", menuCategory: .items, menuGroup: "minecraft:itemGroup.name.ingot", traits: ItemTraits(), visualResourceID: ingotID)
        let sword = ItemDefinition(id: swordID, displayName: swordDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "\(material) Sword", menuCategory: .equipment, menuGroup: "minecraft:itemGroup.name.sword", traits: ItemTraits(combat: CombatTrait(attackBonus: attackBonus), durability: DurabilityTrait(maximum: durability), handEquipped: true, maximumStackSize: 1), visualResourceID: swordID)
        let ingotRecipe = ShapelessRecipeDefinition(id: ContentID("\(stem)_ingot_recipe"), tags: ["crafting_table"], ingredients: Array(repeating: .vanilla(sourceItem), count: sourceCount), result: RecipeResult(item: .generated(ingotID), count: 1), unlock: [.vanilla(sourceItem)])
        let swordRecipe = ShapedRecipeDefinition(id: ContentID("\(stem)_sword_recipe"), tags: ["crafting_table"], pattern: [" I ", " I ", " S "], ingredients: ["I": .generated(ingotID), "S": .vanilla("minecraft:stick")], result: RecipeResult(item: .generated(swordID), count: 1), unlock: [.generated(ingotID)])
        return AddOnProject(id: identity.projectID, namespace: identity.namespace, displayName: material, shortDescription: shortDescription, packUUIDs: identity.packUUIDs, buildVersion: VersionTriplet(major: 1, minor: 0, patch: 0), targetProfileID: profile.id, originalPrompt: originalPrompt, content: [.item(ingot), .item(sword), .shapelessRecipe(ingotRecipe), .shapedRecipe(swordRecipe), .visualResource(VisualResource(id: ingotID, kind: .ingotPixelArt, color: color)), .visualResource(VisualResource(id: swordID, kind: .swordPixelArt, color: color))])
    }

    public static func materialToolSet(
        materialName: String = "Azure",
        color: PixelArtColor = .blue,
        sourceItem: String = "minecraft:diamond",
        sourceCount: Int = 4,
        attackBonus: Int = 10,
        durability: Int = 500,
        shortDescription: String? = nil,
        originalPrompt: String,
        identity: AddOnProjectIdentity = .generate(),
        profile: BedrockContentProfile = .current
    ) throws -> AddOnProject {
        let material = materialName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !material.isEmpty else { throw AddOnProjectError.emptyDisplayName }
        guard material.count <= 24 else { throw AddOnProjectError.displayNameTooLong }
        guard (1...9).contains(sourceCount) else { throw AddOnProjectError.invalidIngredientCount }
        guard (1...30).contains(attackBonus) else { throw AddOnProjectError.invalidAttackBonus }
        guard (50...2_000).contains(durability) else { throw AddOnProjectError.invalidDurability }
        guard profile.materialSourceIdentifiers.contains(sourceItem) else { throw AddOnProjectError.unsupportedVanillaItem(sourceItem) }

        let stem = BedrockIdentifier.make(displayName: material, suffix: identity.contentSuffix).pathComponent
        let ingotID = ContentID("\(stem)_ingot")
        let ingot = ItemDefinition(
            id: ingotID,
            displayName: "\(material) Ingot",
            menuCategory: .items,
            menuGroup: "minecraft:itemGroup.name.ingot",
            traits: ItemTraits(),
            visualResourceID: ingotID
        )
        let toolSpecs: [MaterialToolSpec] = [
            MaterialToolSpec(suffix: "sword", displayName: "\(material) Sword", menuGroup: "minecraft:itemGroup.name.sword", visualKind: .swordPixelArt, pattern: [" I ", " I ", " S "], attackBonus: attackBonus),
            MaterialToolSpec(suffix: "pickaxe", displayName: "\(material) Pickaxe", menuGroup: "minecraft:itemGroup.name.pickaxe", visualKind: .pickaxePixelArt, pattern: ["III", " S ", " S "], attackBonus: max(1, attackBonus - 4)),
            MaterialToolSpec(suffix: "axe", displayName: "\(material) Axe", menuGroup: "minecraft:itemGroup.name.axe", visualKind: .axePixelArt, pattern: ["II ", "IS ", " S "], attackBonus: max(1, attackBonus - 2)),
            MaterialToolSpec(suffix: "shovel", displayName: "\(material) Shovel", menuGroup: "minecraft:itemGroup.name.shovel", visualKind: .shovelPixelArt, pattern: [" I ", " S ", " S "], attackBonus: max(1, attackBonus - 5)),
            MaterialToolSpec(suffix: "hoe", displayName: "\(material) Hoe", menuGroup: "minecraft:itemGroup.name.hoe", visualKind: .hoePixelArt, pattern: ["II ", " S ", " S "], attackBonus: max(1, attackBonus - 7))
        ]
        let tools = toolSpecs.map { spec in
            let id = ContentID("\(stem)_\(spec.suffix)")
            return ItemDefinition(
                id: id,
                displayName: spec.displayName,
                menuCategory: .equipment,
                menuGroup: spec.menuGroup,
                traits: ItemTraits(
                    combat: CombatTrait(attackBonus: spec.attackBonus),
                    durability: DurabilityTrait(maximum: durability),
                    handEquipped: true,
                    maximumStackSize: 1
                ),
                visualResourceID: id
            )
        }
        let ingotRecipe = ShapelessRecipeDefinition(
            id: ContentID("\(stem)_ingot_recipe"),
            tags: ["crafting_table"],
            ingredients: Array(repeating: .vanilla(sourceItem), count: sourceCount),
            result: RecipeResult(item: .generated(ingotID), count: 1),
            unlock: [.vanilla(sourceItem)]
        )
        let toolRecipes = zip(toolSpecs, tools).map { spec, item in
            ShapedRecipeDefinition(
                id: ContentID("\(item.id.rawValue)_recipe"),
                tags: ["crafting_table"],
                pattern: spec.pattern,
                ingredients: ["I": .generated(ingotID), "S": .vanilla("minecraft:stick")],
                result: RecipeResult(item: .generated(item.id), count: 1),
                unlock: [.generated(ingotID)]
            )
        }
        let visuals = [VisualResource(id: ingotID, kind: .ingotPixelArt, color: color)] + zip(toolSpecs, tools).map { spec, item in
            VisualResource(id: item.id, kind: spec.visualKind, color: color)
        }
        return AddOnProject(
            id: identity.projectID,
            namespace: identity.namespace,
            displayName: material,
            shortDescription: shortDescription,
            packUUIDs: identity.packUUIDs,
            buildVersion: VersionTriplet(major: 1, minor: 0, patch: 0),
            targetProfileID: profile.id,
            originalPrompt: originalPrompt,
            content: [.item(ingot)] + tools.map(AddOnContentNode.item) + [.shapelessRecipe(ingotRecipe)] + toolRecipes.map(AddOnContentNode.shapedRecipe) + visuals.map(AddOnContentNode.visualResource)
        )
    }

    public static func materialWeaponSet(
        materialName: String = "Azure",
        color: PixelArtColor = .blue,
        sourceItem: String = "minecraft:diamond",
        sourceCount: Int = 4,
        attackBonus: Int = 10,
        durability: Int = 500,
        shortDescription: String? = nil,
        originalPrompt: String,
        identity: AddOnProjectIdentity = .generate(),
        profile: BedrockContentProfile = .current
    ) throws -> AddOnProject {
        let material = materialName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !material.isEmpty else { throw AddOnProjectError.emptyDisplayName }
        guard material.count <= 24 else { throw AddOnProjectError.displayNameTooLong }
        guard (1...9).contains(sourceCount) else { throw AddOnProjectError.invalidIngredientCount }
        guard (1...30).contains(attackBonus) else { throw AddOnProjectError.invalidAttackBonus }
        guard (50...2_000).contains(durability) else { throw AddOnProjectError.invalidDurability }
        guard profile.materialSourceIdentifiers.contains(sourceItem) else { throw AddOnProjectError.unsupportedVanillaItem(sourceItem) }

        let stem = BedrockIdentifier.make(displayName: material, suffix: identity.contentSuffix).pathComponent
        let ingotID = ContentID("\(stem)_ingot")
        let ingot = ItemDefinition(
            id: ingotID,
            displayName: "\(material) Ingot",
            menuCategory: .items,
            menuGroup: "minecraft:itemGroup.name.ingot",
            traits: ItemTraits(),
            visualResourceID: ingotID
        )
        let weaponSpecs: [MaterialWeaponSpec] = [
            MaterialWeaponSpec(suffix: "sword", displayName: "\(material) Sword", menuGroup: "minecraft:itemGroup.name.sword", visualKind: .swordPixelArt, pattern: [" I ", " I ", " S "], attackBonus: attackBonus),
            MaterialWeaponSpec(suffix: "dagger", displayName: "\(material) Dagger", menuGroup: "minecraft:itemGroup.name.sword", visualKind: .daggerPixelArt, pattern: [" I ", " S "], attackBonus: max(1, attackBonus - 3)),
            MaterialWeaponSpec(suffix: "spear", displayName: "\(material) Spear", menuGroup: "minecraft:itemGroup.name.sword", visualKind: .spearPixelArt, pattern: ["  I", " S ", "S  "], attackBonus: max(1, attackBonus - 1)),
            MaterialWeaponSpec(suffix: "hammer", displayName: "\(material) Hammer", menuGroup: "minecraft:itemGroup.name.sword", visualKind: .hammerPixelArt, pattern: ["III", " S ", " S "], attackBonus: min(30, attackBonus + 3))
        ]
        let weapons = weaponSpecs.map { spec in
            let id = ContentID("\(stem)_\(spec.suffix)")
            return ItemDefinition(
                id: id,
                displayName: spec.displayName,
                menuCategory: .equipment,
                menuGroup: spec.menuGroup,
                traits: ItemTraits(
                    combat: CombatTrait(attackBonus: spec.attackBonus),
                    durability: DurabilityTrait(maximum: durability),
                    handEquipped: true,
                    maximumStackSize: 1
                ),
                visualResourceID: id
            )
        }
        let ingotRecipe = ShapelessRecipeDefinition(
            id: ContentID("\(stem)_ingot_recipe"),
            tags: ["crafting_table"],
            ingredients: Array(repeating: .vanilla(sourceItem), count: sourceCount),
            result: RecipeResult(item: .generated(ingotID), count: 1),
            unlock: [.vanilla(sourceItem)]
        )
        let weaponRecipes = zip(weaponSpecs, weapons).map { spec, item in
            ShapedRecipeDefinition(
                id: ContentID("\(item.id.rawValue)_recipe"),
                tags: ["crafting_table"],
                pattern: spec.pattern,
                ingredients: ["I": .generated(ingotID), "S": .vanilla("minecraft:stick")],
                result: RecipeResult(item: .generated(item.id), count: 1),
                unlock: [.generated(ingotID)]
            )
        }
        let visuals = [VisualResource(id: ingotID, kind: .ingotPixelArt, color: color)] + zip(weaponSpecs, weapons).map { spec, item in
            VisualResource(id: item.id, kind: spec.visualKind, color: color)
        }
        return AddOnProject(
            id: identity.projectID,
            namespace: identity.namespace,
            displayName: material,
            shortDescription: shortDescription,
            packUUIDs: identity.packUUIDs,
            buildVersion: VersionTriplet(major: 1, minor: 0, patch: 0),
            targetProfileID: profile.id,
            originalPrompt: originalPrompt,
            content: [.item(ingot)] + weapons.map(AddOnContentNode.item) + [.shapelessRecipe(ingotRecipe)] + weaponRecipes.map(AddOnContentNode.shapedRecipe) + visuals.map(AddOnContentNode.visualResource)
        )
    }

    private static func normalizedShortDescription(_ description: String?, displayName: String, content: [AddOnContentNode]) -> String {
        let trimmed = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return String(trimmed.prefix(180))
        }
        let itemCount = content.reduce(0) { count, node in
            if case .item = node { count + 1 } else { count }
        }
        if itemCount > 1 {
            return "\(displayName) adds \(itemCount) custom items with matching crafting recipes."
        }
        return "\(displayName) adds a custom craftable item for Minecraft Bedrock."
    }
}

private extension String { var nonEmpty: String? { isEmpty ? nil : self } }

private struct MaterialToolSpec {
    let suffix: String
    let displayName: String
    let menuGroup: String
    let visualKind: VisualResourceKind
    let pattern: [String]
    let attackBonus: Int
}

private struct MaterialWeaponSpec {
    let suffix: String
    let displayName: String
    let menuGroup: String
    let visualKind: VisualResourceKind
    let pattern: [String]
    let attackBonus: Int
}

public enum AddOnProjectError: LocalizedError, Equatable {
    case emptyDisplayName
    case displayNameTooLong
    case invalidAttackBonus
    case invalidDurability
    case invalidIngredientCount
    case unsupportedProjectSchema(Int)
    case unsupportedVanillaItem(String)

    public var errorDescription: String? {
        switch self {
        case .emptyDisplayName: "Give your item a name."
        case .displayNameTooLong: "Item names must be 32 characters or fewer."
        case .invalidAttackBonus: "Attack bonus must be between 1 and 30."
        case .invalidDurability: "Durability must be between 50 and 2,000."
        case .invalidIngredientCount: "Material recipes need between 1 and 9 source items."
        case .unsupportedProjectSchema(let version): "Project schema version \(version) is newer than this app supports."
        case .unsupportedVanillaItem(let identifier):
            "The active Bedrock profile does not support \(identifier)."
        }
    }
}
