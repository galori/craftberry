import Foundation

/// One tappable starter idea on the welcome screen.
struct ExamplePrompt: Identifiable, Equatable, Sendable {
    let emoji: String
    let text: String

    var id: String { text }
    var displayLabel: String { "\(emoji)  \(text)" }
}

/// The pool the welcome screen samples three suggestions from.
///
/// Every prompt must stay inside the active capability profile: only materials from
/// `GeneratedVanillaItemCatalog.materialSources`, attack 1–30, durability 50–2,000, protection
/// 4–20, and one of the supported project kinds (single sword, ingot + sword, tool set, weapon
/// set, armor set, consumable set, block set, furnace set, smithing set). Add a handful of prompts here whenever a new capability ships — see AGENTS.md.
enum ExamplePromptLibrary {
    static let all: [ExamplePrompt] = singleSwords + materialSwordSets + toolSets + weaponSets + armorSets + consumableSets + blockSets + furnaceSets + smithingSets + brewingSets + oreSets + cropSets

    /// Picks `count` prompts at random, preferring ones the user is not already looking at.
    static func selection(
        count: Int = 3,
        excluding shown: [ExamplePrompt] = [],
        using generator: inout some RandomNumberGenerator
    ) -> [ExamplePrompt] {
        let shownIDs = Set(shown.map(\.id))
        let fresh = all.filter { !shownIDs.contains($0.id) }
        let pool = fresh.count >= count ? fresh : all
        return Array(pool.shuffled(using: &generator).prefix(count))
    }

    /// Convenience for the view, which has no reason to own a generator.
    static func selection(count: Int = 3, excluding shown: [ExamplePrompt] = []) -> [ExamplePrompt] {
        var generator = SystemRandomNumberGenerator()
        return selection(count: count, excluding: shown, using: &generator)
    }

    private static let singleSwords: [ExamplePrompt] = [
        ExamplePrompt(emoji: "🗡️", text: "A blue sword, 20 damage, crafted from diamonds"),
        ExamplePrompt(emoji: "✨", text: "A purple sword named Starfall, crafted from amethyst"),
        ExamplePrompt(emoji: "🔥", text: "A red sword with 12 damage, crafted from blaze rods"),
        ExamplePrompt(emoji: "💚", text: "An emerald sword named Verdant Edge, 900 durability"),
        ExamplePrompt(emoji: "⚡", text: "A crackling redstone sword, 15 damage, 400 durability"),
        ExamplePrompt(emoji: "🌊", text: "A deep blue lapis sword named Tidecaller, 11 damage"),
        ExamplePrompt(emoji: "🌑", text: "A netherite sword named Ashfang with 28 damage"),
        ExamplePrompt(emoji: "🤍", text: "A pale quartz sword named Moonsliver, 9 damage")
    ]

    private static let materialSwordSets: [ExamplePrompt] = [
        ExamplePrompt(emoji: "🧊", text: "A Glacier ingot and matching sword, from 4 diamonds"),
        ExamplePrompt(emoji: "🍯", text: "A golden Sunforge ingot plus its matching sword"),
        ExamplePrompt(emoji: "🛡️", text: "An iron Ironheart ingot and sword with 14 damage"),
        ExamplePrompt(emoji: "💜", text: "An amethyst Duskshard ingot and its matching sword"),
        ExamplePrompt(emoji: "🔮", text: "A quartz ingot named Starlight plus a matching sword"),
        ExamplePrompt(emoji: "🌋", text: "A Cinder ingot from blaze rods, with an 18 damage sword"),
        ExamplePrompt(emoji: "💎", text: "An emerald ingot named Jade with a 750 durability sword"),
        ExamplePrompt(emoji: "🕳️", text: "A netherite Voidcore ingot and its matching sword")
    ]

    private static let toolSets: [ExamplePrompt] = [
        ExamplePrompt(emoji: "⛏️", text: "A redstone tool set: sword, pickaxe, axe, shovel, hoe"),
        ExamplePrompt(emoji: "🛠️", text: "A diamond tool set named Frostforge for a mining trip"),
        ExamplePrompt(emoji: "🌾", text: "A gold tool set named Harvest with a 600 durability hoe"),
        ExamplePrompt(emoji: "🪓", text: "A lapis tool set named Deepdelve with a 10 damage sword"),
        ExamplePrompt(emoji: "🧰", text: "An iron tool set named Toolbox with 800 durability"),
        ExamplePrompt(emoji: "💠", text: "An amethyst tool set named Geode, crafted from 6 shards"),
        ExamplePrompt(emoji: "🏔️", text: "A quartz tool set named Snowline for a snowy build"),
        ExamplePrompt(emoji: "🌟", text: "A netherite tool set named Starforged, 25 damage sword")
    ]

    private static let weaponSets: [ExamplePrompt] = [
        ExamplePrompt(emoji: "⚔️", text: "An emerald weapon set: sword, dagger, spear, and hammer"),
        ExamplePrompt(emoji: "🌩️", text: "A diamond weapon set named Stormbrand, 22 damage"),
        ExamplePrompt(emoji: "🔱", text: "A lapis weapon set named Tideguard with a long spear"),
        ExamplePrompt(emoji: "🔨", text: "A netherite weapon set named Doomforge, 30 damage"),
        ExamplePrompt(emoji: "🥷", text: "A gold weapon set named Nightblade with a quick dagger"),
        ExamplePrompt(emoji: "🎇", text: "A blaze rod weapon set named Emberstrike, 19 damage"),
        ExamplePrompt(emoji: "🦾", text: "An iron weapon set named Guardian, 1200 durability"),
        ExamplePrompt(emoji: "💫", text: "An amethyst weapon set named Prism with a heavy hammer"),
        ExamplePrompt(emoji: "🧨", text: "A redstone weapon set named Fuse with a fast dagger"),
        ExamplePrompt(emoji: "🪶", text: "A quartz weapon set named Featherfall, 8 damage spear")
    ]

    private static let armorSets: [ExamplePrompt] = [
        ExamplePrompt(emoji: "🛡️", text: "A netherite armor set named Warden, 20 protection"),
        ExamplePrompt(emoji: "🥇", text: "A gold armor set from 3 gold ingots, called Radiant"),
        ExamplePrompt(emoji: "💎", text: "A diamond armor set named Bastion, 900 durability"),
        ExamplePrompt(emoji: "🧊", text: "An amethyst armor set named Crystalguard, 16 protection"),
        ExamplePrompt(emoji: "🔩", text: "An iron armor set named Ironclad for early exploring"),
        ExamplePrompt(emoji: "⚡", text: "A redstone armor set named Pulseguard, 12 protection")
    ]

    private static let consumableSets: [ExamplePrompt] = [
        ExamplePrompt(emoji: "🍎", text: "A diamond consumable set: ingot, food, and fuel"),
        ExamplePrompt(emoji: "🍖", text: "An emerald consumable set named Verdant with food and fuel"),
        ExamplePrompt(emoji: "🔥", text: "A blaze rod consumable set named Ember with food and fuel"),
        ExamplePrompt(emoji: "❄️", text: "A quartz consumable set named Frostbite, food and fuel"),
        ExamplePrompt(emoji: "🧪", text: "A redstone consumable set named Pulse, food and fuel"),
        ExamplePrompt(emoji: "⛏️", text: "An iron consumable set named Ironclad with food and fuel"),
        ExamplePrompt(emoji: "💎", text: "A lapis consumable set named Deepsea, food and fuel"),
        ExamplePrompt(emoji: "🪙", text: "A gold consumable set named Gilded with food and fuel"),
        ExamplePrompt(emoji: "💜", text: "An amethyst consumable set named Geode, food and fuel"),
        ExamplePrompt(emoji: "🗿", text: "A netherite consumable set named Warden, food and fuel")
    ]

    private static let blockSets: [ExamplePrompt] = [
        ExamplePrompt(emoji: "🧱", text: "A diamond block set: Azure ingot plus storage block"),
        ExamplePrompt(emoji: "🏗️", text: "An emerald block set named Verdant with ingot and block"),
        ExamplePrompt(emoji: "🔥", text: "A blaze rod block set named Ember with ingot and block"),
        ExamplePrompt(emoji: "❄️", text: "A quartz block set named Frostbite with ingot and block"),
        ExamplePrompt(emoji: "🧪", text: "A redstone block set named Pulse with ingot and block"),
        ExamplePrompt(emoji: "⛓️", text: "An iron block set named Ironclad with ingot and block"),
        ExamplePrompt(emoji: "💙", text: "A lapis block set named Deepsea with ingot and block"),
        ExamplePrompt(emoji: "🪙", text: "A gold block set named Gilded with ingot and block"),
        ExamplePrompt(emoji: "💜", text: "An amethyst block set named Geode with ingot and block"),
        ExamplePrompt(emoji: "🗿", text: "A netherite block set named Warden with ingot and block")
    ]

    private static let furnaceSets: [ExamplePrompt] = [
        ExamplePrompt(emoji: "🔥", text: "A diamond furnace set: smelt Azure ingot and forge a sword"),
        ExamplePrompt(emoji: "🏺", text: "An emerald furnace set named Verdant smelted in a furnace"),
        ExamplePrompt(emoji: "⚒️", text: "A blaze rod furnace set named Ember with furnace-smelted ingot"),
        ExamplePrompt(emoji: "❄️", text: "A quartz furnace set named Frostbite smelted then forged"),
        ExamplePrompt(emoji: "🧪", text: "A redstone furnace set named Pulse with furnace recipe"),
        ExamplePrompt(emoji: "⛓️", text: "An iron furnace set named Ironclad smelted in furnace"),
        ExamplePrompt(emoji: "💙", text: "A lapis furnace set named Deepsea with furnace-smelted ingot"),
        ExamplePrompt(emoji: "🪙", text: "A gold furnace set named Gilded smelted sword set"),
        ExamplePrompt(emoji: "💜", text: "An amethyst furnace set named Geode with furnace ingot"),
        ExamplePrompt(emoji: "🗿", text: "A netherite furnace set named Warden smelted ingot plus sword")
    ]

    private static let smithingSets: [ExamplePrompt] = [
        ExamplePrompt(emoji: "⚒️", text: "A diamond smithing set: upgrade Azure sword at the smithing table"),
        ExamplePrompt(emoji: "🛡️", text: "An emerald smithing set named Verdant with smithing upgrade"),
        ExamplePrompt(emoji: "🔥", text: "A blaze rod smithing set named Ember with armor trim"),
        ExamplePrompt(emoji: "❄️", text: "A quartz smithing set named Frostbite with smithing sword"),
        ExamplePrompt(emoji: "🧪", text: "A redstone smithing set named Pulse upgraded on smithing table"),
        ExamplePrompt(emoji: "⛓️", text: "An iron smithing set named Ironclad with smithing trim"),
        ExamplePrompt(emoji: "💙", text: "A lapis smithing set named Deepsea with smithing upgrade"),
        ExamplePrompt(emoji: "🪙", text: "A gold smithing set named Gilded smithing table upgrade"),
        ExamplePrompt(emoji: "💜", text: "An amethyst smithing set named Geode with ward trim"),
        ExamplePrompt(emoji: "🗿", text: "A netherite smithing set named Warden upgraded via smithing")
    ]

    private static let brewingSets: [ExamplePrompt] = [
        ExamplePrompt(emoji: "🧪", text: "A diamond brewing set: brew Azure elixir at the brewing stand"),
        ExamplePrompt(emoji: "⚗️", text: "An emerald brewing set named Verdant with elixir brewed from ingot"),
        ExamplePrompt(emoji: "🔥", text: "A blaze rod brewing set named Ember with brewing-stand elixir"),
        ExamplePrompt(emoji: "❄️", text: "A quartz brewing set named Frostbite brewed then splashed"),
        ExamplePrompt(emoji: "💎", text: "A redstone brewing set named Pulse with brewing mix"),
        ExamplePrompt(emoji: "⛓️", text: "An iron brewing set named Ironclad brewed at the stand"),
        ExamplePrompt(emoji: "💙", text: "A lapis brewing set named Deepsea with potion elixir"),
        ExamplePrompt(emoji: "🪙", text: "A gold brewing set named Gilded brewed elixir from ingot"),
        ExamplePrompt(emoji: "💜", text: "An amethyst brewing set named Geode with brewing mix and container"),
        ExamplePrompt(emoji: "🗿", text: "A netherite brewing set named Warden brewed elixir splash")
    ]

    private static let oreSets: [ExamplePrompt] = [
        ExamplePrompt(emoji: "🪨", text: "A diamond ore set: Azure ingot plus ore block"),
        ExamplePrompt(emoji: "⛏️", text: "An emerald ore set named Verdant with ingot and ore"),
        ExamplePrompt(emoji: "🔥", text: "A blaze rod ore set named Ember with ingot and ore"),
        ExamplePrompt(emoji: "❄️", text: "A quartz ore set named Frostbite with ingot and ore"),
        ExamplePrompt(emoji: "🧪", text: "A redstone ore set named Pulse with ingot and ore")
    ]

    private static let cropSets: [ExamplePrompt] = [
        ExamplePrompt(emoji: "🌱", text: "A diamond crop set: Azure seeds plus crop and produce"),
        ExamplePrompt(emoji: "🌾", text: "An emerald crop set named Verdant with seeds and crop"),
        ExamplePrompt(emoji: "🔥", text: "A blaze rod crop set named Ember with seeds and crop"),
        ExamplePrompt(emoji: "❄️", text: "A quartz crop set named Frostbite seeds and harvest"),
        ExamplePrompt(emoji: "🧪", text: "A redstone crop set named Pulse with seeds, crop, and produce")
    ]
}
