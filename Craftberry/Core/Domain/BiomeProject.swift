import Foundation

/// Surface blocks a generated biome may paint. Each is a stable vanilla block
/// whose top face is easy to tell apart from the plains and forest it replaces.
public enum BiomeSurface: String, Codable, Equatable, Sendable, CaseIterable {
    case redSand
    case snow
    case mycelium

    public var blockIdentifier: String {
        switch self {
        case .redSand: "minecraft:red_sand"
        case .snow: "minecraft:snow_block"
        case .mycelium: "minecraft:mycelium"
        }
    }

    var tokenColor: PixelArtColor {
        switch self {
        case .redSand: .orange
        case .snow: .white
        case .mycelium: .purple
        }
    }
}

public struct BiomeDefinition: Codable, Equatable, Sendable {
    public let id: ContentID
    public let displayName: String
    public let surface: BiomeSurface

    public init(id: ContentID, displayName: String, surface: BiomeSurface) {
        self.id = id
        self.displayName = displayName
        self.surface = surface
    }
}

extension AddOnProject {
    /// One namespaced biome that replaces part of vanilla plains and forest, plus a
    /// token item so the pack has the icon and creative-menu entry every add-on needs.
    public static func biomeSet(
        biomeName: String,
        surface: BiomeSurface = .redSand,
        shortDescription: String? = nil,
        originalPrompt: String,
        identity: AddOnProjectIdentity = .generate(),
        profile: BedrockContentProfile = .current
    ) throws -> AddOnProject {
        let name = biomeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw AddOnProjectError.emptyDisplayName }
        guard name.count <= 24 else { throw AddOnProjectError.displayNameTooLong }

        let stem = BedrockIdentifier.make(displayName: name, suffix: identity.contentSuffix).pathComponent
        let biomeID = ContentID("\(stem)_biome")
        let tokenID = ContentID("\(stem)_biome_token")
        let biome = BiomeDefinition(id: biomeID, displayName: name, surface: surface)
        let token = ItemDefinition(id: tokenID, displayName: "\(name) Biome Token", menuCategory: .items, menuGroup: nil, traits: ItemTraits(), visualResourceID: tokenID)
        let visual = VisualResource(id: tokenID, kind: .ingotPixelArt, color: surface.tokenColor)
        return AddOnProject(
            id: identity.projectID,
            namespace: identity.namespace,
            displayName: name,
            shortDescription: shortDescription,
            packUUIDs: identity.packUUIDs,
            buildVersion: VersionTriplet(major: 1, minor: 0, patch: 0),
            targetProfileID: profile.id,
            originalPrompt: originalPrompt,
            content: [.item(token), .biome(biome), .visualResource(visual)]
        )
    }
}
