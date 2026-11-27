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
    /// Armor-layer kinds are worn-body textures at Bedrock's fixed 64x32 sheet size, as is the
    /// entity body texture (pig-geometry UV sheet); blockTerrain is a 16x16 terrain tile;
    /// every other kind is a 32x32 inventory icon.
    func testRenderProducesExpectedDimensionsForEveryVisualResourceKind() {
        for kind in VisualResourceKind.allCases {
            let resource = VisualResource(id: ContentID("test_\(kind.rawValue)"), kind: kind, color: .blue)
            let data = PixelArtTextureRenderer.render(resource)
            let expected: PNGDimensions
            switch kind {
            case .armorLayerOne, .armorLayerTwo, .entityTexture: expected = PNGDimensions(width: 64, height: 32)
            case .blockTerrain, .oreTerrain, .cropTerrain: expected = PNGDimensions(width: 16, height: 16)
            default: expected = PNGDimensions(width: 32, height: 32)
            }
            XCTAssertEqual(Array(data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10], "missing PNG signature for \(kind)")
            XCTAssertEqual(PNGInspector.dimensions(of: data), expected, "unexpected dimensions for \(kind)")
        }
    }

    func testImportedPixelDataReplacesGeneratedItemArtAndScalesForPackIcon() throws {
        var sourcePixels = Data(capacity: 32 * 32 * 4)
        for index in 0..<(32 * 32) {
            sourcePixels.append(contentsOf: [
                UInt8(index % 256),
                UInt8((index * 3) % 256),
                UInt8((index * 7) % 256),
                255
            ])
        }
        let visual = VisualResource(
            id: ContentID("custom_sword"),
            kind: .swordPixelArt,
            color: .blue,
            customPixels: sourcePixels
        )

        let icon = PixelArtTextureRenderer.render(visual)
        let packIcon = PixelArtTextureRenderer.render(visual, pixelScale: 4)

        XCTAssertEqual(PNGInspector.dimensions(of: icon), PNGDimensions(width: 32, height: 32))
        XCTAssertEqual(PNGInspector.dimensions(of: packIcon), PNGDimensions(width: 128, height: 128))
        let canonicalPixels = try PixelArtTextureImporter.canonicalPixels(fromPNG: icon)
        var firstDifference: Int?
        for index in 0..<sourcePixels.count where canonicalPixels[index] != sourcePixels[index] {
            firstDifference = index
            break
        }
        XCTAssertNil(
            firstDifference,
            "First differing byte is \(String(describing: firstDifference)). Expected \(Array(sourcePixels.prefix(4))), got \(Array(canonicalPixels.prefix(4)))."
        )
    }

    func testPNGTextureImporterRejectsNonSquareOrInvalidPNG() throws {
        let validPixels = Array(repeating: RGBA(red: 255, green: 0, blue: 0, alpha: 255), count: 16 * 16)
        let undersized = PNGEncoder.encode(width: 16, height: 16, pixels: validPixels)

        XCTAssertThrowsError(try PixelArtTextureImporter.canonicalPixels(fromPNG: undersized)) {
            XCTAssertEqual($0 as? PixelArtTextureImportError, .incorrectDimensions)
        }
        XCTAssertThrowsError(try PixelArtTextureImporter.canonicalPixels(fromPNG: Data("not a PNG".utf8))) {
            XCTAssertEqual($0 as? PixelArtTextureImportError, .invalidPNG)
        }
        XCTAssertThrowsError(try PixelArtTextureImporter.canonicalPixels(fromPNG: Data(repeating: 0, count: 300_000))) {
            XCTAssertEqual($0 as? PixelArtTextureImportError, .fileTooLarge)
        }
    }

    func testPNGFileReaderReturnsSmallFilesAndRejectsOversizedFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let png = PixelArtTextureRenderer.render(VisualResource(
            id: ContentID("file_reader_sword"),
            kind: .swordPixelArt,
            color: .cyan
        ))
        let validURL = directory.appending(path: "valid.png")
        try png.write(to: validURL)
        XCTAssertEqual(try PixelArtTextureImporter.readPNGData(from: validURL), png)

        let oversizedURL = directory.appending(path: "oversized.png")
        try Data(repeating: 0, count: PixelArtTextureImporter.maximumFileSize + 1).write(to: oversizedURL)
        XCTAssertThrowsError(try PixelArtTextureImporter.readPNGData(from: oversizedURL)) {
            XCTAssertEqual($0 as? PixelArtTextureImportError, .fileTooLarge)
        }
    }

    func testVisualResourceFromOlderSidecarDecodesWithoutImportedPixels() throws {
        let data = Data(#"{"id":"sword","kind":"swordPixelArt","color":"blue"}"#.utf8)
        let visual = try JSONDecoder().decode(VisualResource.self, from: data)
        XCTAssertNil(visual.customPixels)
    }
}
