import Foundation

/// Produces a small, deterministic original melody as mono PCM WAV data.
/// No third-party music, samples, or game audio are bundled with generated packs.
enum MusicRecordAudioRenderer {
    static let sampleRate: UInt32 = 22_050
    static let duration: Double = 8
    private static let noteDuration = 0.5

    private static let melodies: [MusicRecordStyle: [Double]] = [
        .dreamy: [523.25, 659.25, 783.99, 659.25, 587.33, 698.46, 880.00, 698.46, 523.25, 659.25, 783.99, 1046.50, 880.00, 783.99, 659.25, 523.25],
        .bright: [523.25, 659.25, 783.99, 1046.50, 783.99, 659.25, 587.33, 698.46, 880.00, 1174.66, 880.00, 698.46, 783.99, 880.00, 1046.50, 1046.50],
        .mysterious: [392.00, 466.16, 587.33, 466.16, 415.30, 523.25, 622.25, 523.25, 349.23, 415.30, 523.25, 622.25, 466.16, 415.30, 392.00, 349.23],
        .adventurous: [392.00, 523.25, 659.25, 783.99, 659.25, 523.25, 440.00, 587.33, 698.46, 880.00, 698.46, 587.33, 493.88, 659.25, 783.99, 987.77]
    ]

    static func soundEventIdentifier(for itemID: ContentID) -> String {
        "record.craftberry_\(trackIdentifier(for: itemID))"
    }

    static func trackIdentifier(for itemID: ContentID) -> String {
        itemID.rawValue
    }

    static func render(style: MusicRecordStyle) -> Data {
        let samplesPerNote = Int(Double(sampleRate) * noteDuration)
        let sampleCount = samplesPerNote * (melodies[style]?.count ?? 0)
        var pcm = Data(capacity: sampleCount * MemoryLayout<Int16>.size)
        let notes = melodies[style] ?? []

        for (noteIndex, frequency) in notes.enumerated() {
            for sampleIndex in 0..<samplesPerNote {
                let time = Double(sampleIndex) / Double(sampleRate)
                let edge = min(1, min(time / 0.03, (noteDuration - time) / 0.04))
                let envelope = max(0, edge) * (0.88 - 0.08 * time / noteDuration)
                let phase = 2 * Double.pi * frequency * time
                let fundamental = sin(phase)
                let overtone = sin(phase * 2 + Double(noteIndex) * 0.17)
                let shimmer = sin(phase * 3 + 0.4)
                let wave = (fundamental * 0.72 + overtone * 0.20 + shimmer * 0.08) * envelope * 0.55
                append(Int16(max(-1, min(1, wave)) * Double(Int16.max)), to: &pcm)
            }
        }

        var wav = Data(capacity: 44 + pcm.count)
        wav.append(contentsOf: "RIFF".utf8)
        append(UInt32(36 + pcm.count), to: &wav)
        wav.append(contentsOf: "WAVE".utf8)
        wav.append(contentsOf: "fmt ".utf8)
        append(UInt32(16), to: &wav)
        append(UInt16(1), to: &wav) // Linear PCM.
        append(UInt16(1), to: &wav) // Mono.
        append(sampleRate, to: &wav)
        append(sampleRate * 2, to: &wav) // Byte rate.
        append(UInt16(2), to: &wav) // Block alignment.
        append(UInt16(16), to: &wav)
        wav.append(contentsOf: "data".utf8)
        append(UInt32(pcm.count), to: &wav)
        wav.append(pcm)
        return wav
    }

    private static func append(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 24) & 0xff))
    }

    private static func append(_ value: Int16, to data: inout Data) {
        append(UInt16(bitPattern: value), to: &data)
    }
}
