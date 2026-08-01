import Foundation

public struct OpenAIResponsesClient: LLMClient {
    private let apiKey: String
    private let session: URLSession

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    public func generateSword(from prompt: String) async throws -> SwordGeneration {
        guard !apiKey.isEmpty else { throw LLMClientError.missingAPIKey }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(prompt: prompt))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw LLMClientError.invalidResponse }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let detail = (try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data))?.error.message
            throw LLMClientError.requestFailed(detail ?? "Generation failed (HTTP \(httpResponse.statusCode)).")
        }

        let responseBody = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let text = responseBody.output
            .flatMap(\.content)
            .first(where: { $0.type == "output_text" })?.text,
              let generation = try? JSONDecoder().decode(SwordGeneration.self, from: Data(text.utf8)),
              generation.schemaVersion == 1,
              (generation.outcome == .unsupported || generation.sword != nil) else {
            throw LLMClientError.invalidResponse
        }
        return generation
    }

    private func requestBody(prompt: String) -> [String: Any] {
        [
            "model": "gpt-5.6-terra",
            "reasoning": ["effort": "low"],
            "text": ["format": [
                "type": "json_schema",
                "name": "sword_generation",
                "strict": true,
                "schema": Self.schema
            ]],
            "input": [
                [
                    "role": "developer",
                    "content": [["type": "input_text", "text": Self.instructions]]
                ],
                [
                    "role": "user",
                    "content": [["type": "input_text", "text": prompt]]
                ]
            ]
        ]
    }

    private static let instructions = """
    Convert the user's request into exactly one Craftberry custom sword specification.
    Craftberry supports only a colored sword, an attack bonus from 1 through 30, durability from 50 through 2000, and a standard crafting-table recipe with exactly two of one supported material plus a stick.
    If a requested detail is omitted, use blue, attack bonus 10, durability 500, and diamond. Never output Bedrock JSON, identifiers, filenames, code, markdown, or fields outside the schema.
    If the request needs unsupported artifact types, effects, custom recipes, custom models, multiple artifacts, or unsupported ingredients, set outcome to unsupported, omit sword, and state a short supported prompt the user can try.
    If outcome is ready, make message a short friendly summary and populate every sword field.
    """

    private static let schema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["schemaVersion", "outcome", "message", "sword"],
        "properties": [
            "schemaVersion": ["type": "integer", "const": 1],
            "outcome": ["type": "string", "enum": ["ready", "unsupported"]],
            "message": ["type": "string", "minLength": 1, "maxLength": 180],
            "sword": [
                "anyOf": [
                    ["type": "null"],
                    [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["displayName", "color", "attackBonus", "durability", "craftingIngredient"],
                        "properties": [
                            "displayName": ["type": "string", "minLength": 1, "maxLength": 32],
                            "color": ["type": "string", "enum": SwordColor.allCases.map(\.rawValue)],
                            "attackBonus": ["type": "integer", "minimum": 1, "maximum": 30],
                            "durability": ["type": "integer", "minimum": 50, "maximum": 2_000],
                            "craftingIngredient": ["type": "string", "enum": CraftingIngredient.allCases.map(\.rawValue)]
                        ]
                    ]
                ]
            ]
        ]
    ]
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
