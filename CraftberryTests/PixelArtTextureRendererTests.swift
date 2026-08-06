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

    /// Every generated visual resource kind must render valid, correctly sized PNG bytes.
    /// Armor-layer kinds are worn-body textures at Bedrock's fixed 64x32 sheet size; every
    /// other kind is a 32x32 inventory icon.
    func testRenderProducesExpectedDimensionsForEveryVisualResourceKind() {
        for kind in VisualResourceKind.allCases {
            let resource = VisualResource(id: ContentID("test_\(kind.rawValue)"), kind: kind, color: .blue)
            let data = PixelArtTextureRenderer.render(resource)
            let expected: PNGDimensions = (kind == .armorLayerOne || kind == .armorLayerTwo)
                ? PNGDimensions(width: 64, height: 32)
                : PNGDimensions(width: 32, height: 32)
            XCTAssertEqual(Array(data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10], "missing PNG signature for \(kind)")
            XCTAssertEqual(PNGInspector.dimensions(of: data), expected, "unexpected dimensions for \(kind)")
        }
    }
}
