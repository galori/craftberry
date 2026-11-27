import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(DeviceCheck)
import DeviceCheck
#endif
#if canImport(Security)
import Security
#endif

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
                return try Self.assembleProject(from: text, prompt: prompt, identityGenerator: identityGenerator)
            } catch {
                guard attempt == 0 else { throw LLMClientError.invalidResponse }
                repairIssues = [error.localizedDescription]
            }
        }
        throw LLMClientError.invalidResponse
    }

    /// Returns the model-produced intent document without assigning project IDs.
    /// The backend uses this entry point; callers still validate and assemble the
    /// returned intent with the local Swift compiler pipeline.
    public func generateIntentJSON(from prompt: String) async throws -> String {
        guard !apiKey.isEmpty else { throw LLMClientError.missingAPIKey }
        return try await requestStructuredIntent(prompt: prompt, repairIssues: [])
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

    static func assembleProject(
        from text: String,
        prompt: String,
        identityGenerator: @Sendable () -> AddOnProjectIdentity
    ) throws -> ProjectGeneration {
        let intent = try JSONDecoder().decode(ProjectIntentGeneration.self, from: Data(text.utf8))
        guard intent.schemaVersion == 1, !intent.message.isEmpty else { throw LLMClientError.invalidResponse }

        switch intent.outcome {
        case .unsupported:
            guard intent.sword == nil, intent.materialSwordSet == nil, intent.materialToolSet == nil, intent.materialWeaponSet == nil, intent.materialArmorSet == nil, intent.materialConsumableSet == nil, intent.materialBlockSet == nil, intent.materialFurnaceSet == nil, intent.materialSmithingSet == nil, intent.materialBrewingSet == nil, intent.materialOreSet == nil, intent.materialCropSet == nil, intent.materialStructureSet == nil, intent.materialHostileEntitySet == nil else { throw LLMClientError.invalidResponse }
            return ProjectGeneration(outcome: .unsupported, message: intent.message, project: nil)
        case .ready:
            let shortDescription = intent.shortDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !shortDescription.isEmpty else { throw LLMClientError.invalidResponse }
            let identity = identityGenerator()
            let project: AddOnProject
            switch (intent.sword, intent.materialSwordSet, intent.materialToolSet, intent.materialWeaponSet, intent.materialArmorSet, intent.materialConsumableSet, intent.materialBlockSet, intent.materialFurnaceSet, intent.materialSmithingSet, intent.materialBrewingSet, intent.materialOreSet, intent.materialCropSet, intent.materialStructureSet, intent.materialHostileEntitySet) {
            case let (.some(sword), nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil):
                project = try AddOnProject.sword(displayName: sword.displayName, color: sword.color, attackBonus: sword.attackBonus, durability: sword.durability, craftingIngredient: sword.craftingIngredient.bedrockIdentifier, shortDescription: shortDescription, originalPrompt: prompt, identity: identity, profile: .current)
            case let (nil, .some(material), nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil):
                project = try AddOnProject.materialSwordSet(materialName: material.materialName, color: material.color, sourceItem: material.sourceItem.bedrockIdentifier, sourceCount: material.sourceCount, swordDisplayName: material.swordDisplayName, attackBonus: material.attackBonus, durability: material.durability, shortDescription: shortDescription, originalPrompt: prompt, identity: identity, profile: .current)
            case let (nil, nil, .some(material), nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil):
                project = try AddOnProject.materialToolSet(materialName: material.materialName, color: material.color, sourceItem: material.sourceItem.bedrockIdentifier, sourceCount: material.sourceCount, attackBonus: material.attackBonus, durability: material.durability, shortDescription: shortDescription, originalPrompt: prompt, identity: identity, profile: .current)
            case let (nil, nil, nil, .some(material), nil, nil, nil, nil, nil, nil, nil, nil, nil, nil):
                project = try AddOnProject.materialWeaponSet(materialName: material.materialName, color: material.color, sourceItem: material.sourceItem.bedrockIdentifier, sourceCount: material.sourceCount, attackBonus: material.attackBonus, durability: material.durability, shortDescription: shortDescription, originalPrompt: prompt, identity: identity, profile: .current)
            case let (nil, nil, nil, nil, .some(material), nil, nil, nil, nil, nil, nil, nil, nil, nil):
                project = try AddOnProject.materialArmorSet(materialName: material.materialName, color: material.color, sourceItem: material.sourceItem.bedrockIdentifier, sourceCount: material.sourceCount, protection: material.protection, durability: material.durability, shortDescription: shortDescription, originalPrompt: prompt, identity: identity, profile: .current)
            case let (nil, nil, nil, nil, nil, .some(material), nil, nil, nil, nil, nil, nil, nil, nil):
                project = try AddOnProject.materialConsumableSet(materialName: material.materialName, color: material.color, sourceItem: material.sourceItem.bedrockIdentifier, sourceCount: material.sourceCount, nutrition: material.nutrition, saturationModifier: material.saturationModifier, canAlwaysEat: material.canAlwaysEat, fuelDuration: material.fuelDuration, shortDescription: shortDescription, originalPrompt: prompt, identity: identity, profile: .current)
            case let (nil, nil, nil, nil, nil, nil, .some(material), nil, nil, nil, nil, nil, nil, nil):
                project = try AddOnProject.materialBlockSet(materialName: material.materialName, color: material.color, sourceItem: material.sourceItem.bedrockIdentifier, sourceCount: material.sourceCount, destroyTime: material.destroyTime, mapColor: material.mapColor, shortDescription: shortDescription, originalPrompt: prompt, identity: identity, profile: .current)
            case let (nil, nil, nil, nil, nil, nil, nil, .some(material), nil, nil, nil, nil, nil, nil):
                project = try AddOnProject.materialFurnaceSet(materialName: material.materialName, color: material.color, sourceItem: material.sourceItem.bedrockIdentifier, attackBonus: material.attackBonus, durability: material.durability, shortDescription: shortDescription, originalPrompt: prompt, identity: identity, profile: .current)
            case let (nil, nil, nil, nil, nil, nil, nil, nil, .some(material), nil, nil, nil, nil, nil):
                project = try AddOnProject.materialSmithingSet(materialName: material.materialName, color: material.color, sourceItem: material.sourceItem.bedrockIdentifier, sourceCount: material.sourceCount, attackBonus: material.attackBonus, durability: material.durability, shortDescription: shortDescription, originalPrompt: prompt, identity: identity, profile: .current)
            case let (nil, nil, nil, nil, nil, nil, nil, nil, nil, .some(material), nil, nil, nil, nil):
                project = try AddOnProject.materialBrewingSet(materialName: material.materialName, color: material.color, sourceItem: material.sourceItem.bedrockIdentifier, sourceCount: material.sourceCount, shortDescription: shortDescription, originalPrompt: prompt, identity: identity, profile: .current)
            case let (nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, .some(material), nil, nil, nil):
                project = try AddOnProject.materialOreSet(materialName: material.materialName, color: material.color, sourceItem: material.sourceItem.bedrockIdentifier, sourceCount: material.sourceCount, destroyTime: material.destroyTime, mapColor: material.mapColor, shortDescription: shortDescription, originalPrompt: prompt, identity: identity, profile: .current)
            case let (nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, .some(material), nil, nil):
                project = try AddOnProject.materialCropSet(materialName: material.materialName, color: material.color, sourceItem: material.sourceItem.bedrockIdentifier, sourceCount: material.sourceCount, shortDescription: shortDescription, originalPrompt: prompt, identity: identity, profile: .current)
            case let (nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, .some(material), nil):
                project = try AddOnProject.materialStructureSet(materialName: material.materialName, color: material.color, sourceItem: material.sourceItem.bedrockIdentifier, sourceCount: material.sourceCount, destroyTime: material.destroyTime, mapColor: material.mapColor, shortDescription: shortDescription, originalPrompt: prompt, identity: identity, profile: .current)
            case let (nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, .some(material)):
                project = try AddOnProject.materialHostileEntitySet(materialName: material.materialName, color: material.color, sourceItem: material.sourceItem.bedrockIdentifier, sourceCount: material.sourceCount, health: material.health, shortDescription: shortDescription, originalPrompt: prompt, identity: identity, profile: .current)
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

/// Supplies a short-lived generation session credential at request time.
/// Production authentication can replace the Keychain-backed implementation with
/// an App Attest/session exchange without changing the generation client.
/// The body digest binds the signature to the exact versioned request while keeping
/// the App Attest client data small enough to send in request headers.
public struct GenerationAssertionClientData: Codable, Equatable, Sendable {
    public let challengeID: String
    public let challenge: String
    public let requestBodySHA256: String
    public let idempotencyKey: String
    public let method: String
    public let path: String

    public init(
        challengeID: String,
        challenge: String,
        requestBodySHA256: String,
        idempotencyKey: String,
        method: String = "POST",
        path: String = "/v1/generate"
    ) {
        self.challengeID = challengeID
        self.challenge = challenge
        self.requestBodySHA256 = requestBodySHA256
        self.idempotencyKey = idempotencyKey
        self.method = method
        self.path = path
    }

    public func canonicalData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

public struct GenerationAssertionHeaders: Sendable {
    public let challengeID: String
    public let clientData: String
    public let assertion: String

    public init(challengeID: String, clientData: String, assertion: String) {
        self.challengeID = challengeID
        self.clientData = clientData
        self.assertion = assertion
    }
}

public protocol RuntimeGenerationCredentialProvider: Sendable {
    func bearerToken() async throws -> String
    func assertionHeaders(for requestBody: Data, idempotencyKey: String) async throws -> GenerationAssertionHeaders
}

public protocol GenerationSessionCredentialStore: Sendable {
    func bearerToken() async throws -> String?
    func appAttestKeyID() async throws -> String?
    func saveBearerToken(_ token: String) async throws
    func saveAppAttestKeyID(_ keyID: String) async throws
    func clearSession() async throws
}

public enum GenerationAppAttestError: Error, Equatable {
    case invalidKey
}

public protocol GenerationAppAttestService: Sendable {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data
}

public protocol GenerationSessionEnrollmentTransport: Sendable {
    func requestChallenge() async throws -> GenerationEnrollmentChallenge
    func enroll(keyID: String, challenge: GenerationEnrollmentChallenge, attestationObject: Data) async throws -> String
}

public struct GenerationEnrollmentChallenge: Sendable {
    public let challengeID: String
    public let challengeBase64: String

    public init(challengeID: String, challengeBase64: String) {
        self.challengeID = challengeID
        self.challengeBase64 = challengeBase64
    }
}

/// Reads a server-issued bearer session from Keychain and enrolls a new App Attest
/// key when needed. The app never embeds a provider key or backend bearer token.
public struct KeychainGenerationCredentialStore: GenerationSessionCredentialStore {
    public static let defaultService = "com.craftberry.app.generation-session"
    public static let defaultAccount = "bearer"

    private let service: String

    public init(service: String = defaultService) {
        self.service = service
    }

    public func bearerToken() async throws -> String? {
        try read(account: Self.defaultAccount).flatMap { String(data: $0, encoding: .utf8) }
    }

    public func appAttestKeyID() async throws -> String? {
        try read(account: "app-attest-key-id").flatMap { String(data: $0, encoding: .utf8) }
    }

    public func saveBearerToken(_ token: String) async throws {
        try save(Data(token.utf8), account: Self.defaultAccount)
    }

    public func saveAppAttestKeyID(_ keyID: String) async throws {
        try save(Data(keyID.utf8), account: "app-attest-key-id")
    }

    public func clearSession() async throws {
        #if canImport(Security)
        for account in [Self.defaultAccount, "app-attest-key-id"] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw BackendGenerationClientError.missingCredential
            }
        }
        #endif
    }

    private func read(account: String) throws -> Data? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw BackendGenerationClientError.missingCredential
        }
        return data
        #else
        return nil
        #endif
    }

    private func save(_ data: Data, account: String) throws {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var insertion = query
            insertion[kSecValueData as String] = data
            insertion[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess else {
                throw BackendGenerationClientError.missingCredential
            }
        } else if update != errSecSuccess {
            throw BackendGenerationClientError.missingCredential
        }
        #else
        throw BackendGenerationClientError.missingCredential
        #endif
    }
}

public struct SystemGenerationAppAttestService: GenerationAppAttestService {
    public init() {}

    public var isSupported: Bool {
        #if canImport(DeviceCheck)
        DCAppAttestService.shared.isSupported
        #else
        false
        #endif
    }

    public func generateKey() async throws -> String {
        #if canImport(DeviceCheck)
        try await DCAppAttestService.shared.generateKey()
        #else
        throw BackendGenerationClientError.missingCredential
        #endif
    }

    public func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        #if canImport(DeviceCheck)
        try await DCAppAttestService.shared.attestKey(keyID, clientDataHash: clientDataHash)
        #else
        throw BackendGenerationClientError.missingCredential
        #endif
    }

    public func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        #if canImport(DeviceCheck)
        do {
            return try await DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: clientDataHash)
        } catch let error as DCError where error.code == .invalidKey {
            throw GenerationAppAttestError.invalidKey
        }
        #else
        throw BackendGenerationClientError.missingCredential
        #endif
    }
}

public struct URLSessionGenerationEnrollmentTransport: GenerationSessionEnrollmentTransport {
    private let baseURL: URL?
    private let session: URLSession

    public init(baseURL: URL?, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func requestChallenge() async throws -> GenerationEnrollmentChallenge {
        let data = try await post(path: "v1/session/challenge", body: Data("{}".utf8))
        let response = try JSONDecoder().decode(ChallengeResponse.self, from: data)
        return GenerationEnrollmentChallenge(challengeID: response.challengeID, challengeBase64: response.challenge)
    }

    public func enroll(
        keyID: String,
        challenge: GenerationEnrollmentChallenge,
        attestationObject: Data
    ) async throws -> String {
        let requestBody = EnrollmentRequestDocument(
            challengeID: challenge.challengeID,
            keyID: keyID,
            attestationObject: attestationObject.base64EncodedString()
        )
        let data = try await post(path: "v1/session/enroll", body: try JSONEncoder().encode(requestBody))
        let response = try JSONDecoder().decode(EnrollmentResponseDocument.self, from: data)
        guard !response.sessionToken.isEmpty else { throw BackendGenerationClientError.invalidResponse }
        return response.sessionToken
    }

    private func post(path: String, body: Data) async throws -> Data {
        guard let baseURL else { throw BackendGenerationClientError.endpointNotConfigured }
        guard baseURL.scheme?.lowercased() == "https", baseURL.host != nil,
              baseURL.query == nil, baseURL.fragment == nil else {
            throw BackendGenerationClientError.invalidEndpoint
        }
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw BackendGenerationClientError.transportUnavailable
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendGenerationClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 { throw BackendGenerationClientError.unauthorized }
            throw BackendGenerationClientError.transportUnavailable
        }
        return data
    }
}

private struct ChallengeResponse: Decodable {
    let challengeID: String
    let challenge: String
}

private struct EnrollmentRequestDocument: Encodable {
    let challengeID: String
    let keyID: String
    let attestationObject: String
}

private struct EnrollmentResponseDocument: Decodable {
    let sessionToken: String
}

/// Runtime provider that enrolls exactly once while concurrent requests share the
/// same in-flight enrollment operation.
public actor KeychainGenerationCredentialProvider: RuntimeGenerationCredentialProvider {
    private let credentialStore: any GenerationSessionCredentialStore
    private let appAttestService: any GenerationAppAttestService
    private let enrollmentTransport: any GenerationSessionEnrollmentTransport
    private var enrollmentTask: Task<String, Error>?
    private var credentialResetTask: (id: UUID, task: Task<Void, Error>)?
    private var requiresEnrollmentAfterInvalidKey = false
    private var credentialGeneration: UInt64 = 0

    public init(
        baseURL: URL?,
        session: URLSession = .shared,
        credentialStore: any GenerationSessionCredentialStore = KeychainGenerationCredentialStore(),
        appAttestService: any GenerationAppAttestService = SystemGenerationAppAttestService(),
        enrollmentTransport: (any GenerationSessionEnrollmentTransport)? = nil
    ) {
        self.credentialStore = credentialStore
        self.appAttestService = appAttestService
        self.enrollmentTransport = enrollmentTransport ?? URLSessionGenerationEnrollmentTransport(
            baseURL: baseURL,
            session: session
        )
    }

    public func bearerToken() async throws -> String {
        try await awaitCredentialResetIfNeeded()
        if !requiresEnrollmentAfterInvalidKey,
           let token = try await credentialStore.bearerToken(),
           !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return token
        }
        if let enrollmentTask {
            let token = try await enrollmentTask.value
            requiresEnrollmentAfterInvalidKey = false
            return token
        }
        let task = Task { try await self.enrollInstallation() }
        enrollmentTask = task
        defer { enrollmentTask = nil }
        let token = try await task.value
        requiresEnrollmentAfterInvalidKey = false
        return token
    }

    public func assertionHeaders(for requestBody: Data, idempotencyKey: String) async throws -> GenerationAssertionHeaders {
        try await awaitCredentialResetIfNeeded()
        guard !requiresEnrollmentAfterInvalidKey else {
            throw BackendGenerationClientError.appAttestKeyInvalid
        }
        let assertionGeneration = credentialGeneration
        guard appAttestService.isSupported,
              let keyID = try await credentialStore.appAttestKeyID(),
              !keyID.isEmpty else {
            throw BackendGenerationClientError.missingCredential
        }
        let challenge = try await enrollmentTransport.requestChallenge()
        guard let challengeBytes = Data(base64Encoded: challenge.challengeBase64), challengeBytes.count >= 16 else {
            throw BackendGenerationClientError.invalidResponse
        }
        let clientData = GenerationAssertionClientData(
            challengeID: challenge.challengeID,
            challenge: challenge.challengeBase64,
            requestBodySHA256: Self.base64URL(Data(SHA256.hash(data: requestBody))),
            idempotencyKey: idempotencyKey
        )
        let encodedClientData = try clientData.canonicalData()
        let clientDataHash = Data(SHA256.hash(data: encodedClientData))
        let assertion: Data
        do {
            assertion = try await appAttestService.generateAssertion(keyID, clientDataHash: clientDataHash)
        } catch GenerationAppAttestError.invalidKey {
            guard credentialGeneration == assertionGeneration else {
                throw BackendGenerationClientError.appAttestKeyInvalid
            }
            requiresEnrollmentAfterInvalidKey = true
            credentialGeneration &+= 1
            if credentialResetTask == nil {
                let store = credentialStore
                credentialResetTask = (UUID(), Task { try await store.clearSession() })
            }
            try await awaitCredentialResetIfNeeded()
            throw BackendGenerationClientError.appAttestKeyInvalid
        }
        return GenerationAssertionHeaders(
            challengeID: challenge.challengeID,
            clientData: encodedClientData.base64EncodedString(),
            assertion: assertion.base64EncodedString()
        )
    }

    private func enrollInstallation() async throws -> String {
        guard appAttestService.isSupported else { throw BackendGenerationClientError.missingCredential }
        let keyID = try await appAttestService.generateKey()
        let challenge = try await enrollmentTransport.requestChallenge()
        guard let challengeData = Data(base64Encoded: challenge.challengeBase64), !challengeData.isEmpty else {
            throw BackendGenerationClientError.invalidResponse
        }
        #if canImport(CryptoKit)
        let clientDataHash = Data(SHA256.hash(data: challengeData))
        #else
        throw BackendGenerationClientError.missingCredential
        #endif
        let attestation = try await appAttestService.attestKey(keyID, clientDataHash: clientDataHash)
        let token = try await enrollmentTransport.enroll(
            keyID: keyID,
            challenge: challenge,
            attestationObject: attestation
        )
        try await credentialStore.saveAppAttestKeyID(keyID)
        try await credentialStore.saveBearerToken(token)
        credentialGeneration &+= 1
        return token
    }

    private func awaitCredentialResetIfNeeded() async throws {
        guard let reset = credentialResetTask else { return }
        do {
            try await reset.task.value
        } catch {
            if credentialResetTask?.id == reset.id {
                credentialResetTask = nil
            }
            throw error
        }
        if credentialResetTask?.id == reset.id {
            credentialResetTask = nil
        }
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public enum BackendGenerationClientError: LocalizedError, Equatable {
    case endpointNotConfigured
    case invalidEndpoint
    case missingCredential
    case unauthorized
    case appAttestKeyInvalid
    case quotaExceeded
    case serviceUnavailable
    case transportUnavailable
    case requestFailed(statusCode: Int)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .endpointNotConfigured:
            "Generation service is not configured for this build."
        case .invalidEndpoint:
            "Generation service endpoint must be a valid HTTPS URL."
        case .missingCredential:
            "A generation session is not available. Reconnect and try again."
        case .unauthorized:
            "Your generation session has expired. Reconnect and try again."
        case .appAttestKeyInvalid:
            "This device's generation key has expired. Reconnecting and retrying."
        case .quotaExceeded:
            "The generation limit has been reached. Try again later."
        case .serviceUnavailable:
            "The generation service is temporarily unavailable. Try again later."
        case .transportUnavailable:
            "Couldn't connect to the generation service. Check your connection and try again."
        case .requestFailed(let statusCode):
            "Generation failed (HTTP \(statusCode)). Please try again."
        case .invalidResponse:
            "The generation service returned an unusable result. Please try again."
        }
    }
}

/// URLSession client for the versioned first-party generation API. Intent parsing,
/// project identifiers, and profile validation stay in the local Swift assembler.
public struct BackendGenerationClient: LLMClient {
    private let baseURL: URL?
    private let credentialProvider: any RuntimeGenerationCredentialProvider
    private let session: URLSession
    private let identityGenerator: @Sendable () -> AddOnProjectIdentity

    public init(
        baseURL: URL?,
        credentialProvider: any RuntimeGenerationCredentialProvider,
        session: URLSession = .shared,
        identityGenerator: @escaping @Sendable () -> AddOnProjectIdentity = { .generate() }
    ) {
        self.baseURL = baseURL
        self.credentialProvider = credentialProvider
        self.session = session
        self.identityGenerator = identityGenerator
    }

    public func generateProject(from prompt: String) async throws -> ProjectGeneration {
        guard let baseURL else { throw BackendGenerationClientError.endpointNotConfigured }
        guard baseURL.scheme?.lowercased() == "https",
              baseURL.host != nil,
              baseURL.query == nil,
              baseURL.fragment == nil else {
            throw BackendGenerationClientError.invalidEndpoint
        }

        let idempotencyKey = UUID().uuidString.lowercased()
        let requestBody = try JSONEncoder().encode(GenerationRequest(prompt: prompt))
        var didRetryTransientFailure = false
        var didRepairInvalidKey = false
        var processingPolls = 0
        while true {
            let token = try await credentialProvider.bearerToken()
            guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BackendGenerationClientError.missingCredential
            }
            let assertionHeaders: GenerationAssertionHeaders
            do {
                assertionHeaders = try await credentialProvider.assertionHeaders(
                    for: requestBody,
                    idempotencyKey: idempotencyKey
                )
            } catch BackendGenerationClientError.appAttestKeyInvalid where !didRepairInvalidKey {
                didRepairInvalidKey = true
                continue
            }
            var request = URLRequest(url: baseURL.appending(path: "v1/generate"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
            request.setValue(assertionHeaders.challengeID, forHTTPHeaderField: "App-Attest-Challenge-ID")
            request.setValue(assertionHeaders.clientData, forHTTPHeaderField: "App-Attest-Client-Data")
            request.setValue(assertionHeaders.assertion, forHTTPHeaderField: "App-Attest-Assertion")
            request.httpBody = requestBody

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw error
            } catch {
                guard !didRetryTransientFailure else { throw BackendGenerationClientError.transportUnavailable }
                didRetryTransientFailure = true
                continue
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw BackendGenerationClientError.invalidResponse
            }
            if (500...599).contains(httpResponse.statusCode), !didRetryTransientFailure {
                didRetryTransientFailure = true
                continue
            }
            if httpResponse.statusCode == 409 {
                let errorCode = (try? JSONDecoder().decode(BackendErrorResponse.self, from: data))?.error
                if errorCode == "generation_in_progress", processingPolls < 3 {
                    processingPolls += 1
                    try await Self.waitBeforeProcessingRetry(response: httpResponse)
                    continue
                }
                if errorCode == "idempotency_conflict" {
                    throw BackendGenerationClientError.requestFailed(statusCode: 409)
                }
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                switch httpResponse.statusCode {
                case 401:
                    throw BackendGenerationClientError.unauthorized
                case 429:
                    throw BackendGenerationClientError.quotaExceeded
                case 500...599:
                    throw BackendGenerationClientError.serviceUnavailable
                default:
                    throw BackendGenerationClientError.requestFailed(statusCode: httpResponse.statusCode)
                }
            }

            guard let intent = String(data: data, encoding: .utf8) else {
                throw BackendGenerationClientError.invalidResponse
            }
            do {
                return try OpenAIResponsesClient.assembleProject(
                    from: intent,
                    prompt: prompt,
                    identityGenerator: identityGenerator
                )
            } catch {
                throw BackendGenerationClientError.invalidResponse
            }
        }
    }

    private static func waitBeforeProcessingRetry(response: HTTPURLResponse) async throws {
        let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
            .flatMap(TimeInterval.init)
            .map { min(max($0, 0), 2) } ?? 1
        guard retryAfter > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
    }
}

private struct BackendErrorResponse: Decodable {
    let error: String
}

private struct GenerationRequest: Encodable {
    let intentVersion = 1
    let profileID = BedrockContentProfile.current.id
    let prompt: String
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
    let materialConsumableSet: MaterialConsumableSetIntent?
    let materialBlockSet: MaterialBlockSetIntent?
    let materialFurnaceSet: MaterialFurnaceSetIntent?
    let materialSmithingSet: MaterialSmithingSetIntent?
    let materialBrewingSet: MaterialBrewingSetIntent?
    let materialOreSet: MaterialBlockSetIntent?
    let materialCropSet: MaterialCropSetIntent?
    let materialStructureSet: MaterialStructureSetIntent?
    let materialHostileEntitySet: MaterialHostileEntitySetIntent?
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

private struct MaterialConsumableSetIntent: Decodable {
    let materialName: String
    let color: PixelArtColor
    let sourceItem: FoundationSwordIngredient
    let sourceCount: Int
    let nutrition: Int
    let saturationModifier: String
    let canAlwaysEat: Bool
    let fuelDuration: Double
}

private struct MaterialBlockSetIntent: Decodable {
    let materialName: String
    let color: PixelArtColor
    let sourceItem: FoundationSwordIngredient
    let sourceCount: Int
    let destroyTime: Double
    let mapColor: String
}

private struct MaterialFurnaceSetIntent: Decodable {
    let materialName: String
    let color: PixelArtColor
    let sourceItem: FoundationSwordIngredient
    let attackBonus: Int
    let durability: Int
}

private struct MaterialSmithingSetIntent: Decodable {
    let materialName: String
    let color: PixelArtColor
    let sourceItem: FoundationSwordIngredient
    let sourceCount: Int
    let attackBonus: Int
    let durability: Int
}

private struct MaterialBrewingSetIntent: Decodable {
    let materialName: String
    let color: PixelArtColor
    let sourceItem: FoundationSwordIngredient
    let sourceCount: Int
}

private struct MaterialCropSetIntent: Decodable {
    let materialName: String
    let color: PixelArtColor
    let sourceItem: FoundationSwordIngredient
    let sourceCount: Int
}

private struct MaterialStructureSetIntent: Decodable {
    let materialName: String
    let color: PixelArtColor
    let sourceItem: FoundationSwordIngredient
    let sourceCount: Int
    let destroyTime: Double
    let mapColor: String
}

private struct MaterialHostileEntitySetIntent: Decodable {
    let materialName: String
    let color: PixelArtColor
    let sourceItem: FoundationSwordIngredient
    let sourceCount: Int
    let health: Int
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
    Convert the request into exactly one supported Craftberry intent: a single custom sword, one named material ingot plus its matching sword, one named material ingot plus a matching sword/pickaxe/axe/shovel/hoe tool set, one named material ingot plus a matching sword/dagger/spear/hammer melee weapon set, one named material ingot plus a matching helmet/chestplate/leggings/boots armor set, one named material ingot plus food and fuel consumables, one named material ingot plus its storage block, one named material ingot plus a furnace-smelted ingot and its sword, one named material ingot plus a smithing-upgraded sword and armor trim using that ingot, one named material ingot plus a brewing-stand elixir that upgrades a potion via the ingot, one named material ingot plus its ore block, one named material seed plus its crop block and produce, one named material ingot plus its storage block and a 3x3 hut structure built from that block, or one named material ingot plus a hostile creature that attacks players.
    A material set makes a shapeless ingot from 1 through 9 copies of one supported vanilla material, then a sword from two ingots and a stick. Defaults are Azure, blue, diamond x4, attack 10, durability 500, names "Azure Ingot" and "Azure Sword". Never output Bedrock JSON, identifiers, UUIDs, filenames, code, markdown, or fields outside the schema.
    Material sword set swords can be enchanted at an enchanting table; requests for enchantable material sword sets are supported. Specific pre-applied enchantments are not supported.
    A material tool set uses the same ingot recipe and additionally crafts pickaxe, axe, shovel, and hoe variants from that ingot and sticks.
    A material weapon set uses the same ingot recipe and additionally crafts dagger, spear, and hammer variants from that ingot and sticks.
    A material armor set uses the same ingot recipe and additionally crafts a helmet, chestplate, leggings, and boots from that ingot alone (no sticks); protection is the set's total protection (4 through 20, default 15) and is split across the four pieces automatically, so never ask for a per-piece value.
    A material consumable set uses the same ingot recipe and additionally crafts a food (crafted from ingots) and a fuel (crafted from ingots) from that ingot; nutrition is 1 through 20, saturation modifier is 0.1 through 5.0 as a string, and fuel duration is 1.0 through 200.0.
    A material block set uses the same ingot recipe and additionally crafts a storage block from 9 ingots (3x3) and deconstructs 1 block back to 9 ingots (shapeless); destroyTime is 0.5 through 10.0 (default 3.0) and mapColor is one of the vanilla palette hex values.
    A material furnace set smelts its ingot in a furnace from one supported vanilla material (no count) instead of shapeless crafting, then crafts a sword from two ingots and a stick; attack and durability use the same defaults and limits as the sword set.
    A material smithing set uses the same ingot recipe and additionally crafts its sword at the smithing table via netherite_upgrade_smithing_template + diamond_sword + ingot, plus a ward armor trim that uses the ingot as trim material on trimmable armors; it uses the same defaults and limits as the sword set.
    A material brewing set uses the same ingot recipe and additionally brews an elixir at the brewing stand from a potion plus the ingot, then converts it to a splash potion with gunpowder; it uses the same defaults and limits as the sword set.
    A material ore set uses the same ingot recipe and additionally crafts an ore block from 9 ingots (3x3) that drops the ingot when mined; destroyTime and mapColor use the same defaults and limits as the block set.
    A material crop set makes seeds from 1 through 9 copies of one supported vanilla material (4 seeds), plus a produce food and a crop block with 8 growth stages (0..7) that drops produce when broken.
    A material structure set extends the block set with a 3x3 hut structure built from that block and placed via a structure template feature; it uses the same ingot/block defaults and limits as the block set.
    A material hostile creature set uses the same ingot recipe and additionally crafts a spawn egg for a hostile creature that attacks players. Health is 4 through 40 (default 20). Use the built-in pig geometry; do not generate scripts or custom geometry.
    If unsupported, set all intents and shortDescription to null. If ready, populate exactly one intent and write shortDescription as one short user-facing pack overview sentence.
    """

    private static let swordProperty: JSONValue = .object([
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

    private static let materialSwordSetProperty: JSONValue = .object(["anyOf": .array([
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
    ])])

    private static let materialToolSetProperty: JSONValue = .object(["anyOf": .array([
        .object(["type": .string("null")]),
        .object(["type": .string("object"), "additionalProperties": .bool(false), "required": .array(["materialName", "color", "sourceItem", "sourceCount", "attackBonus", "durability"].map(JSONValue.string)), "properties": .object([
            "materialName": .object(["type": .string("string"), "minLength": .integer(1), "maxLength": .integer(24)]),
            "color": .object(["type": .string("string"), "enum": .array(PixelArtColor.allCases.map { .string($0.rawValue) })]),
            "sourceItem": .object(["type": .string("string"), "enum": .array(FoundationSwordIngredient.allCases.map { .string($0.rawValue) })]),
            "sourceCount": .object(["type": .string("integer"), "minimum": .integer(1), "maximum": .integer(9)]),
            "attackBonus": .object(["type": .string("integer"), "minimum": .integer(1), "maximum": .integer(30)]),
            "durability": .object(["type": .string("integer"), "minimum": .integer(50), "maximum": .integer(2_000)])
        ])])
    ])])

    private static let materialWeaponSetProperty: JSONValue = .object(["anyOf": .array([
        .object(["type": .string("null")]),
        .object(["type": .string("object"), "additionalProperties": .bool(false), "required": .array(["materialName", "color", "sourceItem", "sourceCount", "attackBonus", "durability"].map(JSONValue.string)), "properties": .object([
            "materialName": .object(["type": .string("string"), "minLength": .integer(1), "maxLength": .integer(24)]),
            "color": .object(["type": .string("string"), "enum": .array(PixelArtColor.allCases.map { .string($0.rawValue) })]),
            "sourceItem": .object(["type": .string("string"), "enum": .array(FoundationSwordIngredient.allCases.map { .string($0.rawValue) })]),
            "sourceCount": .object(["type": .string("integer"), "minimum": .integer(1), "maximum": .integer(9)]),
            "attackBonus": .object(["type": .string("integer"), "minimum": .integer(1), "maximum": .integer(30)]),
            "durability": .object(["type": .string("integer"), "minimum": .integer(50), "maximum": .integer(2_000)])
        ])])
    ])])

    private static let materialArmorSetProperty: JSONValue = .object(["anyOf": .array([
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

    private static let materialConsumableSetProperty: JSONValue = .object(["anyOf": .array([
        .object(["type": .string("null")]),
        .object(["type": .string("object"), "additionalProperties": .bool(false), "required": .array(["materialName", "color", "sourceItem", "sourceCount", "nutrition", "saturationModifier", "canAlwaysEat", "fuelDuration"].map(JSONValue.string)), "properties": .object([
            "materialName": .object(["type": .string("string"), "minLength": .integer(1), "maxLength": .integer(24)]),
            "color": .object(["type": .string("string"), "enum": .array(PixelArtColor.allCases.map { .string($0.rawValue) })]),
            "sourceItem": .object(["type": .string("string"), "enum": .array(FoundationSwordIngredient.allCases.map { .string($0.rawValue) })]),
            "sourceCount": .object(["type": .string("integer"), "minimum": .integer(1), "maximum": .integer(9)]),
            "nutrition": .object(["type": .string("integer"), "minimum": .integer(1), "maximum": .integer(20)]),
            "saturationModifier": .object(["type": .string("string"), "enum": .array(["0.2","0.3","0.6","0.8","1.0","1.2","1.6","2.0"].map(JSONValue.string))]),
            "canAlwaysEat": .object(["type": .string("boolean")]),
            "fuelDuration": .object(["type": .string("number"), "minimum": .integer(1), "maximum": .integer(200)])
        ])])
    ])])

    private static let materialBlockSetProperty: JSONValue = .object(["anyOf": .array([
        .object(["type": .string("null")]),
        .object(["type": .string("object"), "additionalProperties": .bool(false), "required": .array(["materialName", "color", "sourceItem", "sourceCount", "destroyTime", "mapColor"].map(JSONValue.string)), "properties": .object([
            "materialName": .object(["type": .string("string"), "minLength": .integer(1), "maxLength": .integer(24)]),
            "color": .object(["type": .string("string"), "enum": .array(PixelArtColor.allCases.map { .string($0.rawValue) })]),
            "sourceItem": .object(["type": .string("string"), "enum": .array(FoundationSwordIngredient.allCases.map { .string($0.rawValue) })]),
            "sourceCount": .object(["type": .string("integer"), "minimum": .integer(1), "maximum": .integer(9)]),
            "destroyTime": .object(["type": .string("number"), "minimum": .integer(0), "maximum": .integer(10)]),
            "mapColor": .object(["type": .string("string"), "enum": .array(BlockMapColor.allCases.map { .string($0.rawValue) })])
        ])])
    ])])

    private static let materialFurnaceSetProperty: JSONValue = .object(["anyOf": .array([
        .object(["type": .string("null")]),
        .object(["type": .string("object"), "additionalProperties": .bool(false), "required": .array(["materialName", "color", "sourceItem", "attackBonus", "durability"].map(JSONValue.string)), "properties": .object([
            "materialName": .object(["type": .string("string"), "minLength": .integer(1), "maxLength": .integer(24)]),
            "color": .object(["type": .string("string"), "enum": .array(PixelArtColor.allCases.map { .string($0.rawValue) })]),
            "sourceItem": .object(["type": .string("string"), "enum": .array(FoundationSwordIngredient.allCases.map { .string($0.rawValue) })]),
            "attackBonus": .object(["type": .string("integer"), "minimum": .integer(1), "maximum": .integer(30)]),
            "durability": .object(["type": .string("integer"), "minimum": .integer(50), "maximum": .integer(2_000)])
        ])])
    ])])

    private static let materialBrewingSetProperty: JSONValue = .object(["anyOf": .array([
        .object(["type": .string("null")]),
        .object(["type": .string("object"), "additionalProperties": .bool(false), "required": .array(["materialName", "color", "sourceItem", "sourceCount"].map(JSONValue.string)), "properties": .object([
            "materialName": .object(["type": .string("string"), "minLength": .integer(1), "maxLength": .integer(24)]),
            "color": .object(["type": .string("string"), "enum": .array(PixelArtColor.allCases.map { .string($0.rawValue) })]),
            "sourceItem": .object(["type": .string("string"), "enum": .array(FoundationSwordIngredient.allCases.map { .string($0.rawValue) })]),
            "sourceCount": .object(["type": .string("integer"), "minimum": .integer(1), "maximum": .integer(9)])
        ])])
    ])])

    private static let materialSmithingSetProperty: JSONValue = .object(["anyOf": .array([
        .object(["type": .string("null")]),
        .object(["type": .string("object"), "additionalProperties": .bool(false), "required": .array(["materialName", "color", "sourceItem", "sourceCount", "attackBonus", "durability"].map(JSONValue.string)), "properties": .object([
            "materialName": .object(["type": .string("string"), "minLength": .integer(1), "maxLength": .integer(24)]),
            "color": .object(["type": .string("string"), "enum": .array(PixelArtColor.allCases.map { .string($0.rawValue) })]),
            "sourceItem": .object(["type": .string("string"), "enum": .array(FoundationSwordIngredient.allCases.map { .string($0.rawValue) })]),
            "sourceCount": .object(["type": .string("integer"), "minimum": .integer(1), "maximum": .integer(9)]),
            "attackBonus": .object(["type": .string("integer"), "minimum": .integer(1), "maximum": .integer(30)]),
            "durability": .object(["type": .string("integer"), "minimum": .integer(50), "maximum": .integer(2_000)])
        ])])
    ])])

    private static let materialOreSetProperty: JSONValue = materialBlockSetProperty
    private static let materialStructureSetProperty: JSONValue = .object(["anyOf": .array([
        .object(["type": .string("null")]),
        .object(["type": .string("object"), "additionalProperties": .bool(false), "required": .array(["materialName", "color", "sourceItem", "sourceCount", "destroyTime", "mapColor"].map(JSONValue.string)), "properties": .object([
            "materialName": .object(["type": .string("string"), "minLength": .integer(1), "maxLength": .integer(24)]),
            "color": .object(["type": .string("string"), "enum": .array(PixelArtColor.allCases.map { .string($0.rawValue) })]),
            "sourceItem": .object(["type": .string("string"), "enum": .array(FoundationSwordIngredient.allCases.map { .string($0.rawValue) })]),
            "sourceCount": .object(["type": .string("integer"), "minimum": .integer(1), "maximum": .integer(9)]),
            "destroyTime": .object(["type": .string("number"), "minimum": .integer(0), "maximum": .integer(10)]),
            "mapColor": .object(["type": .string("string"), "enum": .array(BlockMapColor.allCases.map { .string($0.rawValue) })])
        ])])
    ])])

    private static let materialHostileEntitySetProperty: JSONValue = .object(["anyOf": .array([
        .object(["type": .string("null")]),
        .object(["type": .string("object"), "additionalProperties": .bool(false), "required": .array(["materialName", "color", "sourceItem", "sourceCount", "health"].map(JSONValue.string)), "properties": .object([
            "materialName": .object(["type": .string("string"), "minLength": .integer(1), "maxLength": .integer(24)]),
            "color": .object(["type": .string("string"), "enum": .array(PixelArtColor.allCases.map { .string($0.rawValue) })]),
            "sourceItem": .object(["type": .string("string"), "enum": .array(FoundationSwordIngredient.allCases.map { .string($0.rawValue) })]),
            "sourceCount": .object(["type": .string("integer"), "minimum": .integer(1), "maximum": .integer(9)]),
            "health": .object(["type": .string("integer"), "minimum": .integer(4), "maximum": .integer(40)])
        ])])
    ])])

    private static let materialCropSetProperty: JSONValue = .object(["anyOf": .array([
        .object(["type": .string("null")]),
        .object(["type": .string("object"), "additionalProperties": .bool(false), "required": .array(["materialName", "color", "sourceItem", "sourceCount"].map(JSONValue.string)), "properties": .object([
            "materialName": .object(["type": .string("string"), "minLength": .integer(1), "maxLength": .integer(24)]),
            "color": .object(["type": .string("string"), "enum": .array(PixelArtColor.allCases.map { .string($0.rawValue) })]),
            "sourceItem": .object(["type": .string("string"), "enum": .array(FoundationSwordIngredient.allCases.map { .string($0.rawValue) })]),
            "sourceCount": .object(["type": .string("integer"), "minimum": .integer(1), "maximum": .integer(9)])
        ])])
    ])])

    private static let schema: JSONValue = .object([
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "required": .array(["schemaVersion", "outcome", "message", "shortDescription", "sword", "materialSwordSet", "materialToolSet", "materialWeaponSet", "materialArmorSet", "materialConsumableSet", "materialBlockSet", "materialFurnaceSet", "materialSmithingSet", "materialBrewingSet", "materialOreSet", "materialCropSet", "materialStructureSet", "materialHostileEntitySet"].map(JSONValue.string)),
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
            "sword": swordProperty,
            "materialSwordSet": materialSwordSetProperty,
            "materialToolSet": materialToolSetProperty,
            "materialWeaponSet": materialWeaponSetProperty,
            "materialArmorSet": materialArmorSetProperty,
            "materialConsumableSet": materialConsumableSetProperty,
            "materialBlockSet": materialBlockSetProperty,
            "materialFurnaceSet": materialFurnaceSetProperty,
            "materialSmithingSet": materialSmithingSetProperty,
            "materialBrewingSet": materialBrewingSetProperty,
            "materialOreSet": materialOreSetProperty,
            "materialCropSet": materialCropSetProperty,
            "materialStructureSet": materialStructureSetProperty,
            "materialHostileEntitySet": materialHostileEntitySetProperty
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
