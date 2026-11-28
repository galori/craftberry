import Foundation

/// Original, deterministic assets for effect creatures. Nothing here is sampled from Minecraft.
enum EntityEffectAssets {
    static let sampleRate: UInt32 = 22_050

    static func soundEvent(for entityID: ContentID) -> String { "craftberry.\(entityID.rawValue).effect" }
    static func soundPath(for entityID: ContentID) -> String { "sounds/craftberry/\(entityID.rawValue)_effect" }
    static func particleIdentifier(for entityID: ContentID, namespace: String) -> String { "\(namespace):\(entityID.rawValue)_burst" }
    static func particleTexturePath(for entityID: ContentID) -> String { "textures/particle/\(entityID.rawValue)_spark" }
    static func animationIdentifier(for entityID: ContentID) -> String { "animation.\(entityID.rawValue).spawn_effect" }

    /// Mono 16-bit PCM WAV.
    static func renderSound(_ sound: EntityEffectSound) -> Data {
        var pcm = [Int16]()
        switch sound {
        case .chime:
            for frequency in [1046.50, 1318.51, 1567.98] {
                pcm += tone(frequency: frequency, endFrequency: frequency, duration: 0.14, decay: 6)
            }
            pcm += tone(frequency: 2093.0, endFrequency: 2093.0, duration: 0.4, decay: 5)
        case .bell:
            pcm = tone(frequency: 880, endFrequency: 880, duration: 1.0, decay: 3.5, overtone: 2.76)
        case .zap:
            pcm = tone(frequency: 1800, endFrequency: 300, duration: 0.35, decay: 3)
        }
        return wav(pcm)
    }

    private static func tone(frequency: Double, endFrequency: Double, duration: Double, decay: Double, overtone: Double = 2) -> [Int16] {
        let count = Int(Double(sampleRate) * duration)
        var phase = 0.0
        return (0..<count).map { index in
            let progress = Double(index) / Double(count)
            phase += 2 * Double.pi * (frequency + (endFrequency - frequency) * progress) / Double(sampleRate)
            let attack = min(1, Double(index) / 120)
            let envelope = attack * exp(-decay * progress)
            let wave = (sin(phase) * 0.8 + sin(phase * overtone) * 0.2) * envelope * 0.6
            return Int16(max(-1, min(1, wave)) * Double(Int16.max))
        }
    }

    private static func wav(_ samples: [Int16]) -> Data {
        var data = Data()
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let byteCount = UInt32(samples.count * 2)
        data.append(contentsOf: "RIFF".utf8)
        append32(36 + byteCount)
        data.append(contentsOf: "WAVEfmt ".utf8)
        append32(16)
        append16(1) // Linear PCM.
        append16(1) // Mono.
        append32(sampleRate)
        append32(sampleRate * 2)
        append16(2)
        append16(16)
        data.append(contentsOf: "data".utf8)
        append32(byteCount)
        for sample in samples { append16(UInt16(bitPattern: sample)) }
        return data
    }

    /// 8×8 four-point star in the palette colors, drawn with the 8×8 particle uv in the emitter.
    static func renderParticleTexture(color: PixelArtColor) -> Data {
        let palette = SwordPalette.colors(for: color)
        var pixels = Array(repeating: RGBA.transparent, count: 64)
        for y in 0..<8 {
            for x in 0..<8 {
                let dx = abs(Double(x) - 3.5)
                let dy = abs(Double(y) - 3.5)
                let reach = dx + dy
                guard min(dx, dy) < 1.1 || reach < 2.2 else { continue }
                guard reach < 4.2 else { continue }
                pixels[y * 8 + x] = reach < 1.6 ? palette.highlight : palette.main
            }
        }
        return PNGEncoder.encode(width: 8, height: 8, pixels: pixels)
    }

    static func particleDocument(for entityID: ContentID, namespace: String, style: EntityEffectParticle) -> ParticleDocument {
        let shape: (direction: [String], speed: String, gravity: Double)
        switch style {
        case .burst: shape = (["Math.random(-1.0, 1.0)", "Math.random(-1.0, 1.0)", "Math.random(-1.0, 1.0)"], "Math.random(2.0, 4.0)", -2)
        case .fountain: shape = (["Math.random(-0.2, 0.2)", "1.0", "Math.random(-0.2, 0.2)"], "Math.random(4.0, 6.0)", -9.8)
        case .drift: shape = (["Math.random(-0.3, 0.3)", "0.5", "Math.random(-0.3, 0.3)"], "Math.random(0.5, 1.0)", 0.5)
        }
        return ParticleDocument(
            formatVersion: "1.10.0",
            particleEffect: ParticleDocument.ParticleEffect(
                description: ParticleDocument.Description(
                    identifier: particleIdentifier(for: entityID, namespace: namespace),
                    basicRenderParameters: ParticleDocument.RenderParameters(material: "particles_alpha", texture: particleTexturePath(for: entityID))
                ),
                components: ParticleDocument.Components(
                    emitterRateInstant: ParticleDocument.NumParticles(numParticles: 24),
                    emitterLifetimeOnce: ParticleDocument.EmptyComponent(),
                    emitterShapePoint: ParticleDocument.Direction(direction: shape.direction),
                    initialSpeed: shape.speed,
                    lifetime: ParticleDocument.Lifetime(maxLifetime: "Math.random(1.0, 2.0)"),
                    motionDynamic: ParticleDocument.Motion(linearAcceleration: [0, shape.gravity, 0]),
                    billboard: ParticleDocument.Billboard(
                        size: ["0.15", "0.15"],
                        facingCameraMode: "lookat_xyz",
                        uv: ParticleDocument.UV(textureWidth: 8, textureHeight: 8, uv: [0, 0], uvSize: [8, 8])
                    ),
                    lighting: ParticleDocument.EmptyComponent()
                )
            )
        )
    }
}
