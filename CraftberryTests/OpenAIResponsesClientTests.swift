import Foundation
import CryptoKit
import XCTest
#if canImport(CraftberryCore)
@testable import CraftberryCore
#else
@testable import Craftberry
#endif

final class OpenAIResponsesClientTests: XCTestCase {
    func testBackendClientPostsVersionedIntentAndAssemblesReadyProjectLocally() async throws {
        let fixture = try generationFixture()
        let (status, body) = try fixtureScenario("ready", in: fixture)
        let fixtureRequest = try XCTUnwrap(fixture["request"] as? [String: Any])
        let prompt = try XCTUnwrap(fixtureRequest["prompt"] as? String)
        let recorder = RequestRecorder()
        URLProtocolStub.store.setHandler { request in
            _ = recorder.record(request)
            let response = try XCTUnwrap(
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: status, httpVersion: nil, headerFields: nil)
            )
            return (response, body)
        }
        defer { URLProtocolStub.store.setHandler(nil) }

        let identity = identity()
        let client = backendClient(identity: identity)
        let generation = try await client.generateProject(from: prompt)

        XCTAssertEqual(generation.outcome, .ready)
        XCTAssertEqual(generation.project?.displayName, "Harbor")
        XCTAssertEqual(generation.project?.id, identity.projectID)
        XCTAssertEqual(generation.project?.packUUIDs, identity.packUUIDs)
        let request = try XCTUnwrap(recorder.request(at: 0))
        XCTAssertEqual(request.url?.path, fixture["path"] as? String)
        XCTAssertEqual(request.httpMethod, fixture["method"] as? String)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer runtime-test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        let requestBody = try XCTUnwrap(recorder.body(at: 0))
        let encodedAssertionData = request.value(forHTTPHeaderField: "App-Attest-Client-Data")
        let assertionData = try XCTUnwrap(encodedAssertionData.flatMap { Data(base64Encoded: $0) })
        let assertionClientData = try JSONDecoder().decode(GenerationAssertionClientData.self, from: assertionData)
        XCTAssertEqual(assertionClientData.requestBodySHA256, Self.base64URL(Data(SHA256.hash(data: requestBody))))
        XCTAssertEqual(request.value(forHTTPHeaderField: "App-Attest-Challenge-ID"), assertionClientData.challengeID)
        XCTAssertNotNil(request.value(forHTTPHeaderField: "App-Attest-Assertion"))
        let decodedRequest = try XCTUnwrap(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
        XCTAssertEqual(decodedRequest["intentVersion"] as? Int, fixtureRequest["intentVersion"] as? Int)
        XCTAssertEqual(decodedRequest["profileID"] as? String, fixtureRequest["profileID"] as? String)
        XCTAssertEqual(decodedRequest["prompt"] as? String, fixtureRequest["prompt"] as? String)
    }

    func testBackendClientReturnsUnsupportedFixtureWithoutProject() async throws {
        let (status, body) = try fixtureScenario("unsupported", in: generationFixture())
        URLProtocolStub.store.setHandler { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: status, httpVersion: nil, headerFields: nil)
            )
            return (response, body)
        }
        defer { URLProtocolStub.store.setHandler(nil) }

        let generation = try await backendClient().generateProject(from: "Build something outside the profile")

        XCTAssertEqual(generation.outcome, .unsupported)
        XCTAssertNil(generation.project)
        XCTAssertEqual(generation.message, "This add-on needs a feature outside the active profile.")
    }

    func testEnrollmentChallengeTransportPreservesCancellation() async throws {
        URLProtocolStub.store.setHandler { _ in throw URLError(.cancelled) }
        defer { URLProtocolStub.store.setHandler(nil) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let transport = URLSessionGenerationEnrollmentTransport(
            baseURL: URL(string: "https://generation.test"),
            session: URLSession(configuration: configuration)
        )

        do {
            _ = try await transport.requestChallenge()
            XCTFail("The cancelled request should stop enrollment immediately.")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cancelled)
        } catch is CancellationError {
            // CancellationError is also preserved when supplied directly by URLSession.
        }
    }

    func testBackendClientMapsUnauthorizedFixture() async throws {
        try await assertBackendFailure(scenario: "unauthorized", expected: .unauthorized)
    }

    func testBackendClientMapsQuotaFixture() async throws {
        try await assertBackendFailure(scenario: "quota", expected: .quotaExceeded)
    }

    func testBackendClientMapsServiceFailureFixture() async throws {
        try await assertBackendFailure(scenario: "serviceFailure", expected: .serviceUnavailable)
    }

    func testBackendClientRetriesServiceFailureWithSameIdempotencyKey() async throws {
        let fixture = try generationFixture()
        let (status, body) = try fixtureScenario("ready", in: fixture)
        let recorder = RequestRecorder()
        URLProtocolStub.store.setHandler { request in
            let requestNumber = recorder.record(request)
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: requestNumber == 1 ? 503 : status,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return (response, requestNumber == 1 ? Data("{}".utf8) : body)
        }
        defer { URLProtocolStub.store.setHandler(nil) }

        let client = backendClient()
        let generation = try await client.generateProject(from: "Craft a cyan diamond sword named Harbor.")

        XCTAssertEqual(generation.outcome, .ready)
        XCTAssertEqual(recorder.count, 2)
        XCTAssertEqual(
            recorder.request(at: 0)?.value(forHTTPHeaderField: "Idempotency-Key"),
            recorder.request(at: 1)?.value(forHTTPHeaderField: "Idempotency-Key")
        )
        XCTAssertNotEqual(
            recorder.request(at: 0)?.value(forHTTPHeaderField: "App-Attest-Challenge-ID"),
            recorder.request(at: 1)?.value(forHTTPHeaderField: "App-Attest-Challenge-ID")
        )
    }

    func testBackendClientPollsGenerationInProgressWithSameKeyAndFreshAssertion() async throws {
        let fixture = try generationFixture()
        let (status, body) = try fixtureScenario("ready", in: fixture)
        let recorder = RequestRecorder()
        URLProtocolStub.store.setHandler { request in
            let requestNumber = recorder.record(request)
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: requestNumber == 1 ? 409 : status,
                httpVersion: nil,
                headerFields: requestNumber == 1 ? ["Retry-After": "0"] : nil
            ))
            return (response, requestNumber == 1 ? Data(#"{"error":"generation_in_progress"}"#.utf8) : body)
        }
        defer { URLProtocolStub.store.setHandler(nil) }

        let generation = try await backendClient().generateProject(from: "Craft a cyan sword named Harbor.")

        XCTAssertEqual(generation.outcome, .ready)
        XCTAssertEqual(recorder.count, 2)
        XCTAssertEqual(
            recorder.request(at: 0)?.value(forHTTPHeaderField: "Idempotency-Key"),
            recorder.request(at: 1)?.value(forHTTPHeaderField: "Idempotency-Key")
        )
        XCTAssertNotEqual(
            recorder.request(at: 0)?.value(forHTTPHeaderField: "App-Attest-Challenge-ID"),
            recorder.request(at: 1)?.value(forHTTPHeaderField: "App-Attest-Challenge-ID")
        )
        XCTAssertEqual(recorder.body(at: 0), recorder.body(at: 1))
    }

    func testBackendClientRetriesTransientChallengeFailureAndCompletesOperation() async throws {
        let fixture = try generationFixture()
        let (status, body) = try fixtureScenario("ready", in: fixture)
        let recorder = RequestRecorder()
        URLProtocolStub.store.setHandler { request in
            _ = recorder.record(request)
            return (try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )), body)
        }
        defer { URLProtocolStub.store.setHandler(nil) }

        let transportState = FlakyChallengeTransportState()
        let store = SessionCredentialStoreSpy(token: "existing-session", keyID: "existing-app-attest-key")
        let attestState = AppAttestStateSpy()
        let provider = KeychainGenerationCredentialProvider(
            baseURL: URL(string: "https://generation.test"),
            credentialStore: store,
            appAttestService: AppAttestServiceSpy(state: attestState),
            enrollmentTransport: FlakyChallengeEnrollmentTransport(state: transportState)
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let client = BackendGenerationClient(
            baseURL: URL(string: "https://generation.test"),
            credentialProvider: provider,
            session: URLSession(configuration: configuration)
        )

        let generation = try await client.generateProject(from: "A cyan sword after a temporary challenge failure.")

        XCTAssertEqual(generation.outcome, .ready)
        XCTAssertEqual(recorder.count, 1)
        let transportCounts = await transportState.counts()
        XCTAssertEqual(transportCounts, 2)
        let attestationCounts = await attestState.counts()
        XCTAssertEqual(attestationCounts.assertions, 1)
    }

    func testBackendClientRetriesOutOfOrderAssertionWithSameOperationKey() async throws {
        let fixture = try generationFixture()
        let (status, body) = try fixtureScenario("ready", in: fixture)
        let recorder = RequestRecorder()
        URLProtocolStub.store.setHandler { request in
            let requestNumber = recorder.record(request)
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: requestNumber == 1 ? 409 : status,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, requestNumber == 1 ? Data(#"{"error":"assertion_counter_out_of_order"}"#.utf8) : body)
        }
        defer { URLProtocolStub.store.setHandler(nil) }

        let generation = try await backendClient().generateProject(from: "Recover the cyan sword assertion order.")

        XCTAssertEqual(generation.outcome, .ready)
        XCTAssertEqual(recorder.count, 2)
        XCTAssertEqual(
            recorder.request(at: 0)?.value(forHTTPHeaderField: "Idempotency-Key"),
            recorder.request(at: 1)?.value(forHTTPHeaderField: "Idempotency-Key")
        )
        XCTAssertNotEqual(
            recorder.request(at: 0)?.value(forHTTPHeaderField: "App-Attest-Challenge-ID"),
            recorder.request(at: 1)?.value(forHTTPHeaderField: "App-Attest-Challenge-ID")
        )
    }

    func testBackendClientCanResumeAnInProgressOperationAfterPollingBudgetExpires() async throws {
        let fixture = try generationFixture()
        let (status, body) = try fixtureScenario("ready", in: fixture)
        let recorder = RequestRecorder()
        URLProtocolStub.store.setHandler { request in
            let requestNumber = recorder.record(request)
            let stillWorking = requestNumber <= 4
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: stillWorking ? 409 : status,
                httpVersion: nil,
                headerFields: stillWorking ? ["Retry-After": "0"] : nil
            ))
            return (response, stillWorking ? Data(#"{"error":"generation_in_progress"}"#.utf8) : body)
        }
        defer { URLProtocolStub.store.setHandler(nil) }
        let client = backendClient()

        do {
            _ = try await client.generateProject(from: "Resume the cyan sword request.")
            XCTFail("The initial bounded polling window should expire.")
        } catch let error as BackendGenerationClientError {
            XCTAssertEqual(error, .generationInProgress)
        }

        let generation = try await client.generateProject(from: "Resume the cyan sword request.")

        XCTAssertEqual(generation.outcome, .ready)
        XCTAssertEqual(recorder.count, 5)
        XCTAssertEqual(
            recorder.request(at: 0)?.value(forHTTPHeaderField: "Idempotency-Key"),
            recorder.request(at: 4)?.value(forHTTPHeaderField: "Idempotency-Key")
        )
        XCTAssertEqual(recorder.body(at: 0), recorder.body(at: 4))
    }

    func testBackendClientReenrollsAfterAppAttestKeyIsInvalidated() async throws {
        let fixture = try generationFixture()
        let (status, body) = try fixtureScenario("ready", in: fixture)
        let recorder = RequestRecorder()
        URLProtocolStub.store.setHandler { request in
            _ = recorder.record(request)
            return (try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )), body)
        }
        defer { URLProtocolStub.store.setHandler(nil) }

        let store = SessionCredentialStoreSpy(token: "stale-session", keyID: "restored-key-without-secure-enclave-key")
        let transportState = EnrollmentTransportStateSpy(challenge: Data("recovery-challenge".utf8))
        let provider = KeychainGenerationCredentialProvider(
            baseURL: URL(string: "https://generation.test"),
            credentialStore: store,
            appAttestService: InvalidOnceAppAttestService(),
            enrollmentTransport: EnrollmentTransportSpy(state: transportState)
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let client = BackendGenerationClient(
            baseURL: URL(string: "https://generation.test"),
            credentialProvider: provider,
            session: URLSession(configuration: configuration)
        )

        let generation = try await client.generateProject(from: "Craft a cyan sword named Harbor.")

        XCTAssertEqual(generation.outcome, .ready)
        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(recorder.request(at: 0)?.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-session-token")
        let enrollmentCounts = await transportState.counts()
        XCTAssertEqual(enrollmentCounts.enroll, 1)
        let storedValues = await store.values()
        XCTAssertEqual(storedValues.keyID, "recovered-app-attest-key")
        XCTAssertEqual(storedValues.token, "fixture-session-token")
    }

    func testBackendClientReenrollsOnlyForExplicitUnknownSessionAndKeepsOperationKey() async throws {
        let fixture = try generationFixture()
        let (status, body) = try fixtureScenario("ready", in: fixture)
        let recorder = RequestRecorder()
        URLProtocolStub.store.setHandler { request in
            let requestNumber = recorder.record(request)
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: requestNumber == 1 ? 401 : status,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, requestNumber == 1 ? Data(#"{"error":"unknown_session"}"#.utf8) : body)
        }
        defer { URLProtocolStub.store.setHandler(nil) }
        let store = SessionCredentialStoreSpy(token: "expired-session", keyID: "old-app-attest-key")
        let transportState = EnrollmentTransportStateSpy(challenge: Data("replacement-session-challenge".utf8))
        let provider = KeychainGenerationCredentialProvider(
            baseURL: URL(string: "https://generation.test"),
            credentialStore: store,
            appAttestService: AppAttestServiceSpy(state: AppAttestStateSpy()),
            enrollmentTransport: EnrollmentTransportSpy(state: transportState)
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let client = BackendGenerationClient(
            baseURL: URL(string: "https://generation.test"),
            credentialProvider: provider,
            session: URLSession(configuration: configuration)
        )

        let generation = try await client.generateProject(from: "Recover this cyan sword generation.")

        XCTAssertEqual(generation.outcome, .ready)
        XCTAssertEqual(recorder.count, 2)
        XCTAssertEqual(recorder.request(at: 0)?.value(forHTTPHeaderField: "Authorization"), "Bearer expired-session")
        XCTAssertEqual(recorder.request(at: 1)?.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-session-token")
        XCTAssertEqual(
            recorder.request(at: 0)?.value(forHTTPHeaderField: "Idempotency-Key"),
            recorder.request(at: 1)?.value(forHTTPHeaderField: "Idempotency-Key")
        )
    }

    func testLateInvalidKeyDoesNotClearAReplacementSession() async throws {
        let store = SessionCredentialStoreSpy(token: "old-session", keyID: "old-key")
        let state = LateInvalidKeyAppAttestState()
        let provider = KeychainGenerationCredentialProvider(
            baseURL: URL(string: "https://generation.test"),
            credentialStore: store,
            appAttestService: LateInvalidKeyAppAttestService(state: state),
            enrollmentTransport: EnrollmentTransportSpy(
                state: EnrollmentTransportStateSpy(challenge: Data("recovery-challenge".utf8))
            )
        )
        let body = Data(#"{"intentVersion":1,"profileID":"bedrock-stable-1.26.30","prompt":"Build a sword"}"#.utf8)

        let lateAssertion = Task {
            try await provider.assertionHeaders(for: body, idempotencyKey: "late-request")
        }
        defer { Task { await state.releaseFirstAssertion() } }
        guard await state.waitForFirstAssertion(timeoutNanoseconds: 2_000_000_000) else {
            XCTFail("The first assertion did not reach the blocked point within two seconds.")
            await state.releaseFirstAssertion()
            _ = await lateAssertion.result
            return
        }

        do {
            _ = try await provider.assertionHeaders(for: body, idempotencyKey: "reset-request")
            XCTFail("The invalid stored key should trigger session recovery.")
        } catch let error as BackendGenerationClientError {
            XCTAssertEqual(error, .appAttestKeyInvalid)
        }

        let replacementToken = try await provider.bearerToken()
        XCTAssertEqual(replacementToken, "fixture-session-token")
        await state.releaseFirstAssertion()
        do {
            _ = try await lateAssertion.value
            XCTFail("The late assertion still used the invalid key.")
        } catch let error as BackendGenerationClientError {
            XCTAssertEqual(error, .appAttestKeyInvalid)
        }

        let storedValues = await store.values()
        XCTAssertEqual(storedValues.keyID, "replacement-app-attest-key")
        XCTAssertEqual(storedValues.token, "fixture-session-token")
    }

    func testFailedCredentialResetTaskCanRecoverOnTheNextEnrollmentAttempt() async throws {
        let store = FlakySessionCredentialStore(
            token: "stale-session",
            keyID: "invalid-key",
            clearFailuresRemaining: 1
        )
        let transportState = EnrollmentTransportStateSpy(challenge: Data("recovery-challenge".utf8))
        let provider = KeychainGenerationCredentialProvider(
            baseURL: URL(string: "https://generation.test"),
            credentialStore: store,
            appAttestService: InvalidOnceAppAttestService(),
            enrollmentTransport: EnrollmentTransportSpy(state: transportState)
        )
        let body = Data(#"{"intentVersion":1,"profileID":"bedrock-stable-1.26.30","prompt":"Build a sword"}"#.utf8)

        do {
            _ = try await provider.assertionHeaders(for: body, idempotencyKey: "reset-failure")
            XCTFail("The first key reset should surface its storage failure.")
        } catch SessionCredentialStoreTestError.clearFailed {
            // Assert that the injected Keychain failure, rather than App Attest, was returned.
        } catch {
            XCTFail("Expected the injected clearFailed storage error, got \(error).")
        }

        let recoveredToken = try await provider.bearerToken()
        XCTAssertEqual(recoveredToken, "fixture-session-token")
        let counts = await transportState.counts()
        XCTAssertEqual(counts.enroll, 1)
        let storedValues = await store.values()
        XCTAssertEqual(storedValues.keyID, "recovered-app-attest-key")
        XCTAssertEqual(storedValues.token, "fixture-session-token")
    }

    func testBackendClientRejectsUnconfiguredOrNonHTTPSEndpointBeforeFetchingCredential() async throws {
        let provider = CredentialProviderSpy(token: "runtime-test-token")
        let unconfigured = BackendGenerationClient(baseURL: nil, credentialProvider: provider)
        do {
            _ = try await unconfigured.generateProject(from: "prompt")
            XCTFail("Expected an unconfigured endpoint to fail")
        } catch let error as BackendGenerationClientError {
            XCTAssertEqual(error, .endpointNotConfigured)
        }
        let requestsAfterMissingURL = await provider.requestCount()
        XCTAssertEqual(requestsAfterMissingURL, 0)

        let insecure = BackendGenerationClient(baseURL: URL(string: "http://generation.test"), credentialProvider: provider)
        do {
            _ = try await insecure.generateProject(from: "prompt")
            XCTFail("Expected a non-HTTPS endpoint to fail")
        } catch let error as BackendGenerationClientError {
            XCTAssertEqual(error, .invalidEndpoint)
        }
        let requestsAfterInsecureURL = await provider.requestCount()
        XCTAssertEqual(requestsAfterInsecureURL, 0)
    }

    func testKeychainCredentialProviderEnrollsAndPersistsAppAttestSessionOnceForConcurrentCalls() async throws {
        let challenge = Data("fixture-server-challenge".utf8)
        let store = SessionCredentialStoreSpy()
        let attestState = AppAttestStateSpy()
        let transportState = EnrollmentTransportStateSpy(challenge: challenge)
        let provider = KeychainGenerationCredentialProvider(
            baseURL: URL(string: "https://generation.test"),
            credentialStore: store,
            appAttestService: AppAttestServiceSpy(state: attestState),
            enrollmentTransport: EnrollmentTransportSpy(state: transportState)
        )

        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<8 { group.addTask { try await provider.bearerToken() } }
            var values: [String] = []
            for try await token in group { values.append(token) }
            return values
        }

        XCTAssertEqual(Set(tokens), ["fixture-session-token"])
        let enrollmentCounts = await transportState.counts()
        XCTAssertEqual(enrollmentCounts.challenge, 1)
        XCTAssertEqual(enrollmentCounts.enroll, 1)
        let attestCounts = await attestState.counts()
        XCTAssertEqual(attestCounts.generated, 1)
        XCTAssertEqual(attestCounts.attested, 1)
        XCTAssertEqual(attestCounts.lastClientDataHash, Data(SHA256.hash(data: challenge + Data([1]))))
        let storedValues = await store.values()
        XCTAssertEqual(storedValues.keyID, "fixture-app-attest-key-id")
        XCTAssertEqual(storedValues.token, "fixture-session-token")
    }

    func testAttestationServiceUnavailableRetriesWithTheSameKeyAndClientDataHash() async throws {
        let store = SessionCredentialStoreSpy()
        let attestState = RetryableAttestationState()
        let transportState = EnrollmentTransportStateSpy(challenge: Data("retryable-attestation-challenge".utf8))
        let provider = KeychainGenerationCredentialProvider(
            baseURL: URL(string: "https://generation.test"),
            credentialStore: store,
            appAttestService: RetryableAttestationService(state: attestState),
            enrollmentTransport: EnrollmentTransportSpy(state: transportState)
        )

        do {
            _ = try await provider.bearerToken()
            XCTFail("The first Apple service attempt should be temporarily unavailable.")
        } catch let error as BackendGenerationClientError {
            XCTAssertEqual(error, .serviceUnavailable)
        }

        let recoveredToken = try await provider.bearerToken()
        XCTAssertEqual(recoveredToken, "fixture-session-token")
        let attestCounts = await attestState.values()
        XCTAssertEqual(attestCounts.keyIDs, ["retry-app-attest-key-1", "retry-app-attest-key-1"])
        XCTAssertEqual(attestCounts.clientDataHashes.count, 2)
        XCTAssertEqual(attestCounts.clientDataHashes[0], attestCounts.clientDataHashes[1])
        let transportCounts = await transportState.counts()
        XCTAssertEqual(transportCounts.challenge, 1)
        XCTAssertEqual(transportCounts.enroll, 1)
    }

    func testKeychainCredentialProviderReenrollsWhenStoredBearerHasNoAppAttestKey() async throws {
        let store = SessionCredentialStoreSpy(token: "existing-session")
        let attestState = AppAttestStateSpy()
        let transportState = EnrollmentTransportStateSpy(challenge: Data("replacement-challenge".utf8))
        let provider = KeychainGenerationCredentialProvider(
            baseURL: URL(string: "https://generation.test"),
            credentialStore: store,
            appAttestService: AppAttestServiceSpy(state: attestState),
            enrollmentTransport: EnrollmentTransportSpy(state: transportState)
        )

        let token = try await provider.bearerToken()
        XCTAssertEqual(token, "fixture-session-token")
        let enrollmentCounts = await transportState.counts()
        let attestCounts = await attestState.counts()
        XCTAssertEqual(enrollmentCounts.challenge, 1)
        XCTAssertEqual(enrollmentCounts.enroll, 1)
        XCTAssertEqual(attestCounts.generated, 1)
        XCTAssertEqual(attestCounts.attested, 1)
        let storedValues = await store.values()
        XCTAssertEqual(storedValues.keyID, "fixture-app-attest-key-id")
        XCTAssertEqual(storedValues.token, "fixture-session-token")
    }

    func testKeychainCredentialProviderSignsEachGenerationRequestWithFreshChallenge() async throws {
        let store = SessionCredentialStoreSpy(token: "existing-session", keyID: "existing-app-attest-key")
        let attestState = AppAttestStateSpy()
        let transportState = EnrollmentTransportStateSpy(challenge: Data("server-challenge-123456".utf8))
        let provider = KeychainGenerationCredentialProvider(
            baseURL: URL(string: "https://generation.test"),
            credentialStore: store,
            appAttestService: AppAttestServiceSpy(state: attestState),
            enrollmentTransport: EnrollmentTransportSpy(state: transportState)
        )
        let body = Data(#"{"intentVersion":1,"profileID":"bedrock-stable-1.26.30","prompt":"Build a sword"}"#.utf8)

        let first = try await provider.assertionHeaders(for: body, idempotencyKey: "operation-1")
        let second = try await provider.assertionHeaders(for: body, idempotencyKey: "operation-1")

        XCTAssertNotEqual(first.challengeID, second.challengeID)
        let counts = await transportState.counts()
        XCTAssertEqual(counts.challenge, 2)
        let attestCounts = await attestState.counts()
        XCTAssertEqual(attestCounts.assertions, 2)
        XCTAssertNotEqual(attestCounts.assertionHashes.first, nil)
        XCTAssertEqual(attestCounts.assertionHashes.count, 2)
    }

    func testClientAssemblesHostileEntitySetFromStructuredIntent() async throws {
        let structuredText = """
        {"schemaVersion":1,"outcome":"ready","message":"Ready to build.","shortDescription":"A hostile creature pack.","materialHostileEntitySet":{"materialName":"Azure","color":"red","sourceItem":"diamond","sourceCount":4,"health":24}}
        """
        let responseData = try JSONSerialization.data(withJSONObject: ["output": [["content": [["type": "output_text", "text": structuredText]]]]])
        URLProtocolStub.store.setHandler { request in
            (try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)), responseData)
        }
        defer { URLProtocolStub.store.setHandler(nil) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let stableIdentity = identity()
        let client = OpenAIResponsesClient(apiKey: "test-key", session: URLSession(configuration: configuration), identityGenerator: { stableIdentity })

        let generation = try await client.generateProject(from: "A hostile Azure creature that attacks players")

        XCTAssertEqual(generation.project?.entities.first?.archetype, .hostile)
        XCTAssertEqual(generation.project?.entities.first?.health, 24)
    }

    func testClientReturnsUnsupportedForMusicRecordIntentInStableProfile() async throws {
        let structuredText = """
        {"schemaVersion":1,"outcome":"ready","message":"Ready to build.","shortDescription":"A dreamy music record.","musicRecordSet":{"title":"First Light","color":"cyan","style":"dreamy"}}
        """
        let responseData = try JSONSerialization.data(withJSONObject: ["output": [["content": [["type": "output_text", "text": structuredText]]]]])
        URLProtocolStub.store.setHandler { request in
            (try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)), responseData)
        }
        defer { URLProtocolStub.store.setHandler(nil) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let identity = identity()
        let client = OpenAIResponsesClient(apiKey: "test-key", session: URLSession(configuration: configuration), identityGenerator: { identity })

        let generation = try await client.generateProject(from: "Make a dreamy cyan record called First Light")

        XCTAssertEqual(generation.outcome, .unsupported)
        XCTAssertTrue(generation.message.contains("Beta APIs experiment"))
        XCTAssertNil(generation.project)
    }

    func testClientAssemblesPassiveEntitySetFromStructuredIntent() async throws {
        let structuredText = """
        {"schemaVersion":1,"outcome":"ready","message":"Ready to build.","shortDescription":"A gentle passive creature.","materialPassiveEntitySet":{"materialName":"Azure","color":"blue","sourceItem":"diamond","sourceCount":4,"health":12}}
        """
        let responseData = try JSONSerialization.data(withJSONObject: ["output": [["content": [["type": "output_text", "text": structuredText]]]]])
        let recorder = RequestRecorder()
        URLProtocolStub.store.setHandler { request in
            _ = recorder.record(request)
            return (
                try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)),
                responseData
            )
        }
        defer { URLProtocolStub.store.setHandler(nil) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let stableIdentity = identity()
        let client = OpenAIResponsesClient(apiKey: "test-key", session: URLSession(configuration: configuration), identityGenerator: { stableIdentity })

        let generation = try await client.generateProject(from: "A gentle Azure animal that never attacks")

        XCTAssertEqual(generation.outcome, .ready)
        let project = try XCTUnwrap(generation.project)
        XCTAssertEqual(project.entities.first?.archetype, .passive)
        XCTAssertEqual(project.entities.first?.health, 12)
        XCTAssertEqual(project.spawnRules.count, 1)
        XCTAssertEqual(project.entityLootTables.first?.item, .vanilla("minecraft:feather"))

        let requestBody = try XCTUnwrap(recorder.body(at: 0))
        let requestDocument = try XCTUnwrap(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
        let textConfiguration = try XCTUnwrap(requestDocument["text"] as? [String: Any])
        let format = try XCTUnwrap(textConfiguration["format"] as? [String: Any])
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        XCTAssertTrue((try XCTUnwrap(schema["required"] as? [String])).contains("materialPassiveEntitySet"))
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let passiveIntent = try XCTUnwrap(properties["materialPassiveEntitySet"] as? [String: Any])
        let variants = try XCTUnwrap(passiveIntent["anyOf"] as? [[String: Any]])
        let objectSchema = try XCTUnwrap(variants.first { $0["type"] as? String == "object" })
        let healthSchema = try XCTUnwrap((objectSchema["properties"] as? [String: Any])?["health"] as? [String: Any])
        XCTAssertEqual(healthSchema["minimum"] as? Int, 4)
        XCTAssertEqual(healthSchema["maximum"] as? Int, 40)
    }

    func testClientRejectsPassiveIntentCombinedWithAnotherIntent() async throws {
        let structuredText = """
        {"schemaVersion":1,"outcome":"ready","message":"Ready to build.","shortDescription":"Two intents.","materialPassiveEntitySet":{"materialName":"Azure","color":"blue","sourceItem":"diamond","sourceCount":4,"health":12},"materialHostileEntitySet":{"materialName":"Azure","color":"blue","sourceItem":"diamond","sourceCount":4,"health":12}}
        """
        let responseData = try JSONSerialization.data(withJSONObject: ["output": [["content": [["type": "output_text", "text": structuredText]]]]])
        URLProtocolStub.store.setHandler { request in
            (try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)), responseData)
        }
        defer { URLProtocolStub.store.setHandler(nil) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let stableIdentity = identity()
        let client = OpenAIResponsesClient(apiKey: "test-key", session: URLSession(configuration: configuration), identityGenerator: { stableIdentity })

        do {
            _ = try await client.generateProject(from: "A passive and hostile creature")
            XCTFail("Expected invalidResponse")
        } catch {
            guard case LLMClientError.invalidResponse = error else { return XCTFail("Unexpected error \(error)") }
        }
    }

    func testClientAssemblesBossEntitySetFromStructuredIntent() async throws {
        let structuredText = """
        {"schemaVersion":1,"outcome":"ready","message":"Ready to build.","shortDescription":"A phased boss encounter.","materialBossEntitySet":{"materialName":"Azure","color":"red","sourceItem":"diamond","sourceCount":4,"health":40}}
        """
        let responseData = try JSONSerialization.data(withJSONObject: ["output": [["content": [["type": "output_text", "text": structuredText]]]]])
        let recorder = RequestRecorder()
        URLProtocolStub.store.setHandler { request in
            _ = recorder.record(request)
            return (
                try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)),
                responseData
            )
        }
        defer { URLProtocolStub.store.setHandler(nil) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let stableIdentity = identity()
        let client = OpenAIResponsesClient(apiKey: "test-key", session: URLSession(configuration: configuration), identityGenerator: { stableIdentity })

        let generation = try await client.generateProject(from: "A two-phase Azure boss that drops its ingot")

        let project = try XCTUnwrap(generation.project)
        XCTAssertEqual(project.entities.first?.archetype, .boss)
        XCTAssertEqual(project.entities.first?.health, 40)
        XCTAssertEqual(project.entityLootTables.first?.item, .generated(ContentID("azure_a1b2c3_ingot")))
        XCTAssertTrue(project.spawnRules.isEmpty)

        let requestBody = try XCTUnwrap(recorder.body(at: 0))
        let requestDocument = try XCTUnwrap(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
        let textConfiguration = try XCTUnwrap(requestDocument["text"] as? [String: Any])
        let format = try XCTUnwrap(textConfiguration["format"] as? [String: Any])
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let bossIntent = try XCTUnwrap(properties["materialBossEntitySet"] as? [String: Any])
        let variants = try XCTUnwrap(bossIntent["anyOf"] as? [[String: Any]])
        let objectSchema = try XCTUnwrap(variants.first { $0["type"] as? String == "object" })
        let required = try XCTUnwrap(objectSchema["required"] as? [String])
        XCTAssertTrue(required.contains("health"))
        let intentProperties = try XCTUnwrap(objectSchema["properties"] as? [String: Any])
        let healthSchema = try XCTUnwrap(intentProperties["health"] as? [String: Any])
        XCTAssertEqual(healthSchema["minimum"] as? Int, 20)
        XCTAssertEqual(healthSchema["maximum"] as? Int, 40)
    }

    func testClientAssemblesMaterialWeaponSetFromStructuredIntent() async throws {
        let structuredText = """
        {"schemaVersion":1,"outcome":"ready","message":"Ready to build.","shortDescription":"A compact custom pack overview.","sword":null,"materialSwordSet":null,"materialToolSet":null,"materialWeaponSet":{"materialName":"Azure","color":"blue","sourceItem":"diamond","sourceCount":4,"attackBonus":10,"durability":500}}
        """
        let responseData = try JSONSerialization.data(withJSONObject: ["output": [["content": [["type": "output_text", "text": structuredText]]]]])
        URLProtocolStub.store.setHandler { request in
            (try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)), responseData)
        }
        defer { URLProtocolStub.store.setHandler(nil) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let identity = identity()
        let client = OpenAIResponsesClient(apiKey: "test-key", session: URLSession(configuration: configuration), identityGenerator: { identity })

        let generation = try await client.generateProject(from: "An Azure ingot and matching weapon set")

        XCTAssertEqual(generation.project?.items.map(\.displayName), ["Azure Ingot", "Azure Sword", "Azure Dagger", "Azure Spear", "Azure Hammer"])
        XCTAssertEqual(generation.project?.recipes.count, 4)
    }

    func testClientAssemblesMaterialToolSetFromStructuredIntent() async throws {
        let structuredText = """
        {"schemaVersion":1,"outcome":"ready","message":"Ready to build.","shortDescription":"A compact custom pack overview.","sword":null,"materialSwordSet":null,"materialToolSet":{"materialName":"Azure","color":"blue","sourceItem":"diamond","sourceCount":4,"attackBonus":10,"durability":500},"materialWeaponSet":null}
        """
        let responseData = try JSONSerialization.data(withJSONObject: ["output": [["content": [["type": "output_text", "text": structuredText]]]]])
        URLProtocolStub.store.setHandler { request in
            (try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)), responseData)
        }
        defer { URLProtocolStub.store.setHandler(nil) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let identity = identity()
        let client = OpenAIResponsesClient(apiKey: "test-key", session: URLSession(configuration: configuration), identityGenerator: { identity })

        let generation = try await client.generateProject(from: "An Azure ingot and matching tool set")

        XCTAssertEqual(generation.project?.items.map(\.displayName), ["Azure Ingot", "Azure Sword", "Azure Pickaxe", "Azure Axe", "Azure Shovel", "Azure Hoe"])
        XCTAssertEqual(generation.project?.recipes.count, 5)
    }

    func testClientAssemblesMaterialArmorSetFromStructuredIntent() async throws {
        let structuredText = """
        {"schemaVersion":1,"outcome":"ready","message":"Ready to build.","shortDescription":"A compact custom pack overview.","sword":null,"materialSwordSet":null,"materialToolSet":null,"materialWeaponSet":null,"materialArmorSet":{"materialName":"Azure","color":"blue","sourceItem":"diamond","sourceCount":4,"protection":15,"durability":500}}
        """
        let responseData = try JSONSerialization.data(withJSONObject: ["output": [["content": [["type": "output_text", "text": structuredText]]]]])
        URLProtocolStub.store.setHandler { request in
            (try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)), responseData)
        }
        defer { URLProtocolStub.store.setHandler(nil) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let identity = identity()
        let client = OpenAIResponsesClient(apiKey: "test-key", session: URLSession(configuration: configuration), identityGenerator: { identity })

        let generation = try await client.generateProject(from: "An Azure ingot and matching armor set")

        XCTAssertEqual(generation.project?.items.map(\.displayName), ["Azure Ingot", "Azure Helmet", "Azure Chestplate", "Azure Leggings", "Azure Boots"])
        XCTAssertEqual(generation.project?.recipes.count, 4)
        XCTAssertEqual(generation.project?.items.compactMap { $0.traits.armor?.protection }, [2, 6, 5, 2])
    }

    func testClientAssemblesMaterialSwordSetFromStructuredIntent() async throws {
        let structuredText = """
        {"schemaVersion":1,"outcome":"ready","message":"Ready to build.","shortDescription":"A compact custom pack overview.","sword":null,"materialSwordSet":{"materialName":"Azure","color":"blue","sourceItem":"diamond","sourceCount":4,"swordDisplayName":null,"attackBonus":10,"durability":500},"materialToolSet":null,"materialWeaponSet":null}
        """
        let responseData = try JSONSerialization.data(withJSONObject: ["output": [["content": [["type": "output_text", "text": structuredText]]]]])
        URLProtocolStub.store.setHandler { request in
            (try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)), responseData)
        }
        defer { URLProtocolStub.store.setHandler(nil) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let identity = identity()
        let client = OpenAIResponsesClient(apiKey: "test-key", session: URLSession(configuration: configuration), identityGenerator: { identity })

        let generation = try await client.generateProject(from: "An Azure ingot from four diamonds and a sword")

        XCTAssertEqual(generation.project?.items.map(\.displayName), ["Azure Ingot", "Azure Sword"])
        XCTAssertEqual(generation.project?.shapelessRecipes.first?.ingredients.count, 4)
    }
    func testClientAssemblesAStableProjectFromStructuredIntent() async throws {
        let identity = AddOnProjectIdentity(
            projectID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
            namespace: "craftberry",
            contentSuffix: "a1b2c3",
            packUUIDs: PackUUIDs(
                behaviorHeader: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!,
                behaviorModule: UUID(uuidString: "20000000-0000-4000-8000-000000000002")!,
                resourceHeader: UUID(uuidString: "20000000-0000-4000-8000-000000000003")!,
                resourceModule: UUID(uuidString: "20000000-0000-4000-8000-000000000004")!
            )
        )
        let structuredText = """
        {"schemaVersion":1,"outcome":"ready","message":"Ready to build.","shortDescription":"A compact custom pack overview.","sword":{"displayName":"Azure Sword","color":"blue","attackBonus":20,"durability":500,"craftingIngredient":"diamond"},"materialSwordSet":null,"materialToolSet":null,"materialWeaponSet":null}
        """
        let responseData = try JSONSerialization.data(withJSONObject: [
            "output": [[
                "content": [["type": "output_text", "text": structuredText]]
            ]]
        ])
        URLProtocolStub.store.setHandler { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            return (response, responseData)
        }
        defer { URLProtocolStub.store.setHandler(nil) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let client = OpenAIResponsesClient(
            apiKey: "test-key",
            session: URLSession(configuration: configuration),
            identityGenerator: { identity }
        )

        let generation = try await client.generateProject(from: "A blue diamond sword")

        XCTAssertEqual(generation.outcome, .ready)
        XCTAssertEqual(generation.message, "Ready to build.")
        XCTAssertEqual(generation.project?.shortDescription, "A compact custom pack overview.")
        XCTAssertEqual(generation.project?.id, identity.projectID)
        XCTAssertEqual(generation.project?.packUUIDs, identity.packUUIDs)
        XCTAssertEqual(generation.project?.items.first?.id, ContentID("azure_sword_a1b2c3"))
    }

    func testClientMakesOneRepairAttemptAfterSemanticValidationFails() async throws {
        let invalidResponse = try responseData(attackBonus: 31)
        let repairedResponse = try responseData(attackBonus: 20)
        let recorder = RequestRecorder()
        URLProtocolStub.store.setHandler { request in
            let requestNumber = recorder.record(request)
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            return (response, requestNumber == 1 ? invalidResponse : repairedResponse)
        }
        defer { URLProtocolStub.store.setHandler(nil) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let client = OpenAIResponsesClient(
            apiKey: "test-key",
            session: URLSession(configuration: configuration),
            identityGenerator: {
                AddOnProjectIdentity(
                    projectID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
                    namespace: "craftberry",
                    contentSuffix: "a1b2c3",
                    packUUIDs: PackUUIDs(
                        behaviorHeader: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!,
                        behaviorModule: UUID(uuidString: "20000000-0000-4000-8000-000000000002")!,
                        resourceHeader: UUID(uuidString: "20000000-0000-4000-8000-000000000003")!,
                        resourceModule: UUID(uuidString: "20000000-0000-4000-8000-000000000004")!
                    )
                )
            }
        )

        let generation = try await client.generateProject(from: "A blue diamond sword")

        XCTAssertEqual(generation.project?.items.first?.traits.combat?.attackBonus, 20)
        XCTAssertEqual(recorder.count, 2)
        let repairBody = try XCTUnwrap(recorder.body(at: 1))
        XCTAssertTrue(String(decoding: repairBody, as: UTF8.self).contains("Attack bonus must be between 1 and 30."))
    }

    private func responseData(attackBonus: Int) throws -> Data {
        let structuredText = """
        {"schemaVersion":1,"outcome":"ready","message":"Ready to build.","shortDescription":"A compact custom pack overview.","sword":{"displayName":"Azure Sword","color":"blue","attackBonus":\(attackBonus),"durability":500,"craftingIngredient":"diamond"},"materialSwordSet":null,"materialToolSet":null,"materialWeaponSet":null}
        """
        return try JSONSerialization.data(withJSONObject: [
            "output": [[
                "content": [["type": "output_text", "text": structuredText]]
            ]]
        ])
    }

    private func backendClient(identity: AddOnProjectIdentity = .generate()) -> BackendGenerationClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return BackendGenerationClient(
            baseURL: URL(string: "https://generation.test"),
            credentialProvider: CredentialProviderSpy(token: "runtime-test-token"),
            session: URLSession(configuration: configuration),
            identityGenerator: { identity }
        )
    }

    private func assertBackendFailure(
        scenario: String,
        expected: BackendGenerationClientError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let (status, body) = try fixtureScenario(scenario, in: generationFixture())
        URLProtocolStub.store.setHandler { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: status, httpVersion: nil, headerFields: nil)
            )
            return (response, body)
        }
        defer { URLProtocolStub.store.setHandler(nil) }

        do {
            _ = try await backendClient().generateProject(from: "Craft a cyan diamond sword named Harbor.")
            XCTFail("Expected backend error \(expected)", file: file, line: line)
        } catch let error as BackendGenerationClientError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func generationFixture() throws -> [String: Any] {
        #if SWIFT_PACKAGE
        let fixtureURL = try XCTUnwrap(Bundle.module.url(forResource: "GenerationV1", withExtension: "json"))
        let data = try Data(contentsOf: fixtureURL)
        #else
        let data = Data(Self.generationFixtureFallback.utf8)
        #endif
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func fixtureScenario(_ name: String, in fixture: [String: Any]) throws -> (Int, Data) {
        let responses = try XCTUnwrap(fixture["responses"] as? [String: [String: Any]])
        let scenario = try XCTUnwrap(responses[name])
        let status = try XCTUnwrap(scenario["status"] as? Int)
        let body = try XCTUnwrap(scenario["body"])
        return (status, try JSONSerialization.data(withJSONObject: body))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    #if !SWIFT_PACKAGE
    private static let generationFixtureFallback = #"""
    {
      "method":"POST","path":"/v1/generate",
      "request":{"intentVersion":1,"profileID":"bedrock-stable-1.26.30","prompt":"Craft a cyan diamond sword named Harbor."},
      "responses":{
        "ready":{"status":200,"body":{"schemaVersion":1,"outcome":"ready","message":"Ready to build.","shortDescription":"A cyan sword crafted from diamonds.","sword":{"displayName":"Harbor","color":"cyan","attackBonus":12,"durability":600,"craftingIngredient":"diamond"}}},
        "unsupported":{"status":200,"body":{"schemaVersion":1,"outcome":"unsupported","message":"This add-on needs a feature outside the active profile."}},
        "unauthorized":{"status":401,"body":{"error":"unauthorized"}},
        "quota":{"status":429,"body":{"error":"quota_exceeded"}},
        "serviceFailure":{"status":503,"body":{"error":"service_unavailable"}}
      }
    }
    """#
    #endif

    private func identity() -> AddOnProjectIdentity {
        AddOnProjectIdentity(projectID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!, namespace: "craftberry", contentSuffix: "a1b2c3", packUUIDs: PackUUIDs(behaviorHeader: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!, behaviorModule: UUID(uuidString: "20000000-0000-4000-8000-000000000002")!, resourceHeader: UUID(uuidString: "20000000-0000-4000-8000-000000000003")!, resourceModule: UUID(uuidString: "20000000-0000-4000-8000-000000000004")!))
    }
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    static let store = URLProtocolStubStore()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try Self.store.handle(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private actor CredentialProviderSpy: RuntimeGenerationCredentialProvider {
    private let token: String
    private var requests = 0
    private var assertionRequests = 0

    init(token: String) {
        self.token = token
    }

    func requestCount() -> Int {
        requests
    }

    func assertionRequestCount() -> Int { assertionRequests }

    func bearerToken() async throws -> String {
        requests += 1
        return token
    }

    func assertionHeaders(for requestBody: Data, idempotencyKey: String) async throws -> GenerationAssertionHeaders {
        assertionRequests += 1
        let challenge = Data("mock-challenge-\(assertionRequests)".utf8)
        let clientData = GenerationAssertionClientData(
            challengeID: "mock-challenge-id-\(assertionRequests)",
            challenge: challenge.base64EncodedString(),
            requestBodySHA256: Self.base64URL(Data(SHA256.hash(data: requestBody))),
            idempotencyKey: idempotencyKey
        )
        return GenerationAssertionHeaders(
            challengeID: clientData.challengeID,
            clientData: try clientData.canonicalData().base64EncodedString(),
            assertion: Data("mock-assertion-\(assertionRequests)".utf8).base64EncodedString()
        )
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private actor SessionCredentialStoreSpy: GenerationSessionCredentialStore {
    private var token: String?
    private var keyID: String?

    init(token: String? = nil, keyID: String? = nil) {
        self.token = token
        self.keyID = keyID
    }

    func bearerToken() async throws -> String? { token }
    func appAttestKeyID() async throws -> String? { keyID }

    func saveBearerToken(_ token: String) async throws {
        self.token = token
    }

    func saveAppAttestKeyID(_ keyID: String) async throws {
        self.keyID = keyID
    }

    func clearSession() async throws {
        token = nil
        keyID = nil
    }

    func values() -> (token: String?, keyID: String?) {
        (token, keyID)
    }
}

private actor FlakySessionCredentialStore: GenerationSessionCredentialStore {
    private var token: String?
    private var keyID: String?
    private var clearFailuresRemaining: Int

    init(token: String?, keyID: String?, clearFailuresRemaining: Int) {
        self.token = token
        self.keyID = keyID
        self.clearFailuresRemaining = clearFailuresRemaining
    }

    func bearerToken() async throws -> String? { token }
    func appAttestKeyID() async throws -> String? { keyID }

    func saveBearerToken(_ token: String) async throws { self.token = token }
    func saveAppAttestKeyID(_ keyID: String) async throws { self.keyID = keyID }

    func clearSession() async throws {
        if clearFailuresRemaining > 0 {
            clearFailuresRemaining -= 1
            throw SessionCredentialStoreTestError.clearFailed
        }
        token = nil
        keyID = nil
    }

    func values() -> (token: String?, keyID: String?) { (token, keyID) }
}

private enum SessionCredentialStoreTestError: Error {
    case clearFailed
}

private actor InvalidOnceAppAttestState {
    private var assertionCalls = 0
    private var keyCalls = 0

    func generateKey() -> String {
        keyCalls += 1
        return "recovered-app-attest-key"
    }

    func generateAssertion() throws -> Data {
        assertionCalls += 1
        if assertionCalls == 1 { throw GenerationAppAttestError.invalidKey }
        return Data("recovered-assertion".utf8)
    }
}

private struct InvalidOnceAppAttestService: GenerationAppAttestService {
    private let state = InvalidOnceAppAttestState()
    var isSupported: Bool { true }

    func generateKey() async throws -> String { await state.generateKey() }
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data { Data("attestation".utf8) }
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await state.generateAssertion()
    }
}

private actor LateInvalidKeyAppAttestState {
    private var assertionCalls = 0
    private var firstAssertionStarted = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var releaseRequested = false

    func generateKey() -> String { "replacement-app-attest-key" }

    func waitForFirstAssertion(timeoutNanoseconds: UInt64) async -> Bool {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutNanoseconds) / 1_000_000_000)
        while !firstAssertionStarted, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return firstAssertionStarted
    }

    func releaseFirstAssertion() {
        releaseRequested = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func generateAssertion() async throws -> Data {
        assertionCalls += 1
        if assertionCalls == 1 {
            firstAssertionStarted = true
            if !releaseRequested {
                await withCheckedContinuation { releaseContinuation = $0 }
            }
            throw GenerationAppAttestError.invalidKey
        }
        if assertionCalls == 2 { throw GenerationAppAttestError.invalidKey }
        return Data("replacement-assertion".utf8)
    }
}

private struct LateInvalidKeyAppAttestService: GenerationAppAttestService {
    let state: LateInvalidKeyAppAttestState
    var isSupported: Bool { true }

    func generateKey() async throws -> String { await state.generateKey() }
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data { Data("attestation".utf8) }
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await state.generateAssertion()
    }
}

private actor AppAttestStateSpy {
    private var generated = 0
    private var attested = 0
    private var lastClientDataHash: Data?
    private var assertionHashes: [Data] = []

    func didGenerate() { generated += 1 }

    func didAttest(clientDataHash: Data) {
        attested += 1
        lastClientDataHash = clientDataHash
    }

    func didAssert(clientDataHash: Data) { assertionHashes.append(clientDataHash) }

    func counts() -> (generated: Int, attested: Int, lastClientDataHash: Data?, assertions: Int, assertionHashes: [Data]) {
        (generated, attested, lastClientDataHash, assertionHashes.count, assertionHashes)
    }
}

private struct AppAttestServiceSpy: GenerationAppAttestService {
    let state: AppAttestStateSpy
    var isSupported: Bool { true }

    func generateKey() async throws -> String {
        await state.didGenerate()
        return "fixture-app-attest-key-id"
    }

    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        await state.didAttest(clientDataHash: clientDataHash)
        return Data("fixture-attestation".utf8)
    }

    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        await state.didAssert(clientDataHash: clientDataHash)
        return Data("fixture-assertion".utf8)
    }
}

private actor RetryableAttestationState {
    private var keyIDs: [String] = []
    private var clientDataHashes: [Data] = []

    func generateKey() -> String {
        "retry-app-attest-key-\(keyIDs.count + 1)"
    }

    func attest(keyID: String, clientDataHash: Data) throws -> Data {
        keyIDs.append(keyID)
        clientDataHashes.append(clientDataHash)
        if keyIDs.count == 1 { throw GenerationAppAttestError.serverUnavailable }
        return Data("retry-attestation-object".utf8)
    }

    func values() -> (keyIDs: [String], clientDataHashes: [Data]) {
        (keyIDs, clientDataHashes)
    }
}

private struct RetryableAttestationService: GenerationAppAttestService {
    let state: RetryableAttestationState
    var isSupported: Bool { true }

    func generateKey() async throws -> String { await state.generateKey() }
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await state.attest(keyID: keyID, clientDataHash: clientDataHash)
    }
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        Data("retry-assertion".utf8)
    }
}

private actor EnrollmentTransportStateSpy {
    private let challenge: Data
    private var challengeRequests = 0
    private var enrollmentRequests = 0

    init(challenge: Data) {
        self.challenge = challenge
    }

    func requestChallenge() -> GenerationEnrollmentChallenge {
        challengeRequests += 1
        return GenerationEnrollmentChallenge(
            challengeID: "fixture-challenge-id-\(challengeRequests)",
            challengeBase64: (challenge + Data([UInt8(challengeRequests)])).base64EncodedString()
        )
    }

    func enroll() -> String {
        enrollmentRequests += 1
        return "fixture-session-token"
    }

    func counts() -> (challenge: Int, enroll: Int) {
        (challengeRequests, enrollmentRequests)
    }
}

private struct EnrollmentTransportSpy: GenerationSessionEnrollmentTransport {
    let state: EnrollmentTransportStateSpy

    func requestChallenge() async throws -> GenerationEnrollmentChallenge {
        await state.requestChallenge()
    }

    func enroll(
        keyID: String,
        challenge: GenerationEnrollmentChallenge,
        attestationObject: Data
    ) async throws -> String {
        await state.enroll()
    }
}

private actor FlakyChallengeTransportState {
    private var challenges = 0

    func requestChallenge() throws -> GenerationEnrollmentChallenge {
        challenges += 1
        if challenges == 1 { throw BackendGenerationClientError.serviceUnavailable }
        return GenerationEnrollmentChallenge(
            challengeID: "retry-challenge-\(challenges)",
            challengeBase64: Data("retry-challenge-bytes".utf8).base64EncodedString()
        )
    }

    func enroll() -> String { "fixture-session-token" }
    func counts() -> Int { challenges }
}

private struct FlakyChallengeEnrollmentTransport: GenerationSessionEnrollmentTransport {
    let state: FlakyChallengeTransportState

    func requestChallenge() async throws -> GenerationEnrollmentChallenge {
        try await state.requestChallenge()
    }

    func enroll(
        keyID: String,
        challenge: GenerationEnrollmentChallenge,
        attestationObject: Data
    ) async throws -> String {
        await state.enroll()
    }
}

private final class URLProtocolStubStore: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private let lock = NSLock()
    private var handler: Handler?

    func setHandler(_ handler: Handler?) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func handle(_ request: URLRequest) throws -> (HTTPURLResponse, Data) {
        lock.lock()
        let handler = handler
        lock.unlock()
        guard let handler else { throw LLMClientError.invalidResponse }
        return try handler(request)
    }
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    private var bodies: [Data?] = []

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests.count
    }

    func record(_ request: URLRequest) -> Int {
        let body = request.httpBody ?? Self.readBodyStream(request.httpBodyStream)
        lock.lock()
        defer { lock.unlock() }
        requests.append(request)
        bodies.append(body)
        return requests.count
    }

    func body(at index: Int) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return bodies[index]
    }

    func request(at index: Int) -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        guard requests.indices.contains(index) else { return nil }
        return requests[index]
    }

    private static func readBodyStream(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
