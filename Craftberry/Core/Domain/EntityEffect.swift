import Foundation

/// Shape of the one-shot particle burst an effect creature plays when it appears.
public enum EntityEffectParticle: String, Codable, Equatable, Sendable, CaseIterable {
    case burst
    case fountain
    case drift
}

/// Short original tone an effect creature plays when it appears. Rendered by Craftberry, never sampled.
public enum EntityEffectSound: String, Codable, Equatable, Sendable, CaseIterable {
    case chime
    case bell
    case zap
}

/// One particle effect and one sound that play once when the entity is spawned from its egg.
public struct EntityEffectTrait: Codable, Equatable, Sendable {
    public let particle: EntityEffectParticle
    public let sound: EntityEffectSound

    public init(particle: EntityEffectParticle, sound: EntityEffectSound) {
        self.particle = particle
        self.sound = sound
    }
}

extension AddOnProject {
    /// Ingot, spawn egg and a passive creature that plays an original particle burst and an original
    /// sound once when summoned. The creature has no natural spawn rule, so the effect only fires from the egg.
    public static func materialEffectEntitySet(
        materialName: String = "Azure",
        color: PixelArtColor = .cyan,
        sourceItem: String = "minecraft:diamond",
        sourceCount: Int = 4,
        particle: EntityEffectParticle = .burst,
        sound: EntityEffectSound = .chime,
        shortDescription: String? = nil,
        originalPrompt: String,
        identity: AddOnProjectIdentity = .generate(),
        profile: BedrockContentProfile = .current
    ) throws -> AddOnProject {
        let base = try materialEntitySet(
            materialName: materialName,
            color: color,
            sourceItem: sourceItem,
            sourceCount: sourceCount,
            shortDescription: shortDescription,
            originalPrompt: originalPrompt,
            identity: identity,
            profile: profile
        )
        let content: [AddOnContentNode] = base.content.compactMap { node in
            switch node {
            case .spawnRule: nil
            case .entity(let entity):
                .entity(EntityDefinition(
                    id: entity.id,
                    displayName: entity.displayName,
                    health: entity.health,
                    movement: entity.movement,
                    scale: entity.scale,
                    spawnEggResourceID: entity.spawnEggResourceID,
                    textureResourceID: entity.textureResourceID,
                    archetype: entity.archetype,
                    effect: EntityEffectTrait(particle: particle, sound: sound)
                ))
            default: node
            }
        }
        return AddOnProject(
            id: base.id,
            namespace: base.namespace,
            displayName: base.displayName,
            shortDescription: base.shortDescription,
            packUUIDs: base.packUUIDs,
            buildVersion: base.buildVersion,
            targetProfileID: base.targetProfileID,
            originalPrompt: base.originalPrompt,
            content: content
        )
    }
}
