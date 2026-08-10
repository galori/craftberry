import Foundation

/// Generated from Mojang/bedrock-samples v1.26.30.5 at 921fafb05c93abeae56c2f2868cd8f942bdbcc0f.
/// Refresh with `scripts/refresh-vanilla-catalog.sh`; this intentionally exposes only
/// the material inputs accepted by the active capability profile.
enum GeneratedVanillaItemCatalog {
    static let materialSources: Set<String> = [
        "minecraft:amethyst_shard", "minecraft:blaze_rod", "minecraft:diamond",
        "minecraft:emerald", "minecraft:gold_ingot", "minecraft:iron_ingot",
        "minecraft:lapis_lazuli", "minecraft:netherite_ingot", "minecraft:quartz",
        "minecraft:redstone"
    ]

    static let smithingTemplates: Set<String> = [
        "minecraft:netherite_upgrade_smithing_template",
        "minecraft:ward_armor_trim_smithing_template"
    ]

    static let smithingBases: Set<String> = [
        "minecraft:diamond_sword"
    ]

    static let trimmableArmorTag = "minecraft:trimmable_armors"

    static let brewingInputs: Set<String> = [
        "minecraft:potion",
        "minecraft:splash_potion",
        "minecraft:lingering_potion",
        "minecraft:potion_type:awkward",
        "minecraft:potion_type:water",
        "minecraft:potion_type:mundane",
        "minecraft:potion_type:thick"
    ]

    static let brewingReagents: Set<String> = [
        "minecraft:blaze_powder",
        "minecraft:dragon_breath",
        "minecraft:ghast_tear",
        "minecraft:gunpowder",
        "minecraft:nether_wart"
    ]

    static let identifiers = materialSources.union(["minecraft:stick"]).union(smithingTemplates).union(smithingBases).union(brewingInputs).union(brewingReagents)
}
