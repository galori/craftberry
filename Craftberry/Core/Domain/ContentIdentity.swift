import Foundation

public enum PixelArtColor: String, CaseIterable, Codable, Sendable {
    case red, orange, yellow, lime, green, cyan, blue, purple
    case magenta, pink, white, gray, black, brown, gold, silver
}

public struct BedrockIdentifier: Equatable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var pathComponent: String {
        String(rawValue.split(separator: ":", maxSplits: 1).last ?? "custom_item")
    }

    public static func make(displayName: String, suffix: String? = nil) -> BedrockIdentifier {
        let latin = displayName.applyingTransform(.toLatin, reverse: false) ?? displayName
        let lowercased = latin.lowercased()
        let mapped = lowercased.unicodeScalars.map { scalar -> Character in
            switch scalar.value {
            case 97...122, 48...57: Character(String(scalar))
            default: "_"
            }
        }
        let collapsed = String(mapped).split(separator: "_", omittingEmptySubsequences: true).joined(separator: "_")
        let stem = collapsed.isEmpty ? "custom_item" : String(collapsed.prefix(40))
        let safeSuffix = suffix.map { String($0.lowercased().prefix(12)) }
        let path = safeSuffix?.isEmpty == false ? "\(stem)_\(safeSuffix!)" : stem
        return BedrockIdentifier(rawValue: "craftberry:\(path)")
    }
}
