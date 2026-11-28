import XCTest
#if canImport(CraftberryCore)
@testable import CraftberryCore
#else
@testable import Craftberry
#endif

final class EntityEffectTests: XCTestCase {
    func testEffectSetKeepsEggAndIngotButHasNoNaturalSpawn() throws {
        let project = try AddOnProject.materialEffectEntitySet(
            materialName: "Pulse",
            particle: .fountain,
            sound: .bell,
            originalPrompt: "effects",
            identity: identity()
        )
        let entity = try XCTUnwrap(project.entities.first)
        XCTAssertEqual(entity.effect, EntityEffectTrait(particle: .fountain, sound: .bell))
        XCTAssertTrue(project.spawnRules.isEmpty, "The effect must only fire from the spawn egg.")
        XCTAssertEqual(project.items.count, 2)
        let decoded = try JSONDecoder().decode(EntityDefinition.self, from: JSONEncoder().encode(entity))
        XCTAssertEqual(decoded, entity)
    }

    func testPlainEntityStillDecodesWithoutAnEffect() throws {
        let project = try AddOnProject.materialEntitySet(originalPrompt: "plain", identity: identity())
        let entity = try XCTUnwrap(project.entities.first)
        XCTAssertNil(entity.effect)
        let encoded = try JSONEncoder().encode(entity)
        XCTAssertNil((try JSONSerialization.jsonObject(with: encoded) as? [String: Any])?["effect"])
    }

    func testCompilerEmitsParticleAnimationSoundAndClientWiringPinnedToSamples() throws {
        let project = try AddOnProject.materialEffectEntitySet(
            materialName: "Azure",
            color: .blue,
            particle: .burst,
            sound: .chime,
            originalPrompt: "an effect creature",
            identity: identity()
        )
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = try BedrockAddOnCompiler().compile(project: project, profile: .current, outputDirectory: directory)
        let outer = try ZipArchiveReader.readEntries(at: result.artifact.url)
        let resource = try ZipArchiveReader.readEntries(
            data: try XCTUnwrap(outer.first { $0.path == "azure_a1b2c3_ingot_resources.mcpack" }?.data)
        )
        func document(_ path: String) throws -> [String: Any] {
            let entry = try XCTUnwrap(resource.first { $0.path == path }, path)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: entry.data) as? [String: Any])
        }

        // Particle shape follows resource_pack/particles/lava_particle.json (format 1.10.0) at 921fafb0.
        let particleFile = try document("particles/azure_a1b2c3_creature.particle.json")
        XCTAssertEqual(particleFile["format_version"] as? String, "1.10.0")
        let particle = try XCTUnwrap(particleFile["particle_effect"] as? [String: Any])
        let description = try XCTUnwrap(particle["description"] as? [String: Any])
        XCTAssertEqual(description["identifier"] as? String, "craftberry:azure_a1b2c3_creature_burst")
        let render = try XCTUnwrap(description["basic_render_parameters"] as? [String: Any])
        XCTAssertEqual(render["material"] as? String, "particles_alpha")
        XCTAssertEqual(render["texture"] as? String, "textures/particle/azure_a1b2c3_creature_spark")
        let components = try XCTUnwrap(particle["components"] as? [String: Any])
        XCTAssertEqual((components["minecraft:emitter_rate_instant"] as? [String: Any])?["num_particles"] as? Int, 24)
        XCTAssertNotNil(components["minecraft:emitter_lifetime_once"])
        XCTAssertEqual((components["minecraft:emitter_shape_point"] as? [String: Any])?["direction"] as? [String], ["Math.random(-1.0, 1.0)", "Math.random(-1.0, 1.0)", "Math.random(-1.0, 1.0)"])
        let billboard = try XCTUnwrap(components["minecraft:particle_appearance_billboard"] as? [String: Any])
        XCTAssertEqual(billboard["facing_camera_mode"] as? String, "lookat_xyz")
        let uv = try XCTUnwrap(billboard["uv"] as? [String: Any])
        XCTAssertEqual(uv["texture_width"] as? Int, 8)
        XCTAssertEqual(uv["uv_size"] as? [Int], [8, 8])

        let texture = try XCTUnwrap(resource.first { $0.path == "textures/particle/azure_a1b2c3_creature_spark.png" })
        XCTAssertEqual(texture.data.prefix(8), Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))

        // Animation timeline keys follow resource_pack/animations/warden.animation.json.
        let animationFile = try document("animations/azure_a1b2c3_creature.animation.json")
        let animation = try XCTUnwrap((animationFile["animations"] as? [String: Any])?["animation.azure_a1b2c3_creature.spawn_effect"] as? [String: Any])
        XCTAssertEqual(animation["loop"] as? Bool, false)
        XCTAssertEqual(animation["animation_length"] as? Double, 1)
        XCTAssertEqual(((animation["particle_effects"] as? [String: Any])?["0.0"] as? [String: String])?["effect"], "spawn_burst")
        XCTAssertEqual(((animation["sound_effects"] as? [String: Any])?["0.0"] as? [String: String])?["effect"], "spawn_sound")

        // Client entity wiring follows blaze.entity.json (particle_effects) and warden.entity.json (sound_effects).
        let client = try document("entity/azure_a1b2c3_creature.entity.json")
        let clientDescription = try XCTUnwrap((client["minecraft:client_entity"] as? [String: Any])?["description"] as? [String: Any])
        XCTAssertEqual(clientDescription["particle_effects"] as? [String: String], ["spawn_burst": "craftberry:azure_a1b2c3_creature_burst"])
        XCTAssertEqual(clientDescription["sound_effects"] as? [String: String], ["spawn_sound": "craftberry.azure_a1b2c3_creature.effect"])
        XCTAssertEqual(clientDescription["animations"] as? [String: String], ["spawn_effect": "animation.azure_a1b2c3_creature.spawn_effect"])
        XCTAssertEqual((clientDescription["scripts"] as? [String: Any])?["animate"] as? [String], ["spawn_effect"])

        // Custom sound event: a plain resource-pack sound_definitions entry, no Beta APIs involved.
        let sounds = try XCTUnwrap(try document("sounds/sound_definitions.json")["sound_definitions"] as? [String: Any])
        let event = try XCTUnwrap(sounds["craftberry.azure_a1b2c3_creature.effect"] as? [String: Any])
        XCTAssertEqual(event["category"] as? String, "neutral")
        XCTAssertEqual((event["sounds"] as? [[String: Any]])?.first?["name"] as? String, "sounds/craftberry/azure_a1b2c3_creature_effect")
        let wav = try XCTUnwrap(resource.first { $0.path == "sounds/craftberry/azure_a1b2c3_creature_effect.wav" })
        XCTAssertEqual(wav.data.prefix(4), Data("RIFF".utf8))
        XCTAssertGreaterThan(wav.data.count, 10_000)
    }

    func testPlainEntityEmitsNoEffectFiles() throws {
        let project = try AddOnProject.materialEntitySet(materialName: "Azure", originalPrompt: "plain", identity: identity())
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = try BedrockAddOnCompiler().compile(project: project, profile: .current, outputDirectory: directory)
        let outer = try ZipArchiveReader.readEntries(at: result.artifact.url)
        let resource = try ZipArchiveReader.readEntries(
            data: try XCTUnwrap(outer.first { $0.path == "azure_a1b2c3_ingot_resources.mcpack" }?.data)
        )
        XCTAssertFalse(resource.contains { $0.path.hasPrefix("particles/") || $0.path.hasPrefix("sounds/") || $0.path.hasPrefix("animations/") })
    }

    func testClientAssemblesEffectSetFromStructuredIntentThroughFakeTransport() async throws {
        let structuredText = """
        {"schemaVersion":1,"outcome":"ready","message":"Ready to build.","shortDescription":"A sparkling creature.","materialEffectEntitySet":{"materialName":"Azure","color":"blue","sourceItem":"diamond","sourceCount":4,"particle":"drift","sound":"zap"}}
        """
        let body = try JSONSerialization.data(withJSONObject: ["output": [["content": [["type": "output_text", "text": structuredText]]]]])
        EffectTransportStub.handler = { request in
            (try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)), body)
        }
        defer { EffectTransportStub.handler = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EffectTransportStub.self]
        let stable = identity()
        let client = OpenAIResponsesClient(apiKey: "test-key", session: URLSession(configuration: configuration), identityGenerator: { stable })

        let generation = try await client.generateProject(from: "A diamond creature with drifting sparks and a zap")

        let entity = try XCTUnwrap(generation.project?.entities.first)
        XCTAssertEqual(entity.effect, EntityEffectTrait(particle: .drift, sound: .zap))
    }

    func testAssemblyRejectsEffectIntentCombinedWithAnotherIntent() {
        let text = """
        {"schemaVersion":1,"outcome":"ready","message":"Ready.","shortDescription":"Both.","materialEffectEntitySet":{"materialName":"Azure","color":"blue","sourceItem":"diamond","sourceCount":4,"particle":"burst","sound":"chime"},"materialBossEntitySet":{"materialName":"Azure","color":"blue","sourceItem":"diamond","sourceCount":4,"health":40}}
        """
        let stable = identity()
        XCTAssertThrowsError(try OpenAIResponsesClient.assembleProject(from: text, prompt: "both", identityGenerator: { stable }))
    }

    func testCachedExamplePromptsAssembleEffectCreatures() throws {
        let cached = try XCTUnwrap(ExamplePromptResponseCache.generation(for: "A diamond creature named Azure with drifting sparks and a zap sound", identity: identity(), originalPrompt: "cached"))
        XCTAssertEqual(cached.project?.entities.first?.effect, EntityEffectTrait(particle: .drift, sound: .zap))
    }

    func testEffectSoundsAreDistinctAndDeterministic() {
        let renders = EntityEffectSound.allCases.map { EntityEffectAssets.renderSound($0) }
        XCTAssertEqual(Set(renders).count, renders.count)
        XCTAssertEqual(renders[0], EntityEffectAssets.renderSound(.chime))
    }

    private func identity() -> AddOnProjectIdentity {
        AddOnProjectIdentity(projectID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!, namespace: "craftberry", contentSuffix: "a1b2c3", packUUIDs: PackUUIDs(behaviorHeader: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!, behaviorModule: UUID(uuidString: "20000000-0000-4000-8000-000000000002")!, resourceHeader: UUID(uuidString: "20000000-0000-4000-8000-000000000003")!, resourceModule: UUID(uuidString: "20000000-0000-4000-8000-000000000004")!))
    }
}

private final class EffectTransportStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try XCTUnwrap(Self.handler)(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
