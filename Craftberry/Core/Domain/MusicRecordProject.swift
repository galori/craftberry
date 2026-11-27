import Foundation

public enum MusicRecordStyle: String, Codable, Equatable, Sendable, CaseIterable {
    case dreamy
    case bright
    case mysterious
    case adventurous
}

public struct MusicRecordTrait: Codable, Equatable, Sendable {
    public let style: MusicRecordStyle

    public init(style: MusicRecordStyle) {
        self.style = style
    }
}

extension AddOnProject {
    public static func musicRecordSet(
        title: String,
        color: PixelArtColor = .cyan,
        style: MusicRecordStyle = .dreamy,
        shortDescription: String? = nil,
        originalPrompt: String,
        identity: AddOnProjectIdentity = .generate(),
        profile: BedrockContentProfile = .current
    ) throws -> AddOnProject {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw AddOnProjectError.emptyDisplayName }
        guard trimmedTitle.count <= 32 else { throw AddOnProjectError.displayNameTooLong }

        let stem = BedrockIdentifier.make(displayName: trimmedTitle, suffix: identity.contentSuffix).pathComponent
        let discID = ContentID("\(stem)_disc")
        let disc = ItemDefinition(
            id: discID,
            displayName: trimmedTitle,
            menuCategory: .items,
            menuGroup: nil,
            traits: ItemTraits(maximumStackSize: 1, musicRecord: MusicRecordTrait(style: style)),
            visualResourceID: discID
        )
        let recipe = ShapedRecipeDefinition(
            id: ContentID("\(discID.rawValue)_recipe"),
            tags: ["crafting_table"],
            pattern: ["DDD", "DRD", "DDD"],
            ingredients: ["D": .vanilla("minecraft:diamond"), "R": .vanilla("minecraft:redstone")],
            result: RecipeResult(item: .generated(discID), count: 1),
            unlock: [.vanilla("minecraft:diamond")]
        )
        let visual = VisualResource(id: discID, kind: .musicDiscPixelArt, color: color)

        return AddOnProject(
            id: identity.projectID,
            namespace: identity.namespace,
            displayName: trimmedTitle,
            shortDescription: shortDescription,
            packUUIDs: identity.packUUIDs,
            buildVersion: VersionTriplet(major: 1, minor: 0, patch: 0),
            targetProfileID: profile.id,
            originalPrompt: originalPrompt,
            content: [.item(disc), .shapedRecipe(recipe), .visualResource(visual)]
        )
    }
}
