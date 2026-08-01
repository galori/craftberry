import Foundation

public struct ZipArchiveEntry: Equatable, Sendable {
    public let path: String
    public let data: Data

    public init(path: String, data: Data) {
        self.path = path
        self.data = data
    }
}

public enum ZipArchiveError: LocalizedError {
    case invalidPath(String)
    case archiveTooLarge
    case malformedArchive
    case compressedEntryUnsupported

    public var errorDescription: String? {
        switch self {
        case .invalidPath(let path): "Invalid archive path: \(path)"
        case .archiveTooLarge: "The add-on is too large to package."
        case .malformedArchive: "The generated archive is malformed."
        case .compressedEntryUnsupported: "Compressed archive entries are not supported."
        }
    }
}

public enum ZipArchiveWriter {
    public static func archive(entries: [ZipArchiveEntry]) throws -> Data {
        var output = Data()
        var centralDirectory = Data()

        for entry in entries {
            guard isSafe(path: entry.path) else { throw ZipArchiveError.invalidPath(entry.path) }
            guard entry.data.count <= Int(UInt32.max), output.count <= Int(UInt32.max) else {
                throw ZipArchiveError.archiveTooLarge
            }

            let pathData = Data(entry.path.utf8)
            let checksum = Checksum.crc32(entry.data)
            let localOffset = UInt32(output.count)
            let size = UInt32(entry.data.count)

            output.appendLittleEndian(UInt32(0x0403_4B50))
            output.appendLittleEndian(UInt16(20))
            output.appendLittleEndian(UInt16(0))
            output.appendLittleEndian(UInt16(0))
            output.appendLittleEndian(UInt16(0))
            output.appendLittleEndian(UInt16(0))
            output.appendLittleEndian(checksum)
            output.appendLittleEndian(size)
            output.appendLittleEndian(size)
            output.appendLittleEndian(UInt16(pathData.count))
            output.appendLittleEndian(UInt16(0))
            output.append(pathData)
            output.append(entry.data)

            centralDirectory.appendLittleEndian(UInt32(0x0201_4B50))
            centralDirectory.appendLittleEndian(UInt16(20))
            centralDirectory.appendLittleEndian(UInt16(20))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(checksum)
            centralDirectory.appendLittleEndian(size)
            centralDirectory.appendLittleEndian(size)
            centralDirectory.appendLittleEndian(UInt16(pathData.count))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt32(0))
            centralDirectory.appendLittleEndian(localOffset)
            centralDirectory.append(pathData)
        }

        guard entries.count <= Int(UInt16.max), centralDirectory.count <= Int(UInt32.max) else {
            throw ZipArchiveError.archiveTooLarge
        }
        let centralOffset = UInt32(output.count)
        output.append(centralDirectory)
        output.appendLittleEndian(UInt32(0x0605_4B50))
        output.appendLittleEndian(UInt16(0))
        output.appendLittleEndian(UInt16(0))
        output.appendLittleEndian(UInt16(entries.count))
        output.appendLittleEndian(UInt16(entries.count))
        output.appendLittleEndian(UInt32(centralDirectory.count))
        output.appendLittleEndian(centralOffset)
        output.appendLittleEndian(UInt16(0))
        return output
    }

    private static func isSafe(path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
    }
}

public enum ZipArchiveReader {
    public static func readEntries(at url: URL) throws -> [ZipArchiveEntry] {
        try readEntries(data: Data(contentsOf: url))
    }

    public static func readEntries(data: Data) throws -> [ZipArchiveEntry] {
        var entries: [ZipArchiveEntry] = []
        var offset = 0

        while offset + 4 <= data.count, data.littleEndianUInt32(at: offset) == 0x0403_4B50 {
            guard let method = data.littleEndianUInt16(at: offset + 8), method == 0,
                  let compressedSize = data.littleEndianUInt32(at: offset + 18),
                  let uncompressedSize = data.littleEndianUInt32(at: offset + 22),
                  compressedSize == uncompressedSize,
                  let pathLength = data.littleEndianUInt16(at: offset + 26),
                  let extraLength = data.littleEndianUInt16(at: offset + 28) else {
                throw ZipArchiveError.malformedArchive
            }
            let pathStart = offset + 30
            let pathEnd = pathStart + Int(pathLength)
            let bodyStart = pathEnd + Int(extraLength)
            let bodyEnd = bodyStart + Int(compressedSize)
            guard bodyEnd <= data.count,
                  let path = String(data: data.subdata(in: pathStart..<pathEnd), encoding: .utf8) else {
                throw ZipArchiveError.malformedArchive
            }
            entries.append(ZipArchiveEntry(path: path, data: data.subdata(in: bodyStart..<bodyEnd)))
            offset = bodyEnd
        }

        guard !entries.isEmpty else { throw ZipArchiveError.malformedArchive }
        return entries
    }
}
