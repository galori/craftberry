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

    static let identifiers = materialSources.union(["minecraft:stick"])
}
