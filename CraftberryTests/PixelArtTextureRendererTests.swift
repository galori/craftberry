import Foundation
import XCTest
#if canImport(CraftberryCore)
@testable import CraftberryCore
#else
@testable import Craftberry
#endif

final class PixelArtTextureRendererTests: XCTestCase {
    func testRenderVanillaMaterialProducesThirtyTwoByThirtyTwoArtworkForEveryCatalogIdentifier() throws {
        for identifier in PixelArtTextureRenderer.supportedVanillaMaterialIdentifiers {
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
