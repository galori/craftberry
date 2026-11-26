import Foundation

/// Generated from Mojang/bedrock-samples v1.26.30.5 at 921fafb05c93abeae56c2f2868cd8f942bdbcc0f.
/// Refresh with `scripts/refresh-vanilla-catalog.sh`; the allowlist is deliberately narrower than vanilla.
enum GeneratedVanillaItemCatalog {
    static let sourceVersion = "1.26.30.5"
    static let sourceCommit = "921fafb05c93abeae56c2f2868cd8f942bdbcc0f"
    static let materialSources: Set<String> = [
        "minecraft:amethyst_shard", "minecraft:blaze_rod", "minecraft:diamond",
        "minecraft:emerald", "minecraft:gold_ingot", "minecraft:iron_ingot",
        "minecraft:lapis_lazuli", "minecraft:netherite_ingot", "minecraft:quartz",
        "minecraft:redstone"
    ]
    static let additionalIdentifiers: Set<String> = [
        "minecraft:egg", "minecraft:feather", "minecraft:stick",
        "minecraft:wheat", "minecraft:wheat_seeds"
    ]
    static let smithingTemplates: Set<String> = [
        "minecraft:netherite_upgrade_smithing_template", "minecraft:ward_armor_trim_smithing_template"
    ]
    static let smithingBases: Set<String> = [
        "minecraft:diamond_sword"
    ]
    static let brewingInputs: Set<String> = [
        "minecraft:lingering_potion", "minecraft:potion", "minecraft:potion_type:awkward",
        "minecraft:potion_type:mundane", "minecraft:potion_type:thick", "minecraft:potion_type:water",
        "minecraft:splash_potion"
    ]
    static let brewingReagents: Set<String> = [
        "minecraft:blaze_powder", "minecraft:dragon_breath", "minecraft:ghast_tear",
        "minecraft:gunpowder", "minecraft:nether_wart"
    ]
    static let itemTags: Set<String> = [
        "minecraft:trimmable_armors"
    ]
    static let recipeForms: Set<String> = [
        "minecraft:recipe_brewing_container", "minecraft:recipe_brewing_mix", "minecraft:recipe_furnace",
        "minecraft:recipe_shaped", "minecraft:recipe_shapeless", "minecraft:recipe_smithing_transform",
        "minecraft:recipe_smithing_trim"
    ]
    static let trimmableArmorTag = "minecraft:trimmable_armors"
    static let identifiers = materialSources.union(additionalIdentifiers).union(smithingTemplates).union(smithingBases).union(brewingInputs).union(brewingReagents)
}
