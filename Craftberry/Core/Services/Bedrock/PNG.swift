import Foundation

public struct PNGDimensions: Equatable, Sendable {
    public let width: Int
    public let height: Int
}

struct RGBA: Equatable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8

    static let transparent = RGBA(red: 0, green: 0, blue: 0, alpha: 0)
    static let outline = RGBA(red: 20, green: 24, blue: 34, alpha: 255)
    static let hilt = RGBA(red: 121, green: 75, blue: 43, alpha: 255)
    static let hiltHighlight = RGBA(red: 177, green: 122, blue: 73, alpha: 255)

    static let diamondMain = RGBA(red: 93, green: 219, blue: 213, alpha: 255)
    static let diamondHighlight = RGBA(red: 199, green: 255, blue: 250, alpha: 255)
    static let diamondShadow = RGBA(red: 45, green: 143, blue: 140, alpha: 255)

    static let emeraldMain = RGBA(red: 47, green: 189, blue: 91, alpha: 255)
    static let emeraldHighlight = RGBA(red: 141, green: 238, blue: 166, alpha: 255)
    static let emeraldShadow = RGBA(red: 22, green: 110, blue: 52, alpha: 255)

    static let ironMain = RGBA(red: 216, green: 216, blue: 207, alpha: 255)
    static let ironHighlight = RGBA(red: 245, green: 245, blue: 240, alpha: 255)
    static let ironShadow = RGBA(red: 150, green: 150, blue: 141, alpha: 255)

    static let goldMain = RGBA(red: 249, green: 219, blue: 76, alpha: 255)
    static let goldHighlight = RGBA(red: 255, green: 244, blue: 168, alpha: 255)
    static let goldShadow = RGBA(red: 178, green: 140, blue: 24, alpha: 255)

    static let netheriteMain = RGBA(red: 78, green: 68, blue: 71, alpha: 255)
    static let netheriteHighlight = RGBA(red: 130, green: 117, blue: 120, alpha: 255)
    static let netheriteShadow = RGBA(red: 41, green: 34, blue: 36, alpha: 255)

    static let lapisMain = RGBA(red: 33, green: 69, blue: 156, alpha: 255)
    static let lapisHighlight = RGBA(red: 90, green: 130, blue: 224, alpha: 255)
    static let lapisShadow = RGBA(red: 18, green: 38, blue: 92, alpha: 255)
    static let lapisFleck = RGBA(red: 220, green: 197, blue: 84, alpha: 255)

    static let quartzMain = RGBA(red: 233, green: 227, blue: 219, alpha: 255)
    static let quartzHighlight = RGBA(red: 255, green: 255, blue: 252, alpha: 255)
    static let quartzShadow = RGBA(red: 176, green: 168, blue: 158, alpha: 255)
    static let quartzVein = RGBA(red: 200, green: 150, blue: 120, alpha: 255)

    static let amethystMain = RGBA(red: 138, green: 88, blue: 210, alpha: 255)
    static let amethystHighlight = RGBA(red: 205, green: 172, blue: 250, alpha: 255)
    static let amethystShadow = RGBA(red: 79, green: 45, blue: 133, alpha: 255)

    static let blazeMain = RGBA(red: 240, green: 178, blue: 42, alpha: 255)
    static let blazeHighlight = RGBA(red: 255, green: 224, blue: 128, alpha: 255)
    static let blazeShadow = RGBA(red: 173, green: 96, blue: 20, alpha: 255)
    static let blazeCore = RGBA(red: 255, green: 246, blue: 200, alpha: 255)

    static let redstoneMain = RGBA(red: 176, green: 24, blue: 20, alpha: 255)
    static let redstoneHighlight = RGBA(red: 235, green: 84, blue: 56, alpha: 255)
    static let redstoneShadow = RGBA(red: 96, green: 12, blue: 12, alpha: 255)

    static let glowstoneMain = RGBA(red: 232, green: 173, blue: 84, alpha: 255)
    static let glowstoneHighlight = RGBA(red: 255, green: 232, blue: 156, alpha: 255)
    static let glowstoneShadow = RGBA(red: 178, green: 118, blue: 42, alpha: 255)

    static let gunpowderMain = RGBA(red: 94, green: 92, blue: 98, alpha: 255)
    static let gunpowderHighlight = RGBA(red: 140, green: 138, blue: 146, alpha: 255)
    static let gunpowderShadow = RGBA(red: 52, green: 50, blue: 56, alpha: 255)

    static let sugarMain = RGBA(red: 244, green: 244, blue: 238, alpha: 255)
    static let sugarHighlight = RGBA(red: 255, green: 255, blue: 255, alpha: 255)
    static let sugarShadow = RGBA(red: 202, green: 202, blue: 194, alpha: 255)

    static let blazePowderMain = RGBA(red: 235, green: 165, blue: 46, alpha: 255)
    static let blazePowderHighlight = RGBA(red: 255, green: 214, blue: 120, alpha: 255)
    static let blazePowderShadow = RGBA(red: 165, green: 96, blue: 22, alpha: 255)

    static let coalMain = RGBA(red: 46, green: 44, blue: 48, alpha: 255)
    static let coalHighlight = RGBA(red: 88, green: 85, blue: 92, alpha: 255)
    static let coalShadow = RGBA(red: 20, green: 19, blue: 22, alpha: 255)
    static let coalGleam = RGBA(red: 152, green: 165, blue: 178, alpha: 255)

    static let rawIronMain = RGBA(red: 216, green: 157, blue: 133, alpha: 255)
    static let rawIronHighlight = RGBA(red: 245, green: 202, blue: 180, alpha: 255)
    static let rawIronShadow = RGBA(red: 160, green: 104, blue: 84, alpha: 255)

    static let rawCopperMain = RGBA(red: 214, green: 129, blue: 84, alpha: 255)
    static let rawCopperHighlight = RGBA(red: 247, green: 176, blue: 128, alpha: 255)
    static let rawCopperShadow = RGBA(red: 150, green: 79, blue: 46, alpha: 255)

    static let rawGoldMain = RGBA(red: 226, green: 178, blue: 66, alpha: 255)
    static let rawGoldHighlight = RGBA(red: 255, green: 222, blue: 130, alpha: 255)
    static let rawGoldShadow = RGBA(red: 163, green: 121, blue: 32, alpha: 255)

    static let stickMain = RGBA(red: 158, green: 113, blue: 66, alpha: 255)
    static let stickHighlight = RGBA(red: 199, green: 155, blue: 100, alpha: 255)
    static let stickShadow = RGBA(red: 105, green: 71, blue: 38, alpha: 255)
}

enum SwordPalette {
    static func colors(for color: PixelArtColor) -> (main: RGBA, highlight: RGBA, shadow: RGBA) {
        switch color {
        case .red: (RGBA(red: 220, green: 58, blue: 58, alpha: 255), RGBA(red: 255, green: 132, blue: 124, alpha: 255), RGBA(red: 125, green: 35, blue: 48, alpha: 255))
        case .orange: (RGBA(red: 235, green: 126, blue: 45, alpha: 255), RGBA(red: 255, green: 190, blue: 102, alpha: 255), RGBA(red: 151, green: 65, blue: 35, alpha: 255))
        case .yellow: (RGBA(red: 235, green: 204, blue: 58, alpha: 255), RGBA(red: 255, green: 244, blue: 151, alpha: 255), RGBA(red: 146, green: 113, blue: 31, alpha: 255))
        case .lime: (RGBA(red: 151, green: 221, blue: 57, alpha: 255), RGBA(red: 213, green: 255, blue: 135, alpha: 255), RGBA(red: 65, green: 129, blue: 45, alpha: 255))
        case .green: (RGBA(red: 59, green: 169, blue: 93, alpha: 255), RGBA(red: 123, green: 229, blue: 141, alpha: 255), RGBA(red: 33, green: 91, blue: 57, alpha: 255))
        case .cyan: (RGBA(red: 52, green: 188, blue: 196, alpha: 255), RGBA(red: 137, green: 247, blue: 246, alpha: 255), RGBA(red: 30, green: 101, blue: 121, alpha: 255))
        case .blue: (RGBA(red: 65, green: 130, blue: 230, alpha: 255), RGBA(red: 141, green: 200, blue: 255, alpha: 255), RGBA(red: 41, green: 66, blue: 156, alpha: 255))
        case .purple: (RGBA(red: 132, green: 82, blue: 213, alpha: 255), RGBA(red: 202, green: 150, blue: 255, alpha: 255), RGBA(red: 72, green: 43, blue: 126, alpha: 255))
        case .magenta: (RGBA(red: 212, green: 72, blue: 180, alpha: 255), RGBA(red: 255, green: 147, blue: 228, alpha: 255), RGBA(red: 129, green: 38, blue: 116, alpha: 255))
        case .pink: (RGBA(red: 239, green: 122, blue: 169, alpha: 255), RGBA(red: 255, green: 193, blue: 211, alpha: 255), RGBA(red: 158, green: 63, blue: 111, alpha: 255))
        case .white: (RGBA(red: 226, green: 235, blue: 240, alpha: 255), RGBA(red: 255, green: 255, blue: 255, alpha: 255), RGBA(red: 122, green: 145, blue: 164, alpha: 255))
        case .gray: (RGBA(red: 145, green: 157, blue: 168, alpha: 255), RGBA(red: 204, green: 215, blue: 222, alpha: 255), RGBA(red: 75, green: 87, blue: 104, alpha: 255))
        case .black: (RGBA(red: 62, green: 69, blue: 85, alpha: 255), RGBA(red: 118, green: 132, blue: 150, alpha: 255), RGBA(red: 25, green: 29, blue: 42, alpha: 255))
        case .brown: (RGBA(red: 142, green: 87, blue: 52, alpha: 255), RGBA(red: 205, green: 143, blue: 90, alpha: 255), RGBA(red: 80, green: 48, blue: 37, alpha: 255))
        case .gold: (RGBA(red: 227, green: 176, blue: 48, alpha: 255), RGBA(red: 255, green: 229, blue: 119, alpha: 255), RGBA(red: 143, green: 96, blue: 27, alpha: 255))
        case .silver: (RGBA(red: 174, green: 193, blue: 207, alpha: 255), RGBA(red: 239, green: 250, blue: 255, alpha: 255), RGBA(red: 95, green: 117, blue: 139, alpha: 255))
        }
    }
}

public enum PixelArtTextureRenderer {
    /// Every vanilla material identifier `renderVanillaMaterial` has hand-authored art for,
    /// in the same order the switch below defines them. Single source of truth for tooling
    /// (previews, tests) that needs to enumerate the supported catalog.
    public static let supportedVanillaMaterialIdentifiers: [String] = [
        "minecraft:diamond", "minecraft:emerald", "minecraft:amethyst_shard",
        "minecraft:iron_ingot", "minecraft:gold_ingot", "minecraft:netherite_ingot",
        "minecraft:lapis_lazuli", "minecraft:quartz", "minecraft:blaze_rod",
        "minecraft:redstone", "minecraft:glowstone_dust", "minecraft:gunpowder",
        "minecraft:sugar", "minecraft:blaze_powder", "minecraft:stick",
        "minecraft:coal", "minecraft:raw_iron", "minecraft:raw_copper", "minecraft:raw_gold",
    ]

    public static func render(_ resource: VisualResource, pixelScale: Int = 1) -> Data {
        switch resource.kind {
        case .swordPixelArt: renderSword(color: resource.color, pixelScale: pixelScale)
        case .ingotPixelArt: renderIngot(color: resource.color, pixelScale: pixelScale)
        case .pickaxePixelArt: renderPickaxe(color: resource.color, pixelScale: pixelScale)
        case .axePixelArt: renderAxe(color: resource.color, pixelScale: pixelScale)
        case .shovelPixelArt: renderShovel(color: resource.color, pixelScale: pixelScale)
        case .hoePixelArt: renderHoe(color: resource.color, pixelScale: pixelScale)
        case .daggerPixelArt: renderDagger(color: resource.color, pixelScale: pixelScale)
        case .spearPixelArt: renderSpear(color: resource.color, pixelScale: pixelScale)
        case .hammerPixelArt: renderHammer(color: resource.color, pixelScale: pixelScale)
        }
    }

    /// Renders original pixel art for a vanilla material identifier (e.g. "minecraft:diamond").
    /// Returns nil for identifiers outside the supported vanilla material catalog.
    public static func renderVanillaMaterial(identifier: String, pixelScale: Int = 1) -> Data? {
        let path = identifier.split(separator: ":").last.map(String.init) ?? identifier
        switch path {
        case "diamond": return renderGem(main: .diamondMain, highlight: .diamondHighlight, shadow: .diamondShadow, pixelScale: pixelScale)
        case "emerald": return renderGem(main: .emeraldMain, highlight: .emeraldHighlight, shadow: .emeraldShadow, pixelScale: pixelScale)
        case "amethyst_shard": return renderAmethystShard(pixelScale: pixelScale)
        case "iron_ingot": return renderVanillaIngot(main: .ironMain, highlight: .ironHighlight, shadow: .ironShadow, pixelScale: pixelScale)
        case "gold_ingot": return renderVanillaIngot(main: .goldMain, highlight: .goldHighlight, shadow: .goldShadow, pixelScale: pixelScale)
        case "netherite_ingot": return renderVanillaIngot(main: .netheriteMain, highlight: .netheriteHighlight, shadow: .netheriteShadow, pixelScale: pixelScale)
        case "lapis_lazuli": return renderLapisLazuli(pixelScale: pixelScale)
        case "quartz": return renderQuartz(pixelScale: pixelScale)
        case "blaze_rod": return renderBlazeRod(pixelScale: pixelScale)
        case "redstone": return renderRedstoneDust(pixelScale: pixelScale)
        case "glowstone_dust": return renderDust(main: .glowstoneMain, highlight: .glowstoneHighlight, shadow: .glowstoneShadow, pixelScale: pixelScale)
        case "gunpowder": return renderDust(main: .gunpowderMain, highlight: .gunpowderHighlight, shadow: .gunpowderShadow, pixelScale: pixelScale)
        case "sugar": return renderDust(main: .sugarMain, highlight: .sugarHighlight, shadow: .sugarShadow, pixelScale: pixelScale)
        case "blaze_powder": return renderDust(main: .blazePowderMain, highlight: .blazePowderHighlight, shadow: .blazePowderShadow, pixelScale: pixelScale)
        case "stick": return renderStick(pixelScale: pixelScale)
        case "coal": return renderCoal(pixelScale: pixelScale)
        case "raw_iron": return renderRawOreChunk(main: .rawIronMain, highlight: .rawIronHighlight, shadow: .rawIronShadow, pixelScale: pixelScale)
        case "raw_copper": return renderRawOreChunk(main: .rawCopperMain, highlight: .rawCopperHighlight, shadow: .rawCopperShadow, pixelScale: pixelScale)
        case "raw_gold": return renderRawOreChunk(main: .rawGoldMain, highlight: .rawGoldHighlight, shadow: .rawGoldShadow, pixelScale: pixelScale)
        default: return nil
        }
    }

    private static func renderSword(color: PixelArtColor, pixelScale: Int) -> Data {
        let scale = max(1, pixelScale)
        let side = 32 * scale
        var pixels = Array(repeating: RGBA.transparent, count: side * side)
        let palette = SwordPalette.colors(for: color)

        func fill(_ x: Int, _ y: Int, _ width: Int, _ height: Int, _ color: RGBA) {
            for row in max(0, y * scale)..<min(side, (y + height) * scale) {
                for column in max(0, x * scale)..<min(side, (x + width) * scale) {
                    pixels[row * side + column] = color
                }
            }
        }

        fill(14, 3, 4, 1, .outline)
        fill(13, 4, 6, 3, .outline)
        fill(12, 7, 8, 16, .outline)
        fill(11, 22, 10, 3, .outline)
        fill(14, 25, 4, 5, .outline)

        fill(15, 4, 2, 3, palette.highlight)
        fill(14, 7, 3, 13, palette.main)
        fill(17, 7, 2, 13, palette.shadow)
        fill(13, 20, 5, 2, palette.main)
        fill(18, 20, 1, 2, palette.shadow)
        fill(12, 23, 8, 1, palette.highlight)
        fill(14, 25, 4, 3, .hilt)
        fill(15, 25, 1, 3, .hiltHighlight)
        fill(14, 28, 4, 1, .outline)

        return PNGEncoder.encode(width: side, height: side, pixels: pixels)
    }

    private static func renderIngot(color: PixelArtColor, pixelScale: Int) -> Data {
        let scale = max(1, pixelScale), side = 32 * scale
        var pixels = Array(repeating: RGBA.transparent, count: side * side)
        let palette = SwordPalette.colors(for: color)
        func fill(_ x: Int, _ y: Int, _ width: Int, _ height: Int, _ color: RGBA) {
            for row in max(0, y * scale)..<min(side, (y + height) * scale) {
                for column in max(0, x * scale)..<min(side, (x + width) * scale) { pixels[row * side + column] = color }
            }
        }
        fill(7, 11, 18, 10, .outline); fill(9, 9, 14, 2, .outline); fill(9, 21, 14, 2, .outline)
        fill(9, 11, 14, 8, palette.main); fill(11, 10, 10, 2, palette.highlight); fill(11, 19, 10, 2, palette.shadow)
        return PNGEncoder.encode(width: side, height: side, pixels: pixels)
    }

    private static func renderPickaxe(color: PixelArtColor, pixelScale: Int) -> Data {
        renderTool(color: color, pixelScale: pixelScale, head: [(8, 5, 16, 3), (6, 8, 4, 3), (22, 8, 4, 3), (11, 8, 10, 2)])
    }

    private static func renderAxe(color: PixelArtColor, pixelScale: Int) -> Data {
        renderTool(color: color, pixelScale: pixelScale, head: [(8, 5, 11, 4), (8, 9, 14, 5), (9, 14, 9, 3)])
    }

    private static func renderShovel(color: PixelArtColor, pixelScale: Int) -> Data {
        renderTool(color: color, pixelScale: pixelScale, head: [(12, 4, 8, 4), (11, 8, 10, 5), (13, 13, 6, 2)])
    }

    private static func renderHoe(color: PixelArtColor, pixelScale: Int) -> Data {
        renderTool(color: color, pixelScale: pixelScale, head: [(9, 5, 14, 3), (20, 8, 4, 3)])
    }

    private static func renderDagger(color: PixelArtColor, pixelScale: Int) -> Data {
        renderWeapon(color: color, pixelScale: pixelScale, blade: [(14, 6, 4, 10), (13, 9, 6, 5)], handle: [(15, 16, 2, 8), (12, 18, 8, 2)])
    }

    private static func renderSpear(color: PixelArtColor, pixelScale: Int) -> Data {
        renderWeapon(color: color, pixelScale: pixelScale, blade: [(14, 3, 4, 7), (13, 7, 6, 4)], handle: [(15, 11, 2, 17)])
    }

    private static func renderHammer(color: PixelArtColor, pixelScale: Int) -> Data {
        renderWeapon(color: color, pixelScale: pixelScale, blade: [(9, 5, 14, 5), (11, 10, 10, 3)], handle: [(15, 13, 3, 15)])
    }

    private static func renderTool(color: PixelArtColor, pixelScale: Int, head: [(x: Int, y: Int, width: Int, height: Int)]) -> Data {
        let scale = max(1, pixelScale), side = 32 * scale
        var pixels = Array(repeating: RGBA.transparent, count: side * side)
        let palette = SwordPalette.colors(for: color)
        func fill(_ x: Int, _ y: Int, _ width: Int, _ height: Int, _ color: RGBA) {
            for row in max(0, y * scale)..<min(side, (y + height) * scale) {
                for column in max(0, x * scale)..<min(side, (x + width) * scale) {
                    pixels[row * side + column] = color
                }
            }
        }
        for part in head {
            fill(part.x - 1, part.y - 1, part.width + 2, part.height + 2, .outline)
        }
        fill(15, 10, 4, 18, .outline)
        fill(16, 10, 2, 17, .hilt)
        fill(16, 10, 1, 17, .hiltHighlight)
        fill(15, 27, 4, 1, .outline)
        for (index, part) in head.enumerated() {
            fill(part.x, part.y, part.width, part.height, index == 0 ? palette.highlight : palette.main)
            fill(part.x, part.y + max(0, part.height - 1), part.width, 1, palette.shadow)
        }
        return PNGEncoder.encode(width: side, height: side, pixels: pixels)
    }

    private static func renderWeapon(color: PixelArtColor, pixelScale: Int, blade: [(x: Int, y: Int, width: Int, height: Int)], handle: [(x: Int, y: Int, width: Int, height: Int)]) -> Data {
        let scale = max(1, pixelScale), side = 32 * scale
        var pixels = Array(repeating: RGBA.transparent, count: side * side)
        let palette = SwordPalette.colors(for: color)
        func fill(_ x: Int, _ y: Int, _ width: Int, _ height: Int, _ color: RGBA) {
            for row in max(0, y * scale)..<min(side, (y + height) * scale) {
                for column in max(0, x * scale)..<min(side, (x + width) * scale) {
                    pixels[row * side + column] = color
                }
            }
        }
        for part in blade + handle {
            fill(part.x - 1, part.y - 1, part.width + 2, part.height + 2, .outline)
        }
        for part in handle {
            fill(part.x, part.y, part.width, part.height, .hilt)
            fill(part.x, part.y, max(1, part.width / 2), part.height, .hiltHighlight)
        }
        for (index, part) in blade.enumerated() {
            fill(part.x, part.y, part.width, part.height, index == 0 ? palette.highlight : palette.main)
            fill(part.x, part.y + max(0, part.height - 1), part.width, 1, palette.shadow)
        }
        return PNGEncoder.encode(width: side, height: side, pixels: pixels)
    }

    private static func renderGem(main: RGBA, highlight: RGBA, shadow: RGBA, pixelScale: Int) -> Data {
        let scale = max(1, pixelScale), side = 32 * scale
        var pixels = Array(repeating: RGBA.transparent, count: side * side)
        func fill(_ x: Int, _ y: Int, _ width: Int, _ height: Int, _ color: RGBA) {
            for row in max(0, y * scale)..<min(side, (y + height) * scale) {
                for column in max(0, x * scale)..<min(side, (x + width) * scale) { pixels[row * side + column] = color }
            }
        }
        fill(14, 6, 4, 2, .outline)
        fill(11, 8, 10, 2, .outline)
        fill(8, 10, 16, 4, .outline)
        fill(8, 14, 16, 6, .outline)
        fill(10, 20, 12, 4, .outline)
        fill(13, 24, 6, 2, .outline)

        fill(15, 7, 2, 1, highlight)
        fill(12, 9, 8, 1, highlight)
        fill(9, 11, 7, 3, highlight)
        fill(16, 11, 7, 3, main)
        fill(9, 15, 7, 5, main)
        fill(16, 15, 7, 5, shadow)
        fill(11, 21, 10, 3, shadow)
        fill(14, 25, 4, 1, shadow)
        return PNGEncoder.encode(width: side, height: side, pixels: pixels)
    }

    private static func renderAmethystShard(pixelScale: Int) -> Data {
        let scale = max(1, pixelScale), side = 32 * scale
        var pixels = Array(repeating: RGBA.transparent, count: side * side)
        func fill(_ x: Int, _ y: Int, _ width: Int, _ height: Int, _ color: RGBA) {
            for row in max(0, y * scale)..<min(side, (y + height) * scale) {
                for column in max(0, x * scale)..<min(side, (x + width) * scale) { pixels[row * side + column] = color }
            }
        }
        fill(9, 24, 14, 4, .outline)
        fill(11, 25, 10, 2, .amethystShadow)

        fill(14, 6, 4, 2, .outline)
        fill(13, 8, 6, 16, .outline)
        fill(14, 8, 2, 3, .amethystHighlight)
        fill(14, 11, 2, 10, .amethystMain)
        fill(16, 8, 2, 13, .amethystShadow)

        fill(8, 14, 3, 2, .outline)
        fill(7, 16, 5, 8, .outline)
        fill(8, 17, 2, 6, .amethystHighlight)
        fill(10, 17, 1, 6, .amethystShadow)

        fill(21, 14, 3, 2, .outline)
        fill(20, 16, 5, 8, .outline)
        fill(21, 17, 2, 6, .amethystMain)
        fill(23, 17, 1, 6, .amethystShadow)
        return PNGEncoder.encode(width: side, height: side, pixels: pixels)
    }

    private static func renderVanillaIngot(main: RGBA, highlight: RGBA, shadow: RGBA, pixelScale: Int) -> Data {
        let scale = max(1, pixelScale), side = 32 * scale
        var pixels = Array(repeating: RGBA.transparent, count: side * side)
        func fill(_ x: Int, _ y: Int, _ width: Int, _ height: Int, _ color: RGBA) {
            for row in max(0, y * scale)..<min(side, (y + height) * scale) {
                for column in max(0, x * scale)..<min(side, (x + width) * scale) { pixels[row * side + column] = color }
            }
        }
        fill(7, 11, 18, 10, .outline); fill(9, 9, 14, 2, .outline); fill(9, 21, 14, 2, .outline)
        fill(9, 11, 14, 8, main); fill(11, 10, 10, 2, highlight); fill(11, 19, 10, 2, shadow)
        return PNGEncoder.encode(width: side, height: side, pixels: pixels)
    }

    private static func renderLapisLazuli(pixelScale: Int) -> Data {
        renderDust(main: .lapisMain, highlight: .lapisHighlight, shadow: .lapisShadow, pixelScale: pixelScale, flecks: [(24, 10), (21, 12), (15, 16), (9, 23)], fleckColor: .lapisFleck)
    }

    private static func renderQuartz(pixelScale: Int) -> Data {
        let scale = max(1, pixelScale), side = 32 * scale
        var pixels = Array(repeating: RGBA.transparent, count: side * side)
        func fill(_ x: Int, _ y: Int, _ width: Int, _ height: Int, _ color: RGBA) {
            for row in max(0, y * scale)..<min(side, (y + height) * scale) {
                for column in max(0, x * scale)..<min(side, (x + width) * scale) { pixels[row * side + column] = color }
            }
        }
        fill(13, 5, 6, 3, .outline)
        fill(11, 8, 10, 16, .outline)
        fill(9, 22, 14, 4, .outline)

        fill(13, 8, 3, 4, .quartzHighlight)
        fill(13, 12, 3, 10, .quartzMain)
        fill(17, 8, 3, 14, .quartzShadow)
        fill(15, 14, 1, 8, .quartzVein)
        fill(10, 23, 12, 2, .quartzShadow)
        return PNGEncoder.encode(width: side, height: side, pixels: pixels)
    }

    private static func renderBlazeRod(pixelScale: Int) -> Data {
        let scale = max(1, pixelScale), side = 32 * scale
        var pixels = Array(repeating: RGBA.transparent, count: side * side)
        func fill(_ x: Int, _ y: Int, _ width: Int, _ height: Int, _ color: RGBA) {
            for row in max(0, y * scale)..<min(side, (y + height) * scale) {
                for column in max(0, x * scale)..<min(side, (x + width) * scale) { pixels[row * side + column] = color }
            }
        }
        fill(13, 4, 6, 24, .outline)
        fill(14, 5, 4, 22, .blazeMain)
        fill(14, 5, 2, 22, .blazeHighlight)
        fill(16, 5, 2, 22, .blazeShadow)
        fill(14, 9, 4, 2, .blazeCore)
        fill(14, 15, 4, 2, .blazeCore)
        fill(14, 21, 4, 2, .blazeCore)
        return PNGEncoder.encode(width: side, height: side, pixels: pixels)
    }

    private static func renderRedstoneDust(pixelScale: Int) -> Data {
        renderDust(main: .redstoneMain, highlight: .redstoneHighlight, shadow: .redstoneShadow, pixelScale: pixelScale)
    }

    /// Loose granular materials (dyes, powders) share this pile-of-grains silhouette: a
    /// cluster of rounded clumps scattered along the diagonal, each stamped from an
    /// outlined circular blob rather than a snapped rectangle, so the icon reads as
    /// scattered dust instead of a dotted square.
    private static func renderDust(main: RGBA, highlight: RGBA, shadow: RGBA, pixelScale: Int, flecks: [(x: Int, y: Int)] = [], fleckColor: RGBA = .transparent) -> Data {
        let scale = max(1, pixelScale), side = 32 * scale
        var pixels = Array(repeating: RGBA.transparent, count: side * side)

        func set(_ x: Int, _ y: Int, _ color: RGBA) {
            guard x >= 0, x < 32, y >= 0, y < 32 else { return }
            for row in (y * scale)..<((y + 1) * scale) {
                for column in (x * scale)..<((x + 1) * scale) {
                    pixels[row * side + column] = color
                }
            }
        }

        func blob(_ cx: Int, _ cy: Int, radius: Double) -> [(x: Int, y: Int)] {
            let r = Int(radius.rounded(.up))
            var offsets: [(x: Int, y: Int)] = []
            for dy in -r...r {
                for dx in -r...r {
                    if Double(dx * dx + dy * dy) <= radius * radius {
                        offsets.append((cx + dx, cy + dy))
                    }
                }
            }
            return offsets
        }

        // A pile of six clumps rising diagonally from the bottom-left, mirroring the
        // silhouette of Minecraft's own dust/powder items rather than a filled square.
        let clumps: [(x: Int, y: Int, radius: Double, tone: RGBA)] = [
            (9, 24, 3.4, main),
            (13, 21, 2.6, shadow),
            (15, 17, 4.2, main),
            (19, 18, 2.8, shadow),
            (20, 13, 3.6, highlight),
            (24, 10, 2.4, main),
            (11, 17, 2.0, highlight),
        ]

        for clump in clumps {
            for offset in blob(clump.x, clump.y, radius: clump.radius + 1) {
                set(offset.x, offset.y, .outline)
            }
        }
        for clump in clumps {
            for offset in blob(clump.x, clump.y, radius: clump.radius) {
                set(offset.x, offset.y, clump.tone)
            }
        }
        for fleck in flecks {
            set(fleck.x, fleck.y, fleckColor)
        }
        return PNGEncoder.encode(width: side, height: side, pixels: pixels)
    }

    private static func renderStick(pixelScale: Int) -> Data {
        let scale = max(1, pixelScale), side = 32 * scale
        var pixels = Array(repeating: RGBA.transparent, count: side * side)
        func fill(_ x: Int, _ y: Int, _ width: Int, _ height: Int, _ color: RGBA) {
            for row in max(0, y * scale)..<min(side, (y + height) * scale) {
                for column in max(0, x * scale)..<min(side, (x + width) * scale) { pixels[row * side + column] = color }
            }
        }
        let segments: [(x: Int, y: Int)] = [(9, 23), (11, 21), (13, 19), (15, 17), (17, 15), (19, 13), (21, 11), (23, 9)]
        for segment in segments {
            fill(segment.x - 1, segment.y - 1, 5, 5, .outline)
        }
        for segment in segments {
            fill(segment.x, segment.y, 3, 3, .stickMain)
        }
        fill(9, 23, 2, 2, .stickShadow)
        fill(22, 9, 2, 2, .stickHighlight)
        return PNGEncoder.encode(width: side, height: side, pixels: pixels)
    }

    /// Coal and the raw ores (iron/copper/gold) share this squat, jagged rock silhouette —
    /// a single solid lump with faceted shading, distinct from the cut-gem and ingot shapes
    /// used for their refined/smelted forms.
    private static func renderRawOreChunk(main: RGBA, highlight: RGBA, shadow: RGBA, pixelScale: Int, flecks: [(x: Int, y: Int)] = [], fleckColor: RGBA = .transparent) -> Data {
        let scale = max(1, pixelScale), side = 32 * scale
        var pixels = Array(repeating: RGBA.transparent, count: side * side)
        func fill(_ x: Int, _ y: Int, _ width: Int, _ height: Int, _ color: RGBA) {
            for row in max(0, y * scale)..<min(side, (y + height) * scale) {
                for column in max(0, x * scale)..<min(side, (x + width) * scale) { pixels[row * side + column] = color }
            }
        }
        func set(_ x: Int, _ y: Int, _ color: RGBA) {
            fill(x, y, 1, 1, color)
        }

        // Jagged rock silhouette, widest through the middle, narrowing to nubs top and bottom.
        fill(13, 6, 7, 2, .outline)
        fill(9, 8, 16, 2, .outline)
        fill(6, 10, 21, 3, .outline)
        fill(5, 13, 23, 6, .outline)
        fill(6, 19, 21, 3, .outline)
        fill(8, 22, 17, 3, .outline)
        fill(11, 25, 11, 2, .outline)

        // Upper-left facet catches the light.
        fill(14, 7, 5, 1, highlight)
        fill(10, 9, 11, 2, highlight)
        fill(7, 11, 11, 4, highlight)
        fill(6, 15, 7, 6, highlight)

        // Center mass in the base tone.
        fill(18, 9, 6, 2, main)
        fill(18, 11, 10, 4, main)
        fill(13, 15, 15, 7, main)
        fill(9, 21, 10, 4, main)

        // Lower-right facet in shadow.
        fill(22, 15, 6, 7, shadow)
        fill(19, 21, 8, 4, shadow)
        fill(9, 23, 15, 2, shadow)
        fill(12, 25, 8, 1, shadow)

        for fleck in flecks { set(fleck.x, fleck.y, fleckColor) }
        return PNGEncoder.encode(width: side, height: side, pixels: pixels)
    }

    private static func renderCoal(pixelScale: Int) -> Data {
        renderRawOreChunk(main: .coalMain, highlight: .coalHighlight, shadow: .coalShadow, pixelScale: pixelScale, flecks: [(12, 12), (21, 13), (16, 19)], fleckColor: .coalGleam)
    }
}

enum PNGEncoder {
    static func encode(width: Int, height: Int, pixels: [RGBA]) -> Data {
        var raw = Data()
        for row in 0..<height {
            raw.append(0)
            for column in 0..<width {
                let pixel = pixels[row * width + column]
                raw.append(contentsOf: [pixel.red, pixel.green, pixel.blue, pixel.alpha])
            }
        }

        var ihdr = Data()
        ihdr.appendBigEndian(UInt32(width))
        ihdr.appendBigEndian(UInt32(height))
        ihdr.append(contentsOf: [8, 6, 0, 0, 0])

        var png = Data([137, 80, 78, 71, 13, 10, 26, 10])
        appendChunk(type: "IHDR", data: ihdr, to: &png)
        appendChunk(type: "IDAT", data: zlibStore(raw), to: &png)
        appendChunk(type: "IEND", data: Data(), to: &png)
        return png
    }

    private static func zlibStore(_ raw: Data) -> Data {
        var output = Data([0x78, 0x01])
        var offset = 0
        while offset < raw.count {
            let length = min(65_535, raw.count - offset)
            output.append(offset + length == raw.count ? UInt8(1) : UInt8(0))
            output.appendLittleEndian(UInt16(length))
            output.appendLittleEndian(UInt16.max - UInt16(length))
            output.append(raw.subdata(in: offset..<(offset + length)))
            offset += length
        }
        output.appendBigEndian(Checksum.adler32(raw))
        return output
    }

    private static func appendChunk(type: String, data: Data, to png: inout Data) {
        let typeData = Data(type.utf8)
        png.appendBigEndian(UInt32(data.count))
        png.append(typeData)
        png.append(data)
        var checksumInput = typeData
        checksumInput.append(data)
        png.appendBigEndian(Checksum.crc32(checksumInput))
    }
}

public enum PNGInspector {
    public static func dimensions(of data: Data) -> PNGDimensions? {
        guard data.count >= 24,
              Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10] else { return nil }
        let width = (UInt32(data[16]) << 24) | (UInt32(data[17]) << 16) | (UInt32(data[18]) << 8) | UInt32(data[19])
        let height = (UInt32(data[20]) << 24) | (UInt32(data[21]) << 16) | (UInt32(data[22]) << 8) | UInt32(data[23])
        return PNGDimensions(width: Int(width), height: Int(height))
    }
}
