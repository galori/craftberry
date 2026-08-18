import Foundation

enum MCStructureError: Error {
    case invalidSize
}

struct MCStructureEncoder {
    static func encodeHut(blockIdentifier: String, size: [Int] = [3, 3, 3]) throws -> Data {
        guard size == [3, 3, 3] else { throw MCStructureError.invalidSize }
        // Deterministic 3x3 hut: floor and roof solid, middle layer walls with doorway
        // Palette: 0 = minecraft:air, 1 = custom block
        let volume = 27
        var primaryIndices: [Int32] = Array(repeating: 0, count: volume)
        for y in 0..<3 {
            for z in 0..<3 {
                for x in 0..<3 {
                    let idx = y * 9 + z * 3 + x
                    var paletteIndex: Int32 = 0
                    if y == 0 {
                        paletteIndex = 1 // floor solid
                    } else if y == 2 {
                        paletteIndex = 1 // roof solid
                    } else {
                        // y == 1 middle: walls on perimeter, except doorway at (1,1,0) north face
                        let isPerimeter = z == 0 || z == 2 || x == 0 || x == 2
                        if isPerimeter && !(x == 1 && z == 0) {
                            paletteIndex = 1
                        } else {
                            paletteIndex = 0
                        }
                    }
                    primaryIndices[idx] = paletteIndex
                }
            }
        }
        let secondaryIndices: [Int32] = Array(repeating: -1, count: volume)

        var writer = NBTWriter()
        // Root compound (unnamed)
        writer.writeTagHeader(type: 10, name: "")
        // format_version INT
        writer.writeTagHeader(type: 3, name: "format_version")
        writer.writeInt(1)
        // size LIST<INT>
        writer.writeTagHeader(type: 9, name: "size")
        writer.writeListHeader(elementType: 3, count: 3)
        for v in size { writer.writeInt(Int32(v)) }
        // structure COMPOUND
        writer.writeTagHeader(type: 10, name: "structure")
        // block_indices LIST<LIST<INT>>
        writer.writeTagHeader(type: 9, name: "block_indices")
        writer.writeListHeader(elementType: 9, count: 2)
        // first layer
        writer.writeListHeader(elementType: 3, count: Int32(volume))
        for v in primaryIndices { writer.writeInt(v) }
        // second layer
        writer.writeListHeader(elementType: 3, count: Int32(volume))
        for v in secondaryIndices { writer.writeInt(v) }
        // entities LIST<COMPOUND> empty
        writer.writeTagHeader(type: 9, name: "entities")
        writer.writeListHeader(elementType: 10, count: 0)
        // palette COMPOUND
        writer.writeTagHeader(type: 10, name: "palette")
        writer.writeTagHeader(type: 10, name: "default")
        // block_palette LIST<COMPOUND>
        writer.writeTagHeader(type: 9, name: "block_palette")
        writer.writeListHeader(elementType: 10, count: 2)
        // air entry
        writer.writeCompoundEntry {
            $0.writeTagHeader(type: 8, name: "name")
            $0.writeString("minecraft:air")
            $0.writeTagHeader(type: 10, name: "states")
            $0.writeCompoundEnd()
            $0.writeTagHeader(type: 3, name: "version")
            $0.writeInt(18139408)
        }
        // custom block entry
        writer.writeCompoundEntry {
            $0.writeTagHeader(type: 8, name: "name")
            $0.writeString(blockIdentifier)
            $0.writeTagHeader(type: 10, name: "states")
            $0.writeCompoundEnd()
            $0.writeTagHeader(type: 3, name: "version")
            $0.writeInt(18139408)
        }
        // block_position_data COMPOUND empty
        writer.writeTagHeader(type: 10, name: "block_position_data")
        writer.writeCompoundEnd()
        // close default
        writer.writeCompoundEnd()
        // close palette
        writer.writeCompoundEnd()
        // close structure
        writer.writeCompoundEnd()
        // structure_world_origin LIST<INT>
        writer.writeTagHeader(type: 9, name: "structure_world_origin")
        writer.writeListHeader(elementType: 3, count: 3)
        writer.writeInt(0); writer.writeInt(0); writer.writeInt(0)
        // END root
        writer.writeCompoundEnd()
        return writer.data
    }
}

private struct NBTWriter {
    var data = Data()

    mutating func writeTagHeader(type: UInt8, name: String) {
        data.append(type)
        writeString(name)
    }

    mutating func writeCompoundEnd() {
        data.append(0) // TAG_End
    }

    mutating func writeString(_ value: String) {
        let bytes = Array(value.utf8)
        let len = UInt16(bytes.count)
        data.append(UInt8(truncatingIfNeeded: len & 0xFF))
        data.append(UInt8(truncatingIfNeeded: (len >> 8) & 0xFF))
        data.append(contentsOf: bytes)
    }

    mutating func writeInt(_ value: Int32) {
        let v = UInt32(bitPattern: value)
        data.append(UInt8(truncatingIfNeeded: v & 0xFF))
        data.append(UInt8(truncatingIfNeeded: (v >> 8) & 0xFF))
        data.append(UInt8(truncatingIfNeeded: (v >> 16) & 0xFF))
        data.append(UInt8(truncatingIfNeeded: (v >> 24) & 0xFF))
    }

    mutating func writeListHeader(elementType: UInt8, count: Int32) {
        data.append(elementType)
        writeInt(count)
    }

    mutating func writeCompoundEntry(_ build: (inout NBTWriter) -> Void) {
        var inner = NBTWriter()
        build(&inner)
        inner.writeCompoundEnd()
        // inner already includes its content but not outer header; we append raw without extra
        data.append(inner.data)
    }
}
