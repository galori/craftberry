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

public enum VisualResourceKind: String, Codable, Sendable {
    case swordPixelArt
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
    case visualResource(VisualResource)

    private enum CodingKeys: String, CodingKey { case type, value }
    private enum Kind: String, Codable { case item, shapedRecipe, visualResource }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .type) {
        case .item: self = .item(try values.decode(ItemDefinition.self, forKey: .value))
        case .shapedRecipe: self = .shapedRecipe(try values.decode(ShapedRecipeDefinition.self, forKey: .value))
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
        case .visualResource(let resource):
            try values.encode(Kind.visualResource, forKey: .type)
            try values.encode(resource, forKey: .value)
        }
    }
}

public struct AddOnProject: Codable, Equatable, Sendable, Identifiable {
    public let schemaVersion: Int
    public let id: UUID
    public let namespace: String
    public let displayName: String
    public let packUUIDs: PackUUIDs
    public let buildVersion: VersionTriplet
    public let targetProfileID: String
    public let originalPrompt: String
    public let content: [AddOnContentNode]

    public init(
        schemaVersion: Int = 1,
        id: UUID,
        namespace: String,
        displayName: String,
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
        self.packUUIDs = packUUIDs
        self.buildVersion = buildVersion
        self.targetProfileID = targetProfileID
        self.originalPrompt = originalPrompt
        self.content = content
    }

    public var items: [ItemDefinition] {
        content.compactMap { if case .item(let item) = $0 { item } else { nil } }
    }

    public var recipes: [ShapedRecipeDefinition] {
        content.compactMap { if case .shapedRecipe(let recipe) = $0 { recipe } else { nil } }
    }

    public var visualResources: [VisualResource] {
        content.compactMap { if case .visualResource(let resource) = $0 { resource } else { nil } }
    }

    public static func sword(
        displayName: String,
        color: PixelArtColor = .blue,
        attackBonus: Int = 10,
        durability: Int = 500,
        craftingIngredient: String = "minecraft:diamond",
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
            packUUIDs: identity.packUUIDs,
            buildVersion: VersionTriplet(major: 1, minor: 0, patch: 0),
            targetProfileID: profile.id,
            originalPrompt: originalPrompt,
            content: [.item(item), .shapedRecipe(recipe), .visualResource(visual)]
        )
    }
}

public enum AddOnProjectError: LocalizedError, Equatable {
    case emptyDisplayName
    case displayNameTooLong
    case invalidAttackBonus
    case invalidDurability
    case unsupportedVanillaItem(String)

    public var errorDescription: String? {
        switch self {
        case .emptyDisplayName: "Give your item a name."
        case .displayNameTooLong: "Item names must be 32 characters or fewer."
        case .invalidAttackBonus: "Attack bonus must be between 1 and 30."
        case .invalidDurability: "Durability must be between 50 and 2,000."
        case .unsupportedVanillaItem(let identifier):
            "The active Bedrock profile does not support \(identifier)."
        }
    }
}
