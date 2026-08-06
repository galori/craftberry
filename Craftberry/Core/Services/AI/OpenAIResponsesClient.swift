import Foundation

public struct OpenAIResponsesClient: LLMClient {
    private let apiKey: String
    private let session: URLSession
    private let identityGenerator: @Sendable () -> AddOnProjectIdentity

    public init(
        apiKey: String,
        session: URLSession = .shared,
        identityGenerator: @escaping @Sendable () -> AddOnProjectIdentity = { .generate() }
    ) {
        self.apiKey = apiKey
        self.session = session
        self.identityGenerator = identityGenerator
    }

    public func generateProject(from prompt: String) async throws -> ProjectGeneration {
        guard !apiKey.isEmpty else { throw LLMClientError.missingAPIKey }
        var repairIssues: [String] = []

        for attempt in 0...1 {
            let text = try await requestStructuredIntent(prompt: prompt, repairIssues: repairIssues)
            do {
                return try assembleProject(from: text, prompt: prompt)
            } catch {
                guard attempt == 0 else { throw LLMClientError.invalidResponse }
                repairIssues = [error.localizedDescription]
            }
        }
        throw LLMClientError.invalidResponse
    }

    private func requestStructuredIntent(prompt: String, repairIssues: [String]) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            OpenAIRequestDocument.make(prompt: prompt, repairIssues: repairIssues)
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw LLMClientError.invalidResponse }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let detail = (try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data))?.error.message
            throw LLMClientError.requestFailed(detail ?? "Generation failed (HTTP \(httpResponse.statusCode)).")
        }

        let responseBody = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let text = responseBody.output
            .flatMap(\.content)
            .first(where: { $0.type == "output_text" })?.text else {
            throw LLMClientError.invalidResponse
        }
        return text
    }

    private func assembleProject(from text: String, prompt: String) throws -> ProjectGeneration {
        let intent = try JSONDecoder().decode(ProjectIntentGeneration.self, from: Data(text.utf8))
        guard intent.schemaVersion == 1, !intent.message.isEmpty else { throw LLMClientError.invalidResponse }

        switch intent.outcome {
        case .unsupported:
            guard intent.sword == nil, intent.materialSwordSet == nil, intent.materialToolSet == nil, intent.materialWeaponSet == nil, intent.materialArmorSet == nil else { throw LLMClientError.invalidResponse }
            return ProjectGeneration(outcome: .unsupported, message: intent.message, project: nil)
        case .ready:
            let shortDescription = intent.shortDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !shortDescription.isEmpty else { throw LLMClientError.invalidResponse }
            let identity = identityGenerator()
            let project: AddOnProject
            switch (intent.sword, intent.materialSwordSet, intent.materialToolSet, intent.materialWeaponSet, intent.materialArmorSet) {
            case let (.some(sword), nil, nil, nil, nil):
                project = try AddOnProject.sword(displayName: sword.displayName, color: sword.color, attackBonus: sword.attackBonus, durability: sword.durability, craftingIngredient: sword.craftingIngredient.bedrockIdentifier, shortDescription: shortDescription, originalPrompt: prompt, identity: identity, profile: .current)
            case let (nil, .some(material), nil, nil, nil):
                project = try AddOnProject.materialSwordSet(materialName: material.materialName, color: material.color, sourceItem: material.sourceItem.bedrockIdentifier, sourceCount: material.sourceCount, swordDisplayName: material.swordDisplayName, attackBonus: material.attackBonus, durability: material.durability, shortDescription: shortDescription, originalPrompt: prompt, identity: identity, profile: .current)
            case let (nil, nil, .some(material), nil, nil):
                project = try AddOnProject.materialToolSet(materialName: material.materialName, color: material.color, sourceItem: material.sourceItem.bedrockIdentifier, sourceCount: material.sourceCount, attackBonus: material.attackBonus, durability: material.durability, shortDescription: shortDescription, originalPrompt: prompt, identity: identity, profile: .current)
            case let (nil, nil, nil, .some(material), nil):
                project = try AddOnProject.materialWeaponSet(materialName: material.materialName, color: material.color, sourceItem: material.sourceItem.bedrockIdentifier, sourceCount: material.sourceCount, attackBonus: material.attackBonus, durability: material.durability, shortDescription: shortDescription, originalPrompt: prompt, identity: identity, profile: .current)
            case let (nil, nil, nil, nil, .some(material)):
                project = try AddOnProject.materialArmorSet(materialName: material.materialName, color: material.color, sourceItem: material.sourceItem.bedrockIdentifier, sourceCount: material.sourceCount, protection: material.protection, durability: material.durability, shortDescription: shortDescription, originalPrompt: prompt, identity: identity, profile: .current)
            default: throw LLMClientError.invalidResponse
            }
            let report = AddOnProjectValidator.validate(project, profile: .current)
            guard report.isSuccessful else {
                throw ProjectIntentValidationError(issues: report.errors)
            }
            return ProjectGeneration(outcome: .ready, message: intent.message, project: project)
        }
    }
}

private struct ProjectIntentValidationError: LocalizedError {
    let issues: [CompilationIssue]

    var errorDescription: String? {
        issues.map { "\($0.path): \($0.message)" }.joined(separator: "; ")
    }
}

private struct ProjectIntentGeneration: Decodable {
    let schemaVersion: Int
    let outcome: ProjectGenerationOutcome
    let message: String
    let shortDescription: String?
    let sword: SwordIntent?
    let materialSwordSet: MaterialSwordSetIntent?
    let materialToolSet: MaterialToolSetIntent?
    let materialWeaponSet: MaterialWeaponSetIntent?
    let materialArmorSet: MaterialArmorSetIntent?
}

private struct MaterialSwordSetIntent: Decodable {
    let materialName: String
    let color: PixelArtColor
    let sourceItem: FoundationSwordIngredient
    let sourceCount: Int
    let swordDisplayName: String?
    let attackBonus: Int
    let durability: Int
}

private struct MaterialToolSetIntent: Decodable {
    let materialName: String
    let color: PixelArtColor
    let sourceItem: FoundationSwordIngredient
    let sourceCount: Int
    let attackBonus: Int
    let durability: Int
}

private struct MaterialWeaponSetIntent: Decodable {
    let materialName: String
    let color: PixelArtColor
    let sourceItem: FoundationSwordIngredient
    let sourceCount: Int
    let attackBonus: Int
    let durability: Int
}

private struct MaterialArmorSetIntent: Decodable {
    let materialName: String
    let color: PixelArtColor
    let sourceItem: FoundationSwordIngredient
    let sourceCount: Int
    let protection: Int
    let durability: Int
}

private struct SwordIntent: Decodable {
    let displayName: String
    let color: PixelArtColor
    let attackBonus: Int
    let durability: Int
    let craftingIngredient: FoundationSwordIngredient
}

private enum FoundationSwordIngredient: String, CaseIterable, Decodable {
    case diamond, emerald, ironIngot = "iron_ingot", goldIngot = "gold_ingot"
    case netheriteIngot = "netherite_ingot", amethystShard = "amethyst_shard"
    case blazeRod = "blaze_rod", redstone, lapisLazuli = "lapis_lazuli", quartz

    var bedrockIdentifier: String { "minecraft:\(rawValue)" }
}

private struct OpenAIRequestDocument: Encodable {
    let model: String
    let reasoning: Reasoning
    let text: TextConfiguration
    let input: [InputMessage]

    struct Reasoning: Encodable { let effort: String }
    struct TextConfiguration: Encodable { let format: StructuredFormat }

    struct StructuredFormat: Encodable {
        let type: String
        let name: String
        let strict: Bool
        let schema: JSONValue
    }

    struct InputMessage: Encodable {
        let role: String
        let content: [InputContent]
    }

    struct InputContent: Encodable {
        let type: String
        let text: String
    }

    static func make(prompt: String, repairIssues: [String]) -> OpenAIRequestDocument {
        var input = [
            InputMessage(
                role: "developer",
                content: [InputContent(type: "input_text", text: instructions)]
            ),
            InputMessage(
                role: "user",
                content: [InputContent(type: "input_text", text: prompt)]
            )
        ]
        if !repairIssues.isEmpty {
            input.append(
                InputMessage(
                    role: "developer",
                    content: [InputContent(
                        type: "input_text",
                        text: "Repair the previous structured intent. Local validation issues: \(repairIssues.joined(separator: "; "))"
                    )]
                )
            )
        }
        return OpenAIRequestDocument(
            model: "gpt-5.6-terra",
            reasoning: Reasoning(effort: "low"),
            text: TextConfiguration(
                format: StructuredFormat(
                    type: "json_schema",
                    name: "craftberry_project_intent",
                    strict: true,
                    schema: schema
                )
            ),
            input: input
        )
    }

    private static let instructions = """
    Convert the request into exactly one supported Craftberry intent: a single custom sword, one named material ingot plus its matching sword, one named material ingot plus a matching sword/pickaxe/axe/shovel/hoe tool set, one named material ingot plus a matching sword/dagger/spear/hammer melee weapon set, or one named material ingot plus a matching helmet/chestplate/leggings/boots armor set.
    A material set makes a shapeless ingot from 1 through 9 copies of one supported vanilla material, then a sword from two ingots and a stick. Defaults are Azure, blue, diamond x4, attack 10, durability 500, names "Azure Ingot" and "Azure Sword". Never output Bedrock JSON, identifiers, UUIDs, filenames, code, markdown, or fields outside the schema.
    A material tool set uses the same ingot recipe and additionally crafts pickaxe, axe, shovel, and hoe variants from that ingot and sticks.
    A material weapon set uses the same ingot recipe and additionally crafts dagger, spear, and hammer variants from that ingot and sticks.
    A material armor set uses the same ingot recipe and additionally crafts a helmet, chestplate, leggings, and boots from that ingot alone (no sticks); protection is the set's total protection (4 through 20, default 15) and is split across the four pieces automatically, so never ask for a per-piece value.
    If unsupported, set all intents and shortDescription to null. If ready, populate exactly one intent and write shortDescription as one short user-facing pack overview sentence.
    """

    private static let schema: JSONValue = .object([
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "required": .array(["schemaVersion", "outcome", "message", "shortDescription", "sword", "materialSwordSet", "materialToolSet", "materialWeaponSet", "materialArmorSet"].map(JSONValue.string)),
        "properties": .object([
            "schemaVersion": .object(["type": .string("integer"), "const": .integer(1)]),
            "outcome": .object([
                "type": .string("string"),
                "enum": .array(["ready", "unsupported"].map(JSONValue.string))
            ]),
            "message": .object([
                "type": .string("string"),
                "minLength": .integer(1),
                "maxLength": .integer(180)
            ]),
            "shortDescription": .object([
                "anyOf": .array([
                    .object(["type": .string("null")]),
                    .object([
                        "type": .string("string"),
                        "minLength": .integer(1),
                        "maxLength": .integer(180)
                    ])
                ])
            ]),
            "sword": .object([
                "anyOf": .array([
                    .object(["type": .string("null")]),
                    .object([
                        "type": .string("object"),
                        "additionalProperties": .bool(false),
                        "required": .array([
                            "displayName", "color", "attackBonus", "durability", "craftingIngredient"
                        ].map(JSONValue.string)),
                        "properties": .object([
                            "displayName": .object([
                                "type": .string("string"),
                                "minLength": .integer(1),
                                "maxLength": .integer(32)
                            ]),
                            "color": .object([
                                "type": .string("string"),
                                "enum": .array(PixelArtColor.allCases.map { .string($0.rawValue) })
                            ]),
                            "attackBonus": .object([
                                "type": .string("integer"),
                                "minimum": .integer(1),
                                "maximum": .integer(30)
                            ]),
                            "durability": .object([
                                "type": .string("integer"),
                                "minimum": .integer(50),
                                "maximum": .integer(2_000)
                            ]),
                            "craftingIngredient": .object([
                                "type": .string("string"),
                                "enum": .array(FoundationSwordIngredient.allCases.map { .string($0.rawValue) })
                            ])
                        ])
                    ])
                ])
            ]),
            "materialSwordSet": .object(["anyOf": .array([
                .object(["type": .string("null")]),
                .object(["type": .string("object"), "additionalProperties": .bool(false), "required": .array(["materialName", "color", "sourceItem", "sourceCount", "swordDisplayName", "attackBonus", "durability"].map(JSONValue.string)), "properties": .object([
                    "materialName": .object(["type": .string("string"), "minLength": .integer(1), "maxLength": .integer(24)]),
                    "color": .object(["type": .string("string"), "enum": .array(PixelArtColor.allCases.map { .string($0.rawValue) })]),
                    "sourceItem": .object(["type": .string("string"), "enum": .array(FoundationSwordIngredient.allCases.map { .string($0.rawValue) })]),
                    "sourceCount": .object(["type": .string("integer"), "minimum": .integer(1), "maximum": .integer(9)]),
                    "swordDisplayName": .object(["anyOf": .array([.object(["type": .string("null")]), .object(["type": .string("string"), "minLength": .integer(1), "maxLength": .integer(32)])])]),
                    "attackBonus": .object(["type": .string("integer"), "minimum": .integer(1), "maximum": .integer(30)]),
                    "durability": .object(["type": .string("integer"), "minimum": .integer(50), "maximum": .integer(2_000)])
                ])])
            ])]),
            "materialToolSet": .object(["anyOf": .array([
                .object(["type": .string("null")]),
                .object(["type": .string("object"), "additionalProperties": .bool(false), "required": .array(["materialName", "color", "sourceItem", "sourceCount", "attackBonus", "durability"].map(JSONValue.string)), "properties": .object([
                    "materialName": .object(["type": .string("string"), "minLength": .integer(1), "maxLength": .integer(24)]),
                    "color": .object(["type": .string("string"), "enum": .array(PixelArtColor.allCases.map { .string($0.rawValue) })]),
                    "sourceItem": .object(["type": .string("string"), "enum": .array(FoundationSwordIngredient.allCases.map { .string($0.rawValue) })]),
                    "sourceCount": .object(["type": .string("integer"), "minimum": .integer(1), "maximum": .integer(9)]),
                    "attackBonus": .object(["type": .string("integer"), "minimum": .integer(1), "maximum": .integer(30)]),
                    "durability": .object(["type": .string("integer"), "minimum": .integer(50), "maximum": .integer(2_000)])
                ])])
            ])]),
            "materialWeaponSet": .object(["anyOf": .array([
                .object(["type": .string("null")]),
                .object(["type": .string("object"), "additionalProperties": .bool(false), "required": .array(["materialName", "color", "sourceItem", "sourceCount", "attackBonus", "durability"].map(JSONValue.string)), "properties": .object([
                    "materialName": .object(["type": .string("string"), "minLength": .integer(1), "maxLength": .integer(24)]),
                    "color": .object(["type": .string("string"), "enum": .array(PixelArtColor.allCases.map { .string($0.rawValue) })]),
                    "sourceItem": .object(["type": .string("string"), "enum": .array(FoundationSwordIngredient.allCases.map { .string($0.rawValue) })]),
                    "sourceCount": .object(["type": .string("integer"), "minimum": .integer(1), "maximum": .integer(9)]),
                    "attackBonus": .object(["type": .string("integer"), "minimum": .integer(1), "maximum": .integer(30)]),
                    "durability": .object(["type": .string("integer"), "minimum": .integer(50), "maximum": .integer(2_000)])
                ])])
            ])]),
            "materialArmorSet": .object(["anyOf": .array([
                .object(["type": .string("null")]),
                .object(["type": .string("object"), "additionalProperties": .bool(false), "required": .array(["materialName", "color", "sourceItem", "sourceCount", "protection", "durability"].map(JSONValue.string)), "properties": .object([
                    "materialName": .object(["type": .string("string"), "minLength": .integer(1), "maxLength": .integer(24)]),
                    "color": .object(["type": .string("string"), "enum": .array(PixelArtColor.allCases.map { .string($0.rawValue) })]),
                    "sourceItem": .object(["type": .string("string"), "enum": .array(FoundationSwordIngredient.allCases.map { .string($0.rawValue) })]),
                    "sourceCount": .object(["type": .string("integer"), "minimum": .integer(1), "maximum": .integer(9)]),
                    "protection": .object(["type": .string("integer"), "minimum": .integer(4), "maximum": .integer(20)]),
                    "durability": .object(["type": .string("integer"), "minimum": .integer(50), "maximum": .integer(2_000)])
                ])])
            ])])
        ])
    ])
}

private indirect enum JSONValue: Encodable, Sendable {
    case string(String)
    case integer(Int)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

private struct OpenAIResponse: Decodable {
    let output: [OpenAIOutput]
}

private struct OpenAIOutput: Decodable {
    let content: [OpenAIContent]
}

private struct OpenAIContent: Decodable {
    let type: String
    let text: String?
}

private struct OpenAIErrorEnvelope: Decodable {
    let error: OpenAIError
}

private struct OpenAIError: Decodable {
    let message: String
}
