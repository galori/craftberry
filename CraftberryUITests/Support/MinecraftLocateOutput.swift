import Foundation

/// Reads the position out of Bedrock's `/locate biome` reply, for example
/// "The nearest craftberry:x is at (-1234, ~, 567) (1300 blocks away)".
enum MinecraftLocateOutput {
    static func coordinates(in recognizedText: String) -> (x: Int, z: Int)? {
        guard let marker = recognizedText.range(of: "is at", options: .caseInsensitive) else { return nil }
        let tail = recognizedText[marker.upperBound...]
        // Only the first parenthesis group holds the position; the second is the distance.
        let group = tail.prefix { $0 != ")" }
        let numbers = group.split { !($0.isNumber || $0 == "-") }.compactMap { Int($0) }
        // Bedrock prints "~" for y; some versions print a number, so accept both shapes.
        switch numbers.count {
        case 2: return (numbers[0], numbers[1])
        case 3: return (numbers[0], numbers[2])
        default: return nil
        }
    }
}
