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
/// `GeneratedVanillaItemCatalog.materialSources`, attack 1–30, durability 50–2,000, and one of
/// the supported project kinds (single sword, ingot + sword, tool set, weapon set). Add a handful
/// of prompts here whenever a new capability ships — see AGENTS.md.
enum ExamplePromptLibrary {
    static let all: [ExamplePrompt] = singleSwords + materialSwordSets + toolSets + weaponSets

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
}
