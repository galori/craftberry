import Foundation
import XCTest
#if canImport(CraftberryCore)
@testable import CraftberryCore
#else
@testable import Craftberry
#endif

final class PixelArtTextureRendererTests: XCTestCase {
    func testRenderVanillaMaterialProducesThirtyTwoByThirtyTwoArtworkForEveryCatalogIdentifier() throws {
        let identifiers = [
            "minecraft:amethyst_shard", "minecraft:blaze_rod", "minecraft:diamond",
            "minecraft:emerald", "minecraft:gold_ingot", "minecraft:iron_ingot",
            "minecraft:lapis_lazuli", "minecraft:netherite_ingot", "minecraft:quartz",
            "minecraft:redstone", "minecraft:stick"
        ]

        for identifier in identifiers {
            let data = try XCTUnwrap(PixelArtTextureRenderer.renderVanillaMaterial(identifier: identifier), "expected artwork for \(identifier)")
            XCTAssertEqual(PNGInspector.dimensions(of: data), PNGDimensions(width: 32, height: 32), "unexpected dimensions for \(identifier)")
        }
    }

    func testRenderVanillaMaterialReturnsNilForUnrecognizedIdentifier() {
        XCTAssertNil(PixelArtTextureRenderer.renderVanillaMaterial(identifier: "minecraft:oak_planks"))
    }

    func testRenderVanillaMaterialScalesWithPixelScale() throws {
        let data = try XCTUnwrap(PixelArtTextureRenderer.renderVanillaMaterial(identifier: "minecraft:diamond", pixelScale: 4))
        XCTAssertEqual(PNGInspector.dimensions(of: data), PNGDimensions(width: 128, height: 128))
    }
}
