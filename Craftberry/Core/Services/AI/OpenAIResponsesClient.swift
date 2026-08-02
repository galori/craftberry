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
            guard intent.sword == nil else { throw LLMClientError.invalidResponse }
            return ProjectGeneration(outcome: .unsupported, message: intent.message, project: nil)
        case .ready:
            guard let sword = intent.sword else { throw LLMClientError.invalidResponse }
            let project = try AddOnProject.sword(
                displayName: sword.displayName,
                color: sword.color,
                attackBonus: sword.attackBonus,
                durability: sword.durability,
                craftingIngredient: sword.craftingIngredient.bedrockIdentifier,
                originalPrompt: prompt,
                identity: identityGenerator(),
                profile: .current
            )
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
    let sword: SwordIntent?
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
    Convert the user's request into exactly one Craftberry custom sword intent.
    Craftberry currently supports only a colored sword, an attack bonus from 1 through 30, durability from 50 through 2000, and a standard crafting-table recipe with exactly two of one supported material plus a stick.
    If a requested detail is omitted, use blue, attack bonus 10, durability 500, and diamond. Never output Bedrock JSON, identifiers, UUIDs, filenames, code, markdown, or fields outside the schema.
    If the request needs unsupported artifact types, effects, custom recipes, custom models, multiple artifacts, or unsupported ingredients, set outcome to unsupported, set sword to null, and state a short supported prompt the user can try.
    If outcome is ready, make message a short friendly summary and populate every sword field.
    """

    private static let schema: JSONValue = .object([
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "required": .array(["schemaVersion", "outcome", "message", "sword"].map(JSONValue.string)),
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
            ])
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
