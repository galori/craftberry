import Foundation

/// Pre-computed `ProjectGeneration` values for every `ExamplePromptLibrary` suggestion.
/// Each factory closure builds a fresh `AddOnProject` with the supplied identity so
/// callers get unique pack UUIDs while still avoiding any network call.
enum ExamplePromptResponseCache {
    static func generation(
        for prompt: String,
        identity: AddOnProjectIdentity,
        originalPrompt: String
    ) throws -> ProjectGeneration? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let project: AddOnProject
        switch trimmed {
        // MARK: - Single swords
        case "A blue sword, 20 damage, crafted from diamonds":
            project = try AddOnProject.sword(
                displayName: "Azure Sword",
                color: .blue,
                attackBonus: 20,
                durability: 500,
                craftingIngredient: "minecraft:diamond",
                shortDescription: "A blue sword with 20 damage, crafted from diamonds.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A purple sword named Starfall, crafted from amethyst":
            project = try AddOnProject.sword(
                displayName: "Starfall",
                color: .purple,
                attackBonus: 10,
                durability: 500,
                craftingIngredient: "minecraft:amethyst_shard",
                shortDescription: "A purple sword named Starfall, crafted from amethyst.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A red sword with 12 damage, crafted from blaze rods":
            project = try AddOnProject.sword(
                displayName: "Ember Sword",
                color: .red,
                attackBonus: 12,
                durability: 500,
                craftingIngredient: "minecraft:blaze_rod",
                shortDescription: "A red sword with 12 damage, crafted from blaze rods.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "An emerald sword named Verdant Edge, 900 durability":
            project = try AddOnProject.sword(
                displayName: "Verdant Edge",
                color: .green,
                attackBonus: 10,
                durability: 900,
                craftingIngredient: "minecraft:emerald",
                shortDescription: "An emerald sword named Verdant Edge with 900 durability.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A crackling redstone sword, 15 damage, 400 durability":
            project = try AddOnProject.sword(
                displayName: "Pulse Sword",
                color: .red,
                attackBonus: 15,
                durability: 400,
                craftingIngredient: "minecraft:redstone",
                shortDescription: "A crackling redstone sword with 15 damage.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A deep blue lapis sword named Tidecaller, 11 damage":
            project = try AddOnProject.sword(
                displayName: "Tidecaller",
                color: .blue,
                attackBonus: 11,
                durability: 500,
                craftingIngredient: "minecraft:lapis_lazuli",
                shortDescription: "A deep blue lapis sword named Tidecaller.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A netherite sword named Ashfang with 28 damage":
            project = try AddOnProject.sword(
                displayName: "Ashfang",
                color: .black,
                attackBonus: 28,
                durability: 500,
                craftingIngredient: "minecraft:netherite_ingot",
                shortDescription: "A netherite sword named Ashfang with 28 damage.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A pale quartz sword named Moonsliver, 9 damage":
            project = try AddOnProject.sword(
                displayName: "Moonsliver",
                color: .white,
                attackBonus: 9,
                durability: 500,
                craftingIngredient: "minecraft:quartz",
                shortDescription: "A pale quartz sword named Moonsliver.",
                originalPrompt: originalPrompt,
                identity: identity
            )

        // MARK: - Material sword sets
        case "A Glacier ingot and matching sword, from 4 diamonds":
            project = try AddOnProject.materialSwordSet(
                materialName: "Glacier",
                color: .cyan,
                sourceItem: "minecraft:diamond",
                sourceCount: 4,
                attackBonus: 10,
                durability: 500,
                shortDescription: "A Glacier ingot and matching sword from diamonds.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A golden Sunforge ingot plus its matching sword":
            project = try AddOnProject.materialSwordSet(
                materialName: "Sunforge",
                color: .gold,
                sourceItem: "minecraft:gold_ingot",
                sourceCount: 4,
                attackBonus: 10,
                durability: 500,
                shortDescription: "A golden Sunforge ingot plus its matching sword.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "An iron Ironheart ingot and sword with 14 damage":
            project = try AddOnProject.materialSwordSet(
                materialName: "Ironheart",
                color: .gray,
                sourceItem: "minecraft:iron_ingot",
                sourceCount: 4,
                attackBonus: 14,
                durability: 500,
                shortDescription: "An Ironheart ingot and sword with 14 damage.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "An amethyst Duskshard ingot and its matching sword":
            project = try AddOnProject.materialSwordSet(
                materialName: "Duskshard",
                color: .purple,
                sourceItem: "minecraft:amethyst_shard",
                sourceCount: 4,
                attackBonus: 10,
                durability: 500,
                shortDescription: "An amethyst Duskshard ingot and matching sword.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A quartz ingot named Starlight plus a matching sword":
            project = try AddOnProject.materialSwordSet(
                materialName: "Starlight",
                color: .white,
                sourceItem: "minecraft:quartz",
                sourceCount: 4,
                attackBonus: 10,
                durability: 500,
                shortDescription: "A quartz Starlight ingot plus a matching sword.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A Cinder ingot from blaze rods, with an 18 damage sword":
            project = try AddOnProject.materialSwordSet(
                materialName: "Cinder",
                color: .orange,
                sourceItem: "minecraft:blaze_rod",
                sourceCount: 4,
                attackBonus: 18,
                durability: 500,
                shortDescription: "A Cinder ingot from blaze rods with an 18 damage sword.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "An emerald ingot named Jade with a 750 durability sword":
            project = try AddOnProject.materialSwordSet(
                materialName: "Jade",
                color: .green,
                sourceItem: "minecraft:emerald",
                sourceCount: 4,
                attackBonus: 10,
                durability: 750,
                shortDescription: "An emerald Jade ingot with a 750 durability sword.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A netherite Voidcore ingot and its matching sword":
            project = try AddOnProject.materialSwordSet(
                materialName: "Voidcore",
                color: .black,
                sourceItem: "minecraft:netherite_ingot",
                sourceCount: 4,
                attackBonus: 10,
                durability: 500,
                shortDescription: "A netherite Voidcore ingot and matching sword.",
                originalPrompt: originalPrompt,
                identity: identity
            )

        // MARK: - Tool sets
        case "A redstone tool set: sword, pickaxe, axe, shovel, hoe":
            project = try AddOnProject.materialToolSet(
                materialName: "Redstone",
                color: .red,
                sourceItem: "minecraft:redstone",
                sourceCount: 4,
                attackBonus: 10,
                durability: 500,
                shortDescription: "A redstone tool set with sword, pickaxe, axe, shovel and hoe.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A diamond tool set named Frostforge for a mining trip":
            project = try AddOnProject.materialToolSet(
                materialName: "Frostforge",
                color: .cyan,
                sourceItem: "minecraft:diamond",
                sourceCount: 4,
                attackBonus: 10,
                durability: 500,
                shortDescription: "A diamond Frostforge tool set for a mining trip.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A gold tool set named Harvest with a 600 durability hoe":
            project = try AddOnProject.materialToolSet(
                materialName: "Harvest",
                color: .gold,
                sourceItem: "minecraft:gold_ingot",
                sourceCount: 4,
                attackBonus: 10,
                durability: 600,
                shortDescription: "A gold Harvest tool set with 600 durability.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A lapis tool set named Deepdelve with a 10 damage sword":
            project = try AddOnProject.materialToolSet(
                materialName: "Deepdelve",
                color: .blue,
                sourceItem: "minecraft:lapis_lazuli",
                sourceCount: 4,
                attackBonus: 10,
                durability: 500,
                shortDescription: "A lapis Deepdelve tool set with a 10 damage sword.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "An iron tool set named Toolbox with 800 durability":
            project = try AddOnProject.materialToolSet(
                materialName: "Toolbox",
                color: .gray,
                sourceItem: "minecraft:iron_ingot",
                sourceCount: 4,
                attackBonus: 10,
                durability: 800,
                shortDescription: "An iron Toolbox tool set with 800 durability.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "An amethyst tool set named Geode, crafted from 6 shards":
            project = try AddOnProject.materialToolSet(
                materialName: "Geode",
                color: .purple,
                sourceItem: "minecraft:amethyst_shard",
                sourceCount: 6,
                attackBonus: 10,
                durability: 500,
                shortDescription: "An amethyst Geode tool set crafted from 6 shards.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A quartz tool set named Snowline for a snowy build":
            project = try AddOnProject.materialToolSet(
                materialName: "Snowline",
                color: .white,
                sourceItem: "minecraft:quartz",
                sourceCount: 4,
                attackBonus: 10,
                durability: 500,
                shortDescription: "A quartz Snowline tool set for a snowy build.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A netherite tool set named Starforged, 25 damage sword":
            project = try AddOnProject.materialToolSet(
                materialName: "Starforged",
                color: .black,
                sourceItem: "minecraft:netherite_ingot",
                sourceCount: 4,
                attackBonus: 25,
                durability: 500,
                shortDescription: "A netherite Starforged tool set with 25 damage sword.",
                originalPrompt: originalPrompt,
                identity: identity
            )

        // MARK: - Weapon sets
        case "An emerald weapon set: sword, dagger, spear, and hammer":
            project = try AddOnProject.materialWeaponSet(
                materialName: "Emerald",
                color: .green,
                sourceItem: "minecraft:emerald",
                sourceCount: 4,
                attackBonus: 10,
                durability: 500,
                shortDescription: "An emerald weapon set with sword, dagger, spear and hammer.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A diamond weapon set named Stormbrand, 22 damage":
            project = try AddOnProject.materialWeaponSet(
                materialName: "Stormbrand",
                color: .cyan,
                sourceItem: "minecraft:diamond",
                sourceCount: 4,
                attackBonus: 22,
                durability: 500,
                shortDescription: "A diamond Stormbrand weapon set with 22 damage.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A lapis weapon set named Tideguard with a long spear":
            project = try AddOnProject.materialWeaponSet(
                materialName: "Tideguard",
                color: .blue,
                sourceItem: "minecraft:lapis_lazuli",
                sourceCount: 4,
                attackBonus: 10,
                durability: 500,
                shortDescription: "A lapis Tideguard weapon set with a long spear.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A netherite weapon set named Doomforge, 30 damage":
            project = try AddOnProject.materialWeaponSet(
                materialName: "Doomforge",
                color: .black,
                sourceItem: "minecraft:netherite_ingot",
                sourceCount: 4,
                attackBonus: 30,
                durability: 500,
                shortDescription: "A netherite Doomforge weapon set with 30 damage.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A gold weapon set named Nightblade with a quick dagger":
            project = try AddOnProject.materialWeaponSet(
                materialName: "Nightblade",
                color: .gold,
                sourceItem: "minecraft:gold_ingot",
                sourceCount: 4,
                attackBonus: 10,
                durability: 500,
                shortDescription: "A gold Nightblade weapon set with a quick dagger.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A blaze rod weapon set named Emberstrike, 19 damage":
            project = try AddOnProject.materialWeaponSet(
                materialName: "Emberstrike",
                color: .orange,
                sourceItem: "minecraft:blaze_rod",
                sourceCount: 4,
                attackBonus: 19,
                durability: 500,
                shortDescription: "A blaze Emberstrike weapon set with 19 damage.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "An iron weapon set named Guardian, 1200 durability":
            project = try AddOnProject.materialWeaponSet(
                materialName: "Guardian",
                color: .gray,
                sourceItem: "minecraft:iron_ingot",
                sourceCount: 4,
                attackBonus: 10,
                durability: 1200,
                shortDescription: "An iron Guardian weapon set with 1200 durability.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "An amethyst weapon set named Prism with a heavy hammer":
            project = try AddOnProject.materialWeaponSet(
                materialName: "Prism",
                color: .purple,
                sourceItem: "minecraft:amethyst_shard",
                sourceCount: 4,
                attackBonus: 10,
                durability: 500,
                shortDescription: "An amethyst Prism weapon set with a heavy hammer.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A redstone weapon set named Fuse with a fast dagger":
            project = try AddOnProject.materialWeaponSet(
                materialName: "Fuse",
                color: .red,
                sourceItem: "minecraft:redstone",
                sourceCount: 4,
                attackBonus: 10,
                durability: 500,
                shortDescription: "A redstone Fuse weapon set with a fast dagger.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A quartz weapon set named Featherfall, 8 damage spear":
            project = try AddOnProject.materialWeaponSet(
                materialName: "Featherfall",
                color: .white,
                sourceItem: "minecraft:quartz",
                sourceCount: 4,
                attackBonus: 8,
                durability: 500,
                shortDescription: "A quartz Featherfall weapon set with an 8 damage spear.",
                originalPrompt: originalPrompt,
                identity: identity
            )

        // MARK: - Armor sets
        case "A netherite armor set named Warden, 20 protection":
            project = try AddOnProject.materialArmorSet(
                materialName: "Warden",
                color: .black,
                sourceItem: "minecraft:netherite_ingot",
                sourceCount: 4,
                protection: 20,
                durability: 500,
                shortDescription: "A netherite Warden armor set with 20 protection.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A gold armor set from 3 gold ingots, called Radiant":
            project = try AddOnProject.materialArmorSet(
                materialName: "Radiant",
                color: .gold,
                sourceItem: "minecraft:gold_ingot",
                sourceCount: 3,
                protection: 15,
                durability: 500,
                shortDescription: "A gold Radiant armor set from 3 gold ingots.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A diamond armor set named Bastion, 900 durability":
            project = try AddOnProject.materialArmorSet(
                materialName: "Bastion",
                color: .cyan,
                sourceItem: "minecraft:diamond",
                sourceCount: 4,
                protection: 15,
                durability: 900,
                shortDescription: "A diamond Bastion armor set with 900 durability.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "An amethyst armor set named Crystalguard, 16 protection":
            project = try AddOnProject.materialArmorSet(
                materialName: "Crystalguard",
                color: .purple,
                sourceItem: "minecraft:amethyst_shard",
                sourceCount: 4,
                protection: 16,
                durability: 500,
                shortDescription: "An amethyst Crystalguard armor set with 16 protection.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "An iron armor set named Ironclad for early exploring":
            project = try AddOnProject.materialArmorSet(
                materialName: "Ironclad",
                color: .gray,
                sourceItem: "minecraft:iron_ingot",
                sourceCount: 4,
                protection: 15,
                durability: 500,
                shortDescription: "An iron Ironclad armor set for early exploring.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A redstone armor set named Pulseguard, 12 protection":
            project = try AddOnProject.materialArmorSet(
                materialName: "Pulseguard",
                color: .red,
                sourceItem: "minecraft:redstone",
                sourceCount: 4,
                protection: 12,
                durability: 500,
                shortDescription: "A redstone Pulseguard armor set with 12 protection.",
                originalPrompt: originalPrompt,
                identity: identity
            )

        // MARK: - Consumable sets
        case "A diamond consumable set: ingot, food, and fuel":
            project = try AddOnProject.materialConsumableSet(
                materialName: "Diamond",
                color: .cyan,
                sourceItem: "minecraft:diamond",
                sourceCount: 4,
                nutrition: 6,
                saturationModifier: "0.6",
                canAlwaysEat: false,
                fuelDuration: 12.0,
                shortDescription: "A diamond consumable set with ingot, food and fuel.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "An emerald consumable set named Verdant with food and fuel":
            project = try AddOnProject.materialConsumableSet(
                materialName: "Verdant",
                color: .green,
                sourceItem: "minecraft:emerald",
                sourceCount: 4,
                nutrition: 6,
                saturationModifier: "0.6",
                canAlwaysEat: false,
                fuelDuration: 12.0,
                shortDescription: "An emerald Verdant consumable set with food and fuel.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A blaze rod consumable set named Ember with food and fuel":
            project = try AddOnProject.materialConsumableSet(
                materialName: "Ember",
                color: .orange,
                sourceItem: "minecraft:blaze_rod",
                sourceCount: 4,
                nutrition: 6,
                saturationModifier: "0.6",
                canAlwaysEat: false,
                fuelDuration: 12.0,
                shortDescription: "A blaze Ember consumable set with food and fuel.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A quartz consumable set named Frostbite, food and fuel":
            project = try AddOnProject.materialConsumableSet(
                materialName: "Frostbite",
                color: .white,
                sourceItem: "minecraft:quartz",
                sourceCount: 4,
                nutrition: 6,
                saturationModifier: "0.6",
                canAlwaysEat: false,
                fuelDuration: 12.0,
                shortDescription: "A quartz Frostbite consumable set with food and fuel.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A redstone consumable set named Pulse, food and fuel":
            project = try AddOnProject.materialConsumableSet(
                materialName: "Pulse",
                color: .red,
                sourceItem: "minecraft:redstone",
                sourceCount: 4,
                nutrition: 6,
                saturationModifier: "0.6",
                canAlwaysEat: false,
                fuelDuration: 12.0,
                shortDescription: "A redstone Pulse consumable set with food and fuel.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "An iron consumable set named Ironclad with food and fuel":
            project = try AddOnProject.materialConsumableSet(
                materialName: "Ironclad",
                color: .gray,
                sourceItem: "minecraft:iron_ingot",
                sourceCount: 4,
                nutrition: 6,
                saturationModifier: "0.6",
                canAlwaysEat: false,
                fuelDuration: 12.0,
                shortDescription: "An iron Ironclad consumable set with food and fuel.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A lapis consumable set named Deepsea, food and fuel":
            project = try AddOnProject.materialConsumableSet(
                materialName: "Deepsea",
                color: .blue,
                sourceItem: "minecraft:lapis_lazuli",
                sourceCount: 4,
                nutrition: 6,
                saturationModifier: "0.6",
                canAlwaysEat: false,
                fuelDuration: 12.0,
                shortDescription: "A lapis Deepsea consumable set with food and fuel.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A gold consumable set named Gilded with food and fuel":
            project = try AddOnProject.materialConsumableSet(
                materialName: "Gilded",
                color: .gold,
                sourceItem: "minecraft:gold_ingot",
                sourceCount: 4,
                nutrition: 6,
                saturationModifier: "0.6",
                canAlwaysEat: false,
                fuelDuration: 12.0,
                shortDescription: "A gold Gilded consumable set with food and fuel.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "An amethyst consumable set named Geode, food and fuel":
            project = try AddOnProject.materialConsumableSet(
                materialName: "Geode",
                color: .purple,
                sourceItem: "minecraft:amethyst_shard",
                sourceCount: 4,
                nutrition: 6,
                saturationModifier: "0.6",
                canAlwaysEat: false,
                fuelDuration: 12.0,
                shortDescription: "An amethyst Geode consumable set with food and fuel.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A netherite consumable set named Warden, food and fuel":
            project = try AddOnProject.materialConsumableSet(
                materialName: "Warden",
                color: .black,
                sourceItem: "minecraft:netherite_ingot",
                sourceCount: 4,
                nutrition: 6,
                saturationModifier: "0.6",
                canAlwaysEat: false,
                fuelDuration: 12.0,
                shortDescription: "A netherite Warden consumable set with food and fuel.",
                originalPrompt: originalPrompt,
                identity: identity
            )

        // MARK: - Block sets
        case "A diamond block set: Azure ingot plus storage block":
            project = try AddOnProject.materialBlockSet(
                materialName: "Azure",
                color: .cyan,
                sourceItem: "minecraft:diamond",
                sourceCount: 4,
                destroyTime: 3.0,
                mapColor: "#5CDBD5",
                shortDescription: "A diamond Azure ingot plus storage block.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "An emerald block set named Verdant with ingot and block":
            project = try AddOnProject.materialBlockSet(
                materialName: "Verdant",
                color: .green,
                sourceItem: "minecraft:emerald",
                sourceCount: 4,
                destroyTime: 3.0,
                mapColor: "#17C37B",
                shortDescription: "An emerald Verdant ingot and block.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A blaze rod block set named Ember with ingot and block":
            project = try AddOnProject.materialBlockSet(
                materialName: "Ember",
                color: .orange,
                sourceItem: "minecraft:blaze_rod",
                sourceCount: 4,
                destroyTime: 3.0,
                mapColor: "#F0B12D",
                shortDescription: "A blaze Ember ingot and block.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A quartz block set named Frostbite with ingot and block":
            project = try AddOnProject.materialBlockSet(
                materialName: "Frostbite",
                color: .white,
                sourceItem: "minecraft:quartz",
                sourceCount: 4,
                destroyTime: 3.0,
                mapColor: "#E9E2D6",
                shortDescription: "A quartz Frostbite ingot and block.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A redstone block set named Pulse with ingot and block":
            project = try AddOnProject.materialBlockSet(
                materialName: "Pulse",
                color: .red,
                sourceItem: "minecraft:redstone",
                sourceCount: 4,
                destroyTime: 3.0,
                mapColor: "#B01A14",
                shortDescription: "A redstone Pulse ingot and block.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "An iron block set named Ironclad with ingot and block":
            project = try AddOnProject.materialBlockSet(
                materialName: "Ironclad",
                color: .gray,
                sourceItem: "minecraft:iron_ingot",
                sourceCount: 4,
                destroyTime: 3.0,
                mapColor: "#C2C2C2",
                shortDescription: "An iron Ironclad ingot and block.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A lapis block set named Deepsea with ingot and block":
            project = try AddOnProject.materialBlockSet(
                materialName: "Deepsea",
                color: .blue,
                sourceItem: "minecraft:lapis_lazuli",
                sourceCount: 4,
                destroyTime: 3.0,
                mapColor: "#224D85",
                shortDescription: "A lapis Deepsea ingot and block.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A gold block set named Gilded with ingot and block":
            project = try AddOnProject.materialBlockSet(
                materialName: "Gilded",
                color: .gold,
                sourceItem: "minecraft:gold_ingot",
                sourceCount: 4,
                destroyTime: 3.0,
                mapColor: "#FAEE4D",
                shortDescription: "A gold Gilded ingot and block.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "An amethyst block set named Geode with ingot and block":
            project = try AddOnProject.materialBlockSet(
                materialName: "Geode",
                color: .purple,
                sourceItem: "minecraft:amethyst_shard",
                sourceCount: 4,
                destroyTime: 3.0,
                mapColor: "#8B5FE0",
                shortDescription: "An amethyst Geode ingot and block.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        case "A netherite block set named Warden with ingot and block":
            project = try AddOnProject.materialBlockSet(
                materialName: "Warden",
                color: .black,
                sourceItem: "minecraft:netherite_ingot",
                sourceCount: 4,
                destroyTime: 3.0,
                mapColor: "#443F41",
                shortDescription: "A netherite Warden ingot and block.",
                originalPrompt: originalPrompt,
                identity: identity
            )
        default:
            return nil
        }
        return ProjectGeneration(outcome: .ready, message: "Ready to build.", project: project)
    }

    static var allCachedPrompts: [String] {
        [
            "A blue sword, 20 damage, crafted from diamonds",
            "A purple sword named Starfall, crafted from amethyst",
            "A red sword with 12 damage, crafted from blaze rods",
            "An emerald sword named Verdant Edge, 900 durability",
            "A crackling redstone sword, 15 damage, 400 durability",
            "A deep blue lapis sword named Tidecaller, 11 damage",
            "A netherite sword named Ashfang with 28 damage",
            "A pale quartz sword named Moonsliver, 9 damage",
            "A Glacier ingot and matching sword, from 4 diamonds",
            "A golden Sunforge ingot plus its matching sword",
            "An iron Ironheart ingot and sword with 14 damage",
            "An amethyst Duskshard ingot and its matching sword",
            "A quartz ingot named Starlight plus a matching sword",
            "A Cinder ingot from blaze rods, with an 18 damage sword",
            "An emerald ingot named Jade with a 750 durability sword",
            "A netherite Voidcore ingot and its matching sword",
            "A redstone tool set: sword, pickaxe, axe, shovel, hoe",
            "A diamond tool set named Frostforge for a mining trip",
            "A gold tool set named Harvest with a 600 durability hoe",
            "A lapis tool set named Deepdelve with a 10 damage sword",
            "An iron tool set named Toolbox with 800 durability",
            "An amethyst tool set named Geode, crafted from 6 shards",
            "A quartz tool set named Snowline for a snowy build",
            "A netherite tool set named Starforged, 25 damage sword",
            "An emerald weapon set: sword, dagger, spear, and hammer",
            "A diamond weapon set named Stormbrand, 22 damage",
            "A lapis weapon set named Tideguard with a long spear",
            "A netherite weapon set named Doomforge, 30 damage",
            "A gold weapon set named Nightblade with a quick dagger",
            "A blaze rod weapon set named Emberstrike, 19 damage",
            "An iron weapon set named Guardian, 1200 durability",
            "An amethyst weapon set named Prism with a heavy hammer",
            "A redstone weapon set named Fuse with a fast dagger",
            "A quartz weapon set named Featherfall, 8 damage spear",
            "A netherite armor set named Warden, 20 protection",
            "A gold armor set from 3 gold ingots, called Radiant",
            "A diamond armor set named Bastion, 900 durability",
            "An amethyst armor set named Crystalguard, 16 protection",
            "An iron armor set named Ironclad for early exploring",
            "A redstone armor set named Pulseguard, 12 protection",
            "A diamond consumable set: ingot, food, and fuel",
            "An emerald consumable set named Verdant with food and fuel",
            "A blaze rod consumable set named Ember with food and fuel",
            "A quartz consumable set named Frostbite, food and fuel",
            "A redstone consumable set named Pulse, food and fuel",
            "An iron consumable set named Ironclad with food and fuel",
            "A lapis consumable set named Deepsea, food and fuel",
            "A gold consumable set named Gilded with food and fuel",
            "An amethyst consumable set named Geode, food and fuel",
            "A netherite consumable set named Warden, food and fuel",
            "A diamond block set: Azure ingot plus storage block",
            "An emerald block set named Verdant with ingot and block",
            "A blaze rod block set named Ember with ingot and block",
            "A quartz block set named Frostbite with ingot and block",
            "A redstone block set named Pulse with ingot and block",
            "An iron block set named Ironclad with ingot and block",
            "A lapis block set named Deepsea with ingot and block",
            "A gold block set named Gilded with ingot and block",
            "An amethyst block set named Geode with ingot and block",
            "A netherite block set named Warden with ingot and block"
        ]
    }
}
