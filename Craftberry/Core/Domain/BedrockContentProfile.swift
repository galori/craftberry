import Foundation

public struct VersionTriplet: Codable, Equatable, Hashable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var components: [Int] { [major, minor, patch] }
}

public enum ItemTraitKind: String, Codable, CaseIterable, Sendable {
    case combat
    case durability
    case handEquipped
    case armor
}

public struct BedrockContentProfile: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let sampleVersion: String
    public let sourceCommit: String
    public let minimumEngineVersion: VersionTriplet
    public let manifestFormatVersion: Int
    public let itemFormatVersion: String
    public let recipeFormatVersion: String
    public let supportedItemTraits: Set<ItemTraitKind>
    public let vanillaItemIdentifiers: Set<String>
    public let vanillaItemTags: Set<String>

    public init(
        id: String,
        sampleVersion: String,
        sourceCommit: String,
        minimumEngineVersion: VersionTriplet,
        manifestFormatVersion: Int,
        itemFormatVersion: String,
        recipeFormatVersion: String,
        supportedItemTraits: Set<ItemTraitKind>,
        vanillaItemIdentifiers: Set<String>,
        vanillaItemTags: Set<String>
    ) {
        self.id = id
        self.sampleVersion = sampleVersion
        self.sourceCommit = sourceCommit
        self.minimumEngineVersion = minimumEngineVersion
        self.manifestFormatVersion = manifestFormatVersion
        self.itemFormatVersion = itemFormatVersion
        self.recipeFormatVersion = recipeFormatVersion
        self.supportedItemTraits = supportedItemTraits
        self.vanillaItemIdentifiers = vanillaItemIdentifiers
        self.vanillaItemTags = vanillaItemTags
    }

    /// Stable profile pinned to Mojang's v1.26.30.5 bedrock-samples release.
    /// The deliberately small vanilla catalog contains only identifiers supported by
    /// the foundation sword archetype; it grows from generated profile resources.
    public static let current = BedrockContentProfile(
        id: "bedrock-stable-1.26.30",
        sampleVersion: "1.26.30.5",
        sourceCommit: "921fafb05c93abeae56c2f2868cd8f942bdbcc0f",
        minimumEngineVersion: VersionTriplet(major: 1, minor: 26, patch: 30),
        manifestFormatVersion: 2,
        itemFormatVersion: "1.21.100",
        recipeFormatVersion: "1.20.10",
        supportedItemTraits: [.combat, .durability, .handEquipped, .armor],
        vanillaItemIdentifiers: GeneratedVanillaItemCatalog.identifiers,
        vanillaItemTags: []
    )

    public var materialSourceIdentifiers: Set<String> {
        vanillaItemIdentifiers.intersection(GeneratedVanillaItemCatalog.materialSources)
    }
}
