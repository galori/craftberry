import CryptoKit
import Foundation

public enum AppAttestEnvironment: String, Codable, Sendable {
    case development
    case production
}

public struct GenerationServiceRequest: Sendable {
    public let method: String
    public let path: String
    public let headers: [String: String]
    public let body: Data

    public init(method: String, path: String, headers: [String: String] = [:], body: Data = Data()) {
        self.method = method.uppercased()
        self.path = path
        self.headers = headers
        self.body = body
    }

    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

public struct GenerationServiceResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

public struct GenerationQuotaPolicy: Equatable, Sendable {
    public let perMinute: Int
    public let perHour: Int
    public let perDay: Int

    public init(perMinute: Int = 5, perHour: Int = 10, perDay: Int = 30) {
        self.perMinute = perMinute
        self.perHour = perHour
        self.perDay = perDay
    }

    public static let `default` = GenerationQuotaPolicy()
}

public struct GenerationServiceConfiguration: Sendable {
    public let expectedAppIdentifier: String
    public let appAttestEnvironment: AppAttestEnvironment
    public let profileID: String
    public let maxPromptCharacters: Int
    public let maxRequestBytes: Int
    public let enrollmentChallengeLifetime: TimeInterval
    public let generationQuota: GenerationQuotaPolicy

    public init(
        expectedAppIdentifier: String,
        appAttestEnvironment: AppAttestEnvironment,
        profileID: String = BedrockContentProfile.current.id,
        maxPromptCharacters: Int = 600,
        maxRequestBytes: Int = 65_536,
        enrollmentChallengeLifetime: TimeInterval = 300,
        generationQuota: GenerationQuotaPolicy = .default
    ) {
        self.expectedAppIdentifier = expectedAppIdentifier
        self.appAttestEnvironment = appAttestEnvironment
        self.profileID = profileID
        self.maxPromptCharacters = maxPromptCharacters
        self.maxRequestBytes = maxRequestBytes
        self.enrollmentChallengeLifetime = enrollmentChallengeLifetime
        self.generationQuota = generationQuota
    }
}

public protocol GenerationServiceClock: Sendable {
    func now() -> Date
}

public struct SystemGenerationServiceClock: GenerationServiceClock {
    public init() {}
    public func now() -> Date { Date() }
}

public struct StoredEnrollmentChallenge: Sendable {
    public let id: String
    public let challenge: Data
    public let expiresAt: Date

    public init(id: String, challenge: Data, expiresAt: Date) {
        self.id = id
        self.challenge = challenge
        self.expiresAt = expiresAt
    }
}

public struct VerifiedAppAttestKey: Sendable {
    public let keyID: String
    public let publicKey: Data
    public let appIdentifier: String
    public let environment: AppAttestEnvironment
    public let bundleVersion: String
    public let receipt: Data

    public init(
        keyID: String,
        publicKey: Data,
        appIdentifier: String,
        environment: AppAttestEnvironment,
        bundleVersion: String,
        receipt: Data = Data()
    ) {
        self.keyID = keyID
        self.publicKey = publicKey
        self.appIdentifier = appIdentifier
        self.environment = environment
        self.bundleVersion = bundleVersion
        self.receipt = receipt
    }
}

public struct GenerationInstallationRegistration: Sendable {
    public let installationID: UUID
    public let keyID: String
    public let publicKey: Data
    public let appIdentifier: String
    public let environment: AppAttestEnvironment
    public let bundleVersion: String
    public let receipt: Data
    public let enrolledAt: Date

    public init(
        installationID: UUID,
        verifiedKey: VerifiedAppAttestKey,
        enrolledAt: Date
    ) {
        self.installationID = installationID
        self.keyID = verifiedKey.keyID
        self.publicKey = verifiedKey.publicKey
        self.appIdentifier = verifiedKey.appIdentifier
        self.environment = verifiedKey.environment
        self.bundleVersion = verifiedKey.bundleVersion
        self.receipt = verifiedKey.receipt
        self.enrolledAt = enrolledAt
    }
}

public struct StoredAppAttestCredential: Sendable {
    public let installationID: UUID
    public let keyID: String
    public let publicKey: Data
    public let appIdentifier: String
    public let environment: AppAttestEnvironment
    public let bundleVersion: String
    public let assertionCounter: UInt32

    public init(
        installationID: UUID,
        keyID: String,
        publicKey: Data,
        appIdentifier: String,
        environment: AppAttestEnvironment,
        bundleVersion: String,
        assertionCounter: UInt32
    ) {
        self.installationID = installationID
        self.keyID = keyID
        self.publicKey = publicKey
        self.appIdentifier = appIdentifier
        self.environment = environment
        self.bundleVersion = bundleVersion
        self.assertionCounter = assertionCounter
    }
}

public struct VerifiedAppAttestAssertion: Equatable, Sendable {
    public let counter: UInt32

    public init(counter: UInt32) {
        self.counter = counter
    }
}

public enum GenerationQuotaWindow: String, Sendable {
    case minute
    case hour
    case day

    public var retryAfter: Int {
        switch self {
        case .minute: 60
        case .hour: 3_600
        case .day: 86_400
        }
    }
}

public enum GenerationReservation: Sendable {
    case reserved(UUID)
    case replay(Data)
    case inProgress
    case idempotencyConflict
    case limited(GenerationQuotaWindow)
}

/// A production store must consume enrollment/assertion challenges atomically with
/// installation/counter updates and durably persist quota events before `.reserved`.
public protocol GenerationServiceStore: Sendable {
    func createEnrollmentChallenge(_ challenge: StoredEnrollmentChallenge, now: Date) async throws
    func enrollmentChallenge(id: String, now: Date) async throws -> StoredEnrollmentChallenge?
    func registerInstallation(
        challengeID: String,
        registration: GenerationInstallationRegistration,
        tokenDigest: Data,
        now: Date
    ) async throws -> Bool
    func installationID(forTokenDigest digest: Data) async throws -> UUID?
    func appAttestCredential(for installationID: UUID) async throws -> StoredAppAttestCredential?
    func appAttestReceipt(for installationID: UUID) async throws -> Data?
    func consumeAppAttestAssertion(
        challengeID: String,
        installationID: UUID,
        expectedCounter: UInt32,
        newCounter: UInt32,
        now: Date
    ) async throws -> Bool
    func reserveGeneration(
        installationID: UUID,
        idempotencyKey: String,
        requestFingerprint: Data,
        now: Date,
        quota: GenerationQuotaPolicy
    ) async throws -> GenerationReservation
    func completeGeneration(
        installationID: UUID,
        idempotencyKey: String,
        reservationID: UUID,
        response: Data,
        now: Date
    ) async throws -> Bool
    func markGenerationRetryable(
        installationID: UUID,
        idempotencyKey: String,
        reservationID: UUID,
        now: Date
    ) async throws -> Bool
}

public protocol AppAttestVerifying: Sendable {
    func verifyAttestation(
        object: Data,
        keyID: String,
        challenge: Data,
        expectedAppIdentifier: String,
        expectedEnvironment: AppAttestEnvironment
    ) async throws -> VerifiedAppAttestKey
    func verifyAssertion(
        object: Data,
        clientData: Data,
        credential: StoredAppAttestCredential,
        expectedAppIdentifier: String,
        expectedEnvironment: AppAttestEnvironment
    ) async throws -> VerifiedAppAttestAssertion
}

public protocol GenerationIntentProviding: Sendable {
    func generateIntent(prompt: String) async throws -> String
}

public enum GenerationIntentProviderError: Error, Equatable {
    case missingProviderCredential
}

/// The provider credential is read only from the server process environment.
public struct EnvironmentOpenAIIntentProvider: GenerationIntentProviding {
    private let apiKey: String?
    private let session: URLSession

    public init(environment: [String: String] = ProcessInfo.processInfo.environment, session: URLSession = .shared) {
        let configuredKey = environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKey = configuredKey?.isEmpty == false ? configuredKey : nil
        self.session = session
    }

    public func generateIntent(prompt: String) async throws -> String {
        guard let apiKey else { throw GenerationIntentProviderError.missingProviderCredential }
        return try await OpenAIResponsesClient(apiKey: apiKey, session: session).generateIntentJSON(from: prompt)
    }
}

public struct GenerationService: Sendable {
    private let configuration: GenerationServiceConfiguration
    private let store: any GenerationServiceStore
    private let attestationVerifier: any AppAttestVerifying
    private let intentProvider: any GenerationIntentProviding
    private let clock: any GenerationServiceClock
    private let randomBytes: @Sendable (Int) -> Data

    public init(
        configuration: GenerationServiceConfiguration,
        store: any GenerationServiceStore,
        attestationVerifier: any AppAttestVerifying,
        intentProvider: any GenerationIntentProviding,
        clock: any GenerationServiceClock = SystemGenerationServiceClock(),
        randomBytes: (@Sendable (Int) -> Data)? = nil
    ) {
        self.configuration = configuration
        self.store = store
        self.attestationVerifier = attestationVerifier
        self.intentProvider = intentProvider
        self.clock = clock
        self.randomBytes = randomBytes ?? Self.secureRandomBytes
    }

    public func handle(_ request: GenerationServiceRequest) async -> GenerationServiceResponse {
        switch (request.method, request.path) {
        case ("POST", "/v1/session/challenge"):
            await issueEnrollmentChallenge(request)
        case ("POST", "/v1/session/enroll"):
            await enroll(request)
        case ("POST", "/v1/generate"):
            await generate(request)
        default:
            response(status: 404, error: "not_found")
        }
    }

    private func issueEnrollmentChallenge(_ request: GenerationServiceRequest) async -> GenerationServiceResponse {
        guard request.body.count <= 1_024 else { return response(status: 413, error: "request_too_large") }
        let challenge = StoredEnrollmentChallenge(
            id: UUID().uuidString.lowercased(),
            challenge: randomBytes(32),
            expiresAt: clock.now().addingTimeInterval(configuration.enrollmentChallengeLifetime)
        )
        guard challenge.challenge.count == 32 else { return response(status: 503, error: "service_unavailable") }
        do {
            try await store.createEnrollmentChallenge(challenge, now: clock.now())
            return response(
                status: 200,
                payload: EnrollmentChallengeResponse(
                    challengeID: challenge.id,
                    challenge: challenge.challenge.base64EncodedString(),
                    expiresAt: ISO8601DateFormatter().string(from: challenge.expiresAt)
                )
            )
        } catch {
            return response(status: 503, error: "service_unavailable")
        }
    }

    private func enroll(_ request: GenerationServiceRequest) async -> GenerationServiceResponse {
        guard request.body.count <= configuration.maxRequestBytes else {
            return response(status: 413, error: "request_too_large")
        }
        guard let body = try? JSONDecoder().decode(EnrollmentRequest.self, from: request.body),
              !body.keyID.isEmpty,
              let object = Data(base64Encoded: body.attestationObject) else {
            return response(status: 400, error: "invalid_request")
        }

        let now = clock.now()
        do {
            guard let challenge = try await store.enrollmentChallenge(id: body.challengeID, now: now) else {
                return response(status: 401, error: "unauthorized")
            }
            let verified: VerifiedAppAttestKey
            do {
                verified = try await attestationVerifier.verifyAttestation(
                    object: object,
                    keyID: body.keyID,
                    challenge: challenge.challenge,
                    expectedAppIdentifier: configuration.expectedAppIdentifier,
                    expectedEnvironment: configuration.appAttestEnvironment
                )
            } catch {
                return response(status: 401, error: "unauthorized")
            }
            guard verified.keyID == body.keyID,
                  verified.appIdentifier == configuration.expectedAppIdentifier,
                  verified.environment == configuration.appAttestEnvironment,
                  !verified.publicKey.isEmpty,
                  !verified.receipt.isEmpty else {
                return response(status: 401, error: "unauthorized")
            }

            let sessionToken = Self.base64URL(randomBytes(32))
            guard Data(base64URL: sessionToken)?.count == 32 else {
                return response(status: 503, error: "service_unavailable")
            }
            let digest = Data(SHA256.hash(data: Data(sessionToken.utf8)))
            let registrationTime = clock.now()
            let registration = GenerationInstallationRegistration(
                installationID: UUID(),
                verifiedKey: verified,
                enrolledAt: registrationTime
            )
            let registered = try await store.registerInstallation(
                challengeID: body.challengeID,
                registration: registration,
                tokenDigest: digest,
                now: registrationTime
            )
            guard registered else { return response(status: 401, error: "unauthorized") }
            return response(status: 200, payload: EnrollmentResponse(sessionToken: sessionToken))
        } catch {
            return response(status: 503, error: "service_unavailable")
        }
    }

    private func generate(_ request: GenerationServiceRequest) async -> GenerationServiceResponse {
        guard request.body.count <= configuration.maxRequestBytes else {
            return response(status: 413, error: "request_too_large")
        }
        guard let bearer = bearerToken(from: request.header("Authorization")) else {
            return response(status: 401, error: "unauthorized")
        }
        guard let body = try? JSONDecoder().decode(GenerationRequest.self, from: request.body),
              body.intentVersion == 1,
              body.profileID == configuration.profileID,
              !body.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return response(status: 400, error: "invalid_request")
        }
        guard body.prompt.count <= configuration.maxPromptCharacters else {
            return response(status: 400, error: "prompt_too_long")
        }
        let installationID: UUID?
        do {
            installationID = try await store.installationID(
                forTokenDigest: Data(SHA256.hash(data: Data(bearer.utf8)))
            )
        } catch {
            return response(status: 503, error: "service_unavailable")
        }
        guard let installationID else { return response(status: 401, error: "unauthorized") }

        let idempotencyKey = request.header("Idempotency-Key") ?? UUID().uuidString.lowercased()
        guard Self.isValidIdempotencyKey(idempotencyKey) else {
            return response(status: 400, error: "invalid_idempotency_key")
        }
        guard let challengeID = request.header("App-Attest-Challenge-ID"),
              let clientDataBase64 = request.header("App-Attest-Client-Data"),
              let clientData = Data(base64Encoded: clientDataBase64),
              let assertionBase64 = request.header("App-Attest-Assertion"),
              let assertionObject = Data(base64Encoded: assertionBase64),
              let assertionClientData = try? JSONDecoder().decode(GenerationAssertionClientData.self, from: clientData),
              assertionClientData.challengeID == challengeID,
              (try? assertionClientData.canonicalData()) == clientData,
              assertionClientData.method == "POST",
              assertionClientData.path == "/v1/generate",
              assertionClientData.idempotencyKey == idempotencyKey,
              assertionClientData.requestBodySHA256 == Self.base64URL(Data(SHA256.hash(data: request.body))) else {
            return response(status: 401, error: "unauthorized")
        }
        let assertionChallenge: StoredEnrollmentChallenge
        let credential: StoredAppAttestCredential
        do {
            guard let challenge = try await store.enrollmentChallenge(id: challengeID, now: clock.now()),
                  let challengeData = Data(base64Encoded: assertionClientData.challenge),
                  challengeData == challenge.challenge,
                  let storedCredential = try await store.appAttestCredential(for: installationID),
                  storedCredential.appIdentifier == configuration.expectedAppIdentifier,
                  storedCredential.environment == configuration.appAttestEnvironment else {
                return response(status: 401, error: "unauthorized")
            }
            assertionChallenge = challenge
            credential = storedCredential
        } catch {
            return response(status: 503, error: "service_unavailable")
        }

        let verifiedAssertion: VerifiedAppAttestAssertion
        do {
            verifiedAssertion = try await attestationVerifier.verifyAssertion(
                object: assertionObject,
                clientData: clientData,
                credential: credential,
                expectedAppIdentifier: configuration.expectedAppIdentifier,
                expectedEnvironment: configuration.appAttestEnvironment
            )
        } catch {
            return response(status: 401, error: "unauthorized")
        }
        guard verifiedAssertion.counter > credential.assertionCounter else {
            return response(status: 401, error: "unauthorized")
        }
        do {
            let consumed = try await store.consumeAppAttestAssertion(
                challengeID: assertionChallenge.id,
                installationID: installationID,
                expectedCounter: credential.assertionCounter,
                newCounter: verifiedAssertion.counter,
                now: clock.now()
            )
            guard consumed else { return response(status: 401, error: "unauthorized") }
        } catch {
            return response(status: 503, error: "service_unavailable")
        }

        let fingerprint: Data
        do {
            let canonicalRequest = CanonicalGenerationRequest(
                intentVersion: body.intentVersion,
                profileID: body.profileID,
                prompt: body.prompt
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            fingerprint = Data(SHA256.hash(data: try encoder.encode(canonicalRequest)))
        } catch {
            return response(status: 503, error: "service_unavailable")
        }

        let now = clock.now()
        let reservation: GenerationReservation
        do {
            reservation = try await store.reserveGeneration(
                installationID: installationID,
                idempotencyKey: idempotencyKey,
                requestFingerprint: fingerprint,
                now: now,
                quota: configuration.generationQuota
            )
        } catch {
            return response(status: 503, error: "service_unavailable")
        }
        switch reservation {
        case .replay(let data):
            return GenerationServiceResponse(statusCode: 200, headers: Self.jsonHeaders, body: data)
        case .inProgress:
            return response(status: 409, error: "generation_in_progress", headers: ["Retry-After": "1"])
        case .idempotencyConflict:
            return response(status: 409, error: "idempotency_conflict")
        case .limited(let window):
            return response(
                status: 429,
                error: "quota_exceeded",
                headers: ["Retry-After": String(window.retryAfter)]
            )
        case .reserved(let reservationID):
            do {
                let intent = try await intentProvider.generateIntent(prompt: body.prompt)
                _ = try OpenAIResponsesClient.assembleProject(
                    from: intent,
                    prompt: body.prompt,
                    identityGenerator: { .generate() }
                )
                let intentData = Data(intent.utf8)
                let completed = try await store.completeGeneration(
                    installationID: installationID,
                    idempotencyKey: idempotencyKey,
                    reservationID: reservationID,
                    response: intentData,
                    now: clock.now()
                )
                guard completed else {
                    return response(status: 409, error: "generation_in_progress", headers: ["Retry-After": "1"])
                }
                return GenerationServiceResponse(statusCode: 200, headers: Self.jsonHeaders, body: intentData)
            } catch {
                do {
                    let markedRetryable = try await store.markGenerationRetryable(
                        installationID: installationID,
                        idempotencyKey: idempotencyKey,
                        reservationID: reservationID,
                        now: clock.now()
                    )
                    guard markedRetryable else {
                        return response(status: 409, error: "generation_in_progress", headers: ["Retry-After": "1"])
                    }
                } catch {
                    return response(status: 503, error: "service_unavailable")
                }
                return response(status: 503, error: "service_unavailable")
            }
        }
    }

    private func bearerToken(from authorization: String?) -> String? {
        guard let authorization,
              authorization.count > 7,
              authorization.prefix(7).caseInsensitiveCompare("Bearer ") == .orderedSame else { return nil }
        let token = String(authorization.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        return Data(base64URL: token)?.count == 32 ? token : nil
    }

    private func response(
        status: Int,
        error: String,
        headers: [String: String] = [:]
    ) -> GenerationServiceResponse {
        GenerationServiceResponse(
            statusCode: status,
            headers: Self.jsonHeaders.merging(headers) { _, newValue in newValue },
            body: (try? JSONEncoder().encode(ErrorResponse(error: error))) ?? Data("{}".utf8)
        )
    }

    private func response<Payload: Encodable>(status: Int, payload: Payload) -> GenerationServiceResponse {
        GenerationServiceResponse(
            statusCode: status,
            headers: Self.jsonHeaders,
            body: (try? JSONEncoder().encode(payload)) ?? Data("{}".utf8)
        )
    }

    private static let jsonHeaders = ["Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store"]

    private static func isValidIdempotencyKey(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && value.utf8.allSatisfy { (33...126).contains($0) }
    }

    private static func secureRandomBytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private struct EnrollmentRequest: Decodable {
    let challengeID: String
    let keyID: String
    let attestationObject: String
}

private struct EnrollmentChallengeResponse: Encodable {
    let challengeID: String
    let challenge: String
    let expiresAt: String
}

private struct EnrollmentResponse: Encodable {
    let sessionToken: String
}

private struct ErrorResponse: Encodable {
    let error: String
}

private struct GenerationRequest: Decodable {
    let intentVersion: Int
    let profileID: String
    let prompt: String
}

private struct CanonicalGenerationRequest: Encodable {
    let intentVersion: Int
    let profileID: String
    let prompt: String
}

private extension Data {
    init?(base64URL value: String) {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let paddingCount = (4 - base64.count % 4) % 4
        base64.append(String(repeating: "=", count: paddingCount))
        self.init(base64Encoded: base64)
    }
}

private struct MemoryChallenge: Sendable {
    let challenge: StoredEnrollmentChallenge
}

private struct MemoryInstallation: Sendable {
    let registration: GenerationInstallationRegistration
}

private struct GenerationIdempotencyScope: Hashable, Sendable {
    let installationID: UUID
    let key: String
}

private enum MemoryIdempotencyState: Sendable {
    case processing(updatedAt: Date, reservationID: UUID)
    case retryable(updatedAt: Date)
    case completed(response: Data, updatedAt: Date)
}

private struct MemoryIdempotencyRecord: Sendable {
    let fingerprint: Data
    var state: MemoryIdempotencyState
}

/// Deterministic in-memory adapter for tests and local development only.
public actor InMemoryGenerationServiceStore: GenerationServiceStore {
    private var challenges: [String: MemoryChallenge] = [:]
    private var installationsByTokenDigest: [Data: UUID] = [:]
    private var installations: [UUID: MemoryInstallation] = [:]
    private var assertionCounters: [UUID: UInt32] = [:]
    private var eventsByInstallation: [UUID: [Date]] = [:]
    private var idempotency: [GenerationIdempotencyScope: MemoryIdempotencyRecord] = [:]

    public init() {}

    public func createEnrollmentChallenge(_ challenge: StoredEnrollmentChallenge, now: Date) async throws {
        challenges = challenges.filter { $0.value.challenge.expiresAt > now }
        challenges[challenge.id] = MemoryChallenge(challenge: challenge)
    }

    public func enrollmentChallenge(id: String, now: Date) async throws -> StoredEnrollmentChallenge? {
        guard let challenge = challenges[id]?.challenge, challenge.expiresAt > now else { return nil }
        return challenge
    }

    public func registerInstallation(
        challengeID: String,
        registration: GenerationInstallationRegistration,
        tokenDigest: Data,
        now: Date
    ) async throws -> Bool {
        guard let challenge = challenges[challengeID]?.challenge,
              challenge.expiresAt > now,
              !installations.values.contains(where: { $0.registration.keyID == registration.keyID }),
              installationsByTokenDigest[tokenDigest] == nil else { return false }
        challenges.removeValue(forKey: challengeID)
        installations[registration.installationID] = MemoryInstallation(registration: registration)
        assertionCounters[registration.installationID] = 0
        installationsByTokenDigest[tokenDigest] = registration.installationID
        return true
    }

    public func installationID(forTokenDigest digest: Data) async throws -> UUID? {
        installationsByTokenDigest[digest]
    }

    public func appAttestCredential(for installationID: UUID) async throws -> StoredAppAttestCredential? {
        guard let registration = installations[installationID]?.registration else { return nil }
        return StoredAppAttestCredential(
            installationID: installationID,
            keyID: registration.keyID,
            publicKey: registration.publicKey,
            appIdentifier: registration.appIdentifier,
            environment: registration.environment,
            bundleVersion: registration.bundleVersion,
            assertionCounter: assertionCounters[installationID, default: 0]
        )
    }

    public func appAttestReceipt(for installationID: UUID) async throws -> Data? {
        installations[installationID]?.registration.receipt
    }

    public func consumeAppAttestAssertion(
        challengeID: String,
        installationID: UUID,
        expectedCounter: UInt32,
        newCounter: UInt32,
        now: Date
    ) async throws -> Bool {
        guard let challenge = challenges[challengeID]?.challenge,
              challenge.expiresAt > now,
              installations[installationID] != nil,
              assertionCounters[installationID, default: 0] >= expectedCounter,
              newCounter > assertionCounters[installationID, default: 0] else { return false }
        challenges.removeValue(forKey: challengeID)
        assertionCounters[installationID] = newCounter
        return true
    }

    public func reserveGeneration(
        installationID: UUID,
        idempotencyKey: String,
        requestFingerprint: Data,
        now: Date,
        quota: GenerationQuotaPolicy
    ) async throws -> GenerationReservation {
        guard installations[installationID] != nil else { return .idempotencyConflict }
        let scope = GenerationIdempotencyScope(installationID: installationID, key: idempotencyKey)
        var events = (eventsByInstallation[installationID] ?? []).filter { now.timeIntervalSince($0) < 86_400 }
        eventsByInstallation[installationID] = events
        if var existing = idempotency[scope] {
            guard existing.fingerprint == requestFingerprint else { return .idempotencyConflict }
            switch existing.state {
            case .completed(let response, _):
                return .replay(response)
            case .processing:
                return .inProgress
            case .retryable:
                if let limit = quotaWindow(for: events, now: now, quota: quota) { return .limited(limit) }
                events.append(now)
                eventsByInstallation[installationID] = events
                let reservationID = UUID()
                existing.state = .processing(updatedAt: now, reservationID: reservationID)
                idempotency[scope] = existing
                return .reserved(reservationID)
            }
        }

        if let limit = quotaWindow(for: events, now: now, quota: quota) { return .limited(limit) }

        eventsByInstallation[installationID, default: []].append(now)
        let reservationID = UUID()
        idempotency[scope] = MemoryIdempotencyRecord(
            fingerprint: requestFingerprint,
            state: .processing(updatedAt: now, reservationID: reservationID)
        )
        return .reserved(reservationID)
    }

    private func quotaWindow(
        for events: [Date],
        now: Date,
        quota: GenerationQuotaPolicy
    ) -> GenerationQuotaWindow? {
        if events.filter({ now.timeIntervalSince($0) < 60 }).count >= quota.perMinute { return .minute }
        if events.filter({ now.timeIntervalSince($0) < 3_600 }).count >= quota.perHour { return .hour }
        if events.count >= quota.perDay { return .day }
        return nil
    }

    public func completeGeneration(
        installationID: UUID,
        idempotencyKey: String,
        reservationID: UUID,
        response: Data,
        now: Date
    ) async throws -> Bool {
        let scope = GenerationIdempotencyScope(installationID: installationID, key: idempotencyKey)
        guard var record = idempotency[scope] else { throw StoreError.missingReservation }
        guard case .processing(_, let currentReservationID) = record.state,
              currentReservationID == reservationID else { return false }
        record.state = .completed(response: response, updatedAt: now)
        idempotency[scope] = record
        return true
    }

    public func markGenerationRetryable(
        installationID: UUID,
        idempotencyKey: String,
        reservationID: UUID,
        now: Date
    ) async throws -> Bool {
        let scope = GenerationIdempotencyScope(installationID: installationID, key: idempotencyKey)
        guard var record = idempotency[scope] else { throw StoreError.missingReservation }
        guard case .processing(_, let currentReservationID) = record.state,
              currentReservationID == reservationID else { return false }
        record.state = .retryable(updatedAt: now)
        idempotency[scope] = record
        return true
    }

    private enum StoreError: Error {
        case missingReservation
    }
}
