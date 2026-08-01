import Foundation

public enum SwordSpecError: LocalizedError, Equatable {
    case emptyDisplayName
    case displayNameTooLong
    case invalidAttackBonus
    case invalidDurability

    public var errorDescription: String? {
        switch self {
        case .emptyDisplayName: "Give your sword a name."
        case .displayNameTooLong: "Sword names must be 32 characters or fewer."
        case .invalidAttackBonus: "Attack bonus must be between 1 and 30."
        case .invalidDurability: "Durability must be between 50 and 2,000."
        }
    }
}

public enum SwordColor: String, CaseIterable, Codable, Sendable {
    case red, orange, yellow, lime, green, cyan, blue, purple
    case magenta, pink, white, gray, black, brown, gold, silver
}

public enum CraftingIngredient: String, CaseIterable, Codable, Sendable {
    case diamond, emerald, ironIngot = "iron_ingot", goldIngot = "gold_ingot"
    case netheriteIngot = "netherite_ingot", amethystShard = "amethyst_shard"
    case blazeRod = "blaze_rod", redstone, lapisLazuli = "lapis_lazuli", quartz

    public var bedrockIdentifier: String { "minecraft:\(rawValue)" }

    public var displayName: String {
        rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

public struct SwordSpec: Codable, Equatable, Sendable {
    public let displayName: String
    public let color: SwordColor
    public let attackBonus: Int
    public let durability: Int
    public let craftingIngredient: CraftingIngredient

    public init(
        displayName: String,
        color: SwordColor = .blue,
        attackBonus: Int = 10,
        durability: Int = 500,
        craftingIngredient: CraftingIngredient = .diamond
    ) throws {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw SwordSpecError.emptyDisplayName }
        guard trimmedName.count <= 32 else { throw SwordSpecError.displayNameTooLong }
        guard (1...30).contains(attackBonus) else { throw SwordSpecError.invalidAttackBonus }
        guard (50...2_000).contains(durability) else { throw SwordSpecError.invalidDurability }

        self.displayName = trimmedName
        self.color = color
        self.attackBonus = attackBonus
        self.durability = durability
        self.craftingIngredient = craftingIngredient
    }

    private enum CodingKeys: String, CodingKey {
        case displayName, color, attackBonus, durability, craftingIngredient
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            displayName: values.decode(String.self, forKey: .displayName),
            color: values.decode(SwordColor.self, forKey: .color),
            attackBonus: values.decode(Int.self, forKey: .attackBonus),
            durability: values.decode(Int.self, forKey: .durability),
            craftingIngredient: values.decode(CraftingIngredient.self, forKey: .craftingIngredient)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(displayName, forKey: .displayName)
        try values.encode(color, forKey: .color)
        try values.encode(attackBonus, forKey: .attackBonus)
        try values.encode(durability, forKey: .durability)
        try values.encode(craftingIngredient, forKey: .craftingIngredient)
    }
}

public enum BedrockIdentifierError: Error {
    case invalidSuffix
}

public struct BedrockIdentifier: Equatable, Sendable {
    public let rawValue: String

    public var pathComponent: String {
        String(rawValue.split(separator: ":", maxSplits: 1).last ?? "custom_sword")
    }

    public static func make(displayName: String, suffix: String? = nil) -> BedrockIdentifier {
        let latin = displayName.applyingTransform(.toLatin, reverse: false) ?? displayName
        let lowercased = latin.lowercased()
        let mapped = lowercased.unicodeScalars.map { scalar -> Character in
            switch scalar.value {
            case 97...122, 48...57: Character(String(scalar))
            default: "_"
            }
        }
        let collapsed = String(mapped).split(separator: "_", omittingEmptySubsequences: true).joined(separator: "_")
        let stem = collapsed.isEmpty ? "custom_sword" : String(collapsed.prefix(40))
        let safeSuffix = suffix.map { String($0.lowercased().prefix(12)) }
        let path = safeSuffix?.isEmpty == false ? "\(stem)_\(safeSuffix!)" : stem
        return BedrockIdentifier(rawValue: "craftberry:\(path)")
    }
}
