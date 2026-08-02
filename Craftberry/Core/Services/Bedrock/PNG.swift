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
    public static func render(_ resource: VisualResource, pixelScale: Int = 1) -> Data {
        switch resource.kind {
        case .swordPixelArt: renderSword(color: resource.color, pixelScale: pixelScale)
        case .ingotPixelArt: renderIngot(color: resource.color, pixelScale: pixelScale)
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
