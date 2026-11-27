import CryptoKit
import CSQLite
import Foundation
import XCTest
@testable import CraftberryCore

final class GenerationServiceTests: XCTestCase {
    private static let assertionSequence = TestAssertionSequence()

    func testGenerationServerMainTypeLivesOutsideImplicitMainSwiftFile() {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let serverDirectory = repositoryRoot.appending(
            path: "Tools/GenerationServer",
            directoryHint: .isDirectory
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: serverDirectory.appending(path: "GenerationServerMain.swift").path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: serverDirectory.appending(path: "main.swift").path),
            "The executable target bundles resources; keep its @main entry point out of main.swift for older SwiftPM toolchains."
        )
    }

    func testFixtureContractSupportsReadyAndUnsupportedIntents() async throws {
        let fixture = try generationFixture()
        let ready = try fixtureBody("ready", fixture: fixture)
        let unsupported = try fixtureBody("unsupported", fixture: fixture)
        let harness = try await makeHarness(provider: ScriptedIntentProvider(intent: String(decoding: ready, as: UTF8.self)))
        let request = try await generationRequest(from: fixture, service: harness.service, token: harness.token, idempotencyKey: "ready-fixture")

        let readyResponse = await harness.service.handle(request)
        XCTAssertEqual(readyResponse.statusCode, 200)
        XCTAssertEqual(try jsonValue(readyResponse.body), try jsonValue(ready))

        let unsupportedHarness = try await makeHarness(
            provider: ScriptedIntentProvider(intent: String(decoding: unsupported, as: UTF8.self))
        )
        let unsupportedRequest = try await generationRequest(from: fixture, service: unsupportedHarness.service, token: unsupportedHarness.token, idempotencyKey: "unsupported-fixture")
        let unsupportedResponse = await unsupportedHarness.service.handle(unsupportedRequest)
        XCTAssertEqual(unsupportedResponse.statusCode, 200)
        XCTAssertEqual(try jsonValue(unsupportedResponse.body), try jsonValue(unsupported))
    }

    func testMissingOrUnknownSessionReturnsFixtureUnauthorizedStatus() async throws {
        let harness = try await makeHarness()
        let fixture = try generationFixture()
        let body = try fixtureRequestBody(fixture)

        let missing = await harness.service.handle(.init(method: "POST", path: "/v1/generate", body: body))
        XCTAssertEqual(missing.statusCode, 401)
        XCTAssertEqual(try errorCode(missing), "unauthorized")

        let unknown = await harness.service.handle(.init(
            method: "POST",
            path: "/v1/generate",
            headers: ["Authorization": "Bearer \(Self.token())"],
            body: body
        ))
        XCTAssertEqual(unknown.statusCode, 401)
        XCTAssertEqual(try errorCode(unknown), "unauthorized")
    }

    func testStoreFailureWhileResolvingSessionReturnsServiceUnavailable() async throws {
        let fixture = try generationFixture()
        let intent = String(decoding: try fixtureBody("ready", fixture: fixture), as: UTF8.self)
        let service = makeService(
            store: InstallationLookupFailingStore(),
            provider: ScriptedIntentProvider(intent: intent),
            clock: ManualGenerationClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        )
        let token = try await enroll(service)
        let response = await service.handle(
            try await generationRequest(from: fixture, service: service, token: token, idempotencyKey: "store-read-failure")
        )

        XCTAssertEqual(response.statusCode, 503)
        XCTAssertEqual(try errorCode(response), "service_unavailable")
    }

    func testEnrollmentChallengeCanOnlyRegisterOnce() async throws {
        let fixture = try generationFixture()
        let intent = String(decoding: try fixtureBody("ready", fixture: fixture), as: UTF8.self)
        let store = InMemoryGenerationServiceStore()
        let clock = ManualGenerationClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        let service = makeService(
            store: store,
            provider: ScriptedIntentProvider(intent: intent),
            clock: clock
        )
        let challenge = await service.handle(.init(method: "POST", path: "/v1/session/challenge", body: Data("{}".utf8)))
        let challengeJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: challenge.body) as? [String: Any])
        let enrollmentBody = try JSONSerialization.data(withJSONObject: [
            "challengeID": try XCTUnwrap(challengeJSON["challengeID"] as? String),
            "keyID": "fixture-app-attest-key-id",
            "attestationObject": Data("valid-attestation-fixture".utf8).base64EncodedString()
        ])

        let first = await service.handle(.init(method: "POST", path: "/v1/session/enroll", body: enrollmentBody))
        let consumedChallenge = try await store.enrollmentChallenge(
            id: try XCTUnwrap(challengeJSON["challengeID"] as? String),
            now: clock.now()
        )
        let replay = await service.handle(.init(method: "POST", path: "/v1/session/enroll", body: enrollmentBody))

        XCTAssertEqual(first.statusCode, 200)
        XCTAssertNil(consumedChallenge, "A successful enrollment must delete its challenge before its expiry.")
        XCTAssertEqual(replay.statusCode, 401)
        XCTAssertEqual(try errorCode(replay), "unauthorized")
    }

    func testGenerationAssertionBindsRequestAndCanOnlyBeConsumedOnce() async throws {
        let fixture = try generationFixture()
        let ready = String(decoding: try fixtureBody("ready", fixture: fixture), as: UTF8.self)
        let provider = ScriptedIntentProvider(intent: ready)
        let harness = try await makeHarness(provider: provider)
        let request = try await generationRequest(
            from: fixture,
            service: harness.service,
            token: harness.token,
            idempotencyKey: "assertion-replay"
        )

        var alteredBody = request.body
        alteredBody.append(0x20)
        let tamperedRequest = GenerationServiceRequest(
            method: request.method,
            path: request.path,
            headers: request.headers,
            body: alteredBody
        )
        let tampered = await harness.service.handle(tamperedRequest)
        let first = await harness.service.handle(request)
        let replay = await harness.service.handle(request)

        XCTAssertEqual(tampered.statusCode, 401)
        XCTAssertEqual(first.statusCode, 200, "A body-tampered request must be rejected before consuming the assertion challenge.")
        XCTAssertEqual(replay.statusCode, 401)
        let calls = await provider.callCount()
        XCTAssertEqual(calls, 1)
    }

    func testPromptLimitAccepts600CharactersAndRejects601BeforeProvider() async throws {
        let fixture = try generationFixture()
        let intent = String(decoding: try fixtureBody("ready", fixture: fixture), as: UTF8.self)
        let provider = ScriptedIntentProvider(intent: intent)
        let harness = try await makeHarness(provider: provider)
        let json = try fixtureRequestBody(fixture)
        var request = try JSONDecoder().decode(TestGenerationRequest.self, from: json)
        request.prompt = String(repeating: "é", count: 600)

        let accepted = await harness.service.handle(try await makeRequest(request, service: harness.service, token: harness.token, idempotencyKey: "prompt-600"))
        XCTAssertEqual(accepted.statusCode, 200)

        request.prompt += "é"
        let rejected = await harness.service.handle(try await makeRequest(request, service: harness.service, token: harness.token, idempotencyKey: "prompt-601"))
        XCTAssertEqual(rejected.statusCode, 400)
        XCTAssertEqual(try errorCode(rejected), "prompt_too_long")
        let providerCalls = await provider.callCount()
        XCTAssertEqual(providerCalls, 1)
    }

    func testGenerationEnforcesFivePerMinuteForOneInstallation() async throws {
        let fixture = try generationFixture()
        let intent = String(decoding: try fixtureBody("ready", fixture: fixture), as: UTF8.self)
        let harness = try await makeHarness(provider: ScriptedIntentProvider(intent: intent))
        var statuses: [Int] = []
        for index in 0..<10 {
            let request = try await generationRequest(
                from: fixture,
                service: harness.service,
                token: harness.token,
                idempotencyKey: "per-minute-\(index)"
            )
            statuses.append(await harness.service.handle(request).statusCode)
        }

        XCTAssertEqual(statuses.filter { $0 == 200 }.count, 5)
        XCTAssertEqual(statuses.filter { $0 == 429 }.count, 5)
        XCTAssertEqual(statuses.filter { $0 != 200 && $0 != 429 }.count, 0)
    }

    func testConcurrentQuotaReservationsAcrossSQLiteConnectionsAreAtomic() async throws {
        let fixture = try generationFixture()
        let intent = String(decoding: try fixtureBody("ready", fixture: fixture), as: UTF8.self)
        let databaseURL = try testDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let clock = ManualGenerationClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        let firstStore = try SQLiteGenerationServiceStore(databaseURL: databaseURL)
        let provider = ScriptedIntentProvider(intent: intent)
        let firstService = makeService(store: firstStore, provider: provider, clock: clock)
        let token = try await enroll(firstService)
        let secondStore = try SQLiteGenerationServiceStore(databaseURL: databaseURL)
        let tokenDigest = Data(SHA256.hash(data: Data(token.utf8)))
        let resolvedInstallationID = try await firstStore.installationID(forTokenDigest: tokenDigest)
        let installationID = try XCTUnwrap(resolvedInstallationID)
        let requestFingerprint = Data(SHA256.hash(data: try fixtureRequestBody(fixture)))

        let statuses = await withTaskGroup(of: Int.self, returning: [Int].self) { group in
            for index in 0..<10 {
                group.addTask {
                    let store = index.isMultiple(of: 2) ? firstStore : secondStore
                    do {
                        switch try await store.reserveGeneration(
                            installationID: installationID,
                            idempotencyKey: "sqlite-parallel-\(index)",
                            requestFingerprint: requestFingerprint,
                            now: clock.now(),
                            quota: .default
                        ) {
                        case .reserved: return 200
                        case .limited: return 429
                        default: return 500
                        }
                    } catch {
                        return 500
                    }
                }
            }
            var results: [Int] = []
            for await result in group { results.append(result) }
            return results
        }

        XCTAssertEqual(statuses.filter { $0 == 200 }.count, 5)
        XCTAssertEqual(statuses.filter { $0 == 429 }.count, 5)
        XCTAssertEqual(statuses.filter { $0 != 200 && $0 != 429 }.count, 0)
    }

    func testSQLiteAssertionCounterAndChallengeConsumptionAreAtomicAndDurable() async throws {
        let fixture = try generationFixture()
        let intent = String(decoding: try fixtureBody("ready", fixture: fixture), as: UTF8.self)
        let databaseURL = try testDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let firstStore = try SQLiteGenerationServiceStore(databaseURL: databaseURL)
        let firstService = makeService(
            store: firstStore,
            provider: ScriptedIntentProvider(intent: intent),
            clock: ManualGenerationClock(now: now)
        )
        let token = try await enroll(firstService)
        let tokenDigest = Data(SHA256.hash(data: Data(token.utf8)))
        let resolvedInstallationID = try await firstStore.installationID(forTokenDigest: tokenDigest)
        let installationID = try XCTUnwrap(resolvedInstallationID)
        let secondStore = try SQLiteGenerationServiceStore(databaseURL: databaseURL)
        let storedReceipt = try await secondStore.appAttestReceipt(for: installationID)
        XCTAssertEqual(storedReceipt, Data("fixture-receipt".utf8))
        let challenge = StoredEnrollmentChallenge(
            id: "assertion-concurrent-replay",
            challenge: Data(repeating: 0x44, count: 32),
            expiresAt: now.addingTimeInterval(300)
        )
        try await firstStore.createEnrollmentChallenge(challenge, now: now)

        let consumed = try await withThrowingTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for store in [firstStore, secondStore] {
                group.addTask {
                    try await store.consumeAppAttestAssertion(
                        challengeID: challenge.id,
                        installationID: installationID,
                        expectedCounter: 0,
                        newCounter: 1,
                        now: now
                    )
                }
            }
            var results: [Bool] = []
            for try await result in group { results.append(result) }
            return results
        }
        XCTAssertEqual(consumed.filter { $0 }.count, 1)
        XCTAssertEqual(consumed.filter { !$0 }.count, 1)
        let consumedChallenge = try await secondStore.enrollmentChallenge(id: challenge.id, now: now)
        XCTAssertNil(consumedChallenge)

        let nextChallenge = StoredEnrollmentChallenge(
            id: "assertion-next-counter",
            challenge: Data(repeating: 0x45, count: 32),
            expiresAt: now.addingTimeInterval(300)
        )
        try await secondStore.createEnrollmentChallenge(nextChallenge, now: now)
        let replayedCounter = try await secondStore.consumeAppAttestAssertion(
            challengeID: nextChallenge.id,
            installationID: installationID,
            expectedCounter: 0,
            newCounter: 1,
            now: now
        )
        XCTAssertFalse(replayedCounter)
        let advancedCounter = try await secondStore.consumeAppAttestAssertion(
            challengeID: nextChallenge.id,
            installationID: installationID,
            expectedCounter: 0,
            newCounter: 2,
            now: now
        )
        XCTAssertTrue(advancedCounter)

        let restartedStore = try SQLiteGenerationServiceStore(databaseURL: databaseURL)
        let credential = try await restartedStore.appAttestCredential(for: installationID)
        XCTAssertEqual(credential?.assertionCounter, 2)
    }

    func testUnusedExpiredEnrollmentChallengesAreDeletedWhenIssuingAnother() async throws {
        let databaseURL = try testDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try SQLiteGenerationServiceStore(databaseURL: databaseURL)
        try await store.createEnrollmentChallenge(.init(
            id: "expired-unused",
            challenge: Data(repeating: 1, count: 32),
            expiresAt: now.addingTimeInterval(-1)
        ), now: now)
        try await store.createEnrollmentChallenge(.init(
            id: "still-live",
            challenge: Data(repeating: 2, count: 32),
            expiresAt: now.addingTimeInterval(60)
        ), now: now)

        try await store.createEnrollmentChallenge(.init(
            id: "new-challenge",
            challenge: Data(repeating: 3, count: 32),
            expiresAt: now.addingTimeInterval(300)
        ), now: now)

        XCTAssertEqual(try sqliteCount("SELECT COUNT(*) FROM enrollment_challenges WHERE challenge_id = 'expired-unused'", at: databaseURL), 0)
        XCTAssertEqual(try sqliteCount("SELECT COUNT(*) FROM enrollment_challenges WHERE challenge_id = 'still-live'", at: databaseURL), 1)
    }

    func testEnrollmentExpiryIsCheckedAfterAttestationVerification() async throws {
        let databaseURL = try testDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = ManualGenerationClock(now: now)
        let store = try SQLiteGenerationServiceStore(databaseURL: databaseURL)
        let service = makeService(
            store: store,
            provider: ScriptedIntentProvider(),
            clock: clock,
            attestationVerifier: ChallengeExpiringFixtureVerifier(clock: clock)
        )
        let challenge = await service.handle(.init(method: "POST", path: "/v1/session/challenge", body: Data("{}".utf8)))
        let challengeBody = try XCTUnwrap(JSONSerialization.jsonObject(with: challenge.body) as? [String: String])
        let enrollmentBody = try JSONSerialization.data(withJSONObject: [
            "challengeID": try XCTUnwrap(challengeBody["challengeID"]),
            "keyID": "fixture-app-attest-key-id",
            "attestationObject": Data("valid-attestation-fixture".utf8).base64EncodedString()
        ])

        let response = await service.handle(.init(method: "POST", path: "/v1/session/enroll", body: enrollmentBody))

        XCTAssertEqual(response.statusCode, 401)
        XCTAssertEqual(try errorCode(response), "unauthorized")
        XCTAssertEqual(try sqliteCount("SELECT COUNT(*) FROM installations", at: databaseURL), 0)
    }

    func testSQLiteGenerationErrorsPropagateInsteadOfBecomingCleanRejections() async throws {
        let databaseURL = try testDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let store = try SQLiteGenerationServiceStore(databaseURL: databaseURL)
        let clock = ManualGenerationClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        let service = makeService(store: store, provider: ScriptedIntentProvider(), clock: clock)
        let token = try await enroll(service)
        let tokenDigest = Data(SHA256.hash(data: Data(token.utf8)))
        let storedInstallationID = try await store.installationID(forTokenDigest: tokenDigest)
        let installationID = try XCTUnwrap(storedInstallationID)
        try executeSQLite("""
        CREATE TRIGGER fail_generation_quota BEFORE INSERT ON generation_quota_events
        BEGIN SELECT RAISE(ABORT, 'intentional test transaction failure'); END;
        """, at: databaseURL)

        do {
            _ = try await store.reserveGeneration(
                installationID: installationID,
                idempotencyKey: "sqlite-failure",
                requestFingerprint: Data(repeating: 4, count: 32),
                now: clock.now(),
                quota: .default
            )
            XCTFail("Expected the SQLite transaction error to propagate.")
        } catch let error as SQLiteGenerationServiceStoreError {
            guard case .database = error else {
                XCTFail("Expected database error, got \(error)")
                return
            }
        }
    }

    func testSQLiteReservationOwnershipPreventsLiveReclaimAndRejectsStaleFinalizers() async throws {
        let databaseURL = try testDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let firstStore = try SQLiteGenerationServiceStore(databaseURL: databaseURL, processID: "server-before-restart")
        let service = makeService(store: firstStore, provider: ScriptedIntentProvider(), clock: ManualGenerationClock(now: now))
        let token = try await enroll(service)
        let digest = Data(SHA256.hash(data: Data(token.utf8)))
        let storedInstallationID = try await firstStore.installationID(forTokenDigest: digest)
        let installationID = try XCTUnwrap(storedInstallationID)
        let fingerprint = Data(repeating: 5, count: 32)
        let key = "restart-safe-reservation"
        guard case .reserved(let originalReservation) = try await firstStore.reserveGeneration(
            installationID: installationID,
            idempotencyKey: key,
            requestFingerprint: fingerprint,
            now: now,
            quota: .default
        ) else { return XCTFail("Expected first reservation") }

        let siblingStore = try SQLiteGenerationServiceStore(databaseURL: databaseURL, processID: "server-before-restart")
        let stillRunning = try await siblingStore.reserveGeneration(
            installationID: installationID,
            idempotencyKey: key,
            requestFingerprint: fingerprint,
            now: now.addingTimeInterval(120),
            quota: .default
        )
        guard case .inProgress = stillRunning else { return XCTFail("A live provider reservation must not be reclaimed by age.") }

        let restartedStore = try SQLiteGenerationServiceStore(databaseURL: databaseURL, processID: "server-after-restart")
        guard case .reserved(let recoveredReservation) = try await restartedStore.reserveGeneration(
            installationID: installationID,
            idempotencyKey: key,
            requestFingerprint: fingerprint,
            now: now.addingTimeInterval(120),
            quota: .default
        ) else { return XCTFail("A confirmed process restart should recover the abandoned reservation.") }
        let staleCompletion = try await firstStore.completeGeneration(
            installationID: installationID,
            idempotencyKey: key,
            reservationID: originalReservation,
            response: Data("stale".utf8),
            now: now.addingTimeInterval(121)
        )
        let staleRetryable = try await firstStore.markGenerationRetryable(
            installationID: installationID,
            idempotencyKey: key,
            reservationID: originalReservation,
            now: now.addingTimeInterval(121)
        )
        let recoveredCompletion = try await restartedStore.completeGeneration(
            installationID: installationID,
            idempotencyKey: key,
            reservationID: recoveredReservation,
            response: Data("fresh".utf8),
            now: now.addingTimeInterval(122)
        )
        let replay = try await restartedStore.reserveGeneration(
            installationID: installationID,
            idempotencyKey: key,
            requestFingerprint: fingerprint,
            now: now.addingTimeInterval(123),
            quota: .default
        )

        XCTAssertFalse(staleCompletion)
        XCTAssertFalse(staleRetryable)
        XCTAssertTrue(recoveredCompletion)
        guard case .replay(let replayedData) = replay else { return XCTFail("Expected only the current reservation to complete.") }
        XCTAssertEqual(replayedData, Data("fresh".utf8))
    }

    func testSQLiteCleanupPreservesReservationRenewedByRetry() async throws {
        let databaseURL = try testDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let store = try SQLiteGenerationServiceStore(databaseURL: databaseURL, processID: "stable-process")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let service = makeService(store: store, provider: ScriptedIntentProvider(), clock: ManualGenerationClock(now: base))
        let token = try await enroll(service)
        let digest = Data(SHA256.hash(data: Data(token.utf8)))
        let storedInstallationID = try await store.installationID(forTokenDigest: digest)
        let installationID = try XCTUnwrap(storedInstallationID)
        let fingerprint = Data(repeating: 6, count: 32)
        let key = "renewed-reservation"
        guard case .reserved(let firstReservation) = try await store.reserveGeneration(
            installationID: installationID,
            idempotencyKey: key,
            requestFingerprint: fingerprint,
            now: base,
            quota: .default
        ) else { return XCTFail("Expected initial reservation") }
        let retryTime = base.addingTimeInterval(90_000)
        let markedRetryable = try await store.markGenerationRetryable(
            installationID: installationID,
            idempotencyKey: key,
            reservationID: firstReservation,
            now: retryTime
        )
        XCTAssertTrue(markedRetryable)
        guard case .reserved = try await store.reserveGeneration(
            installationID: installationID,
            idempotencyKey: key,
            requestFingerprint: fingerprint,
            now: retryTime,
            quota: .default
        ) else { return XCTFail("Expected retry reservation") }
        _ = try await store.reserveGeneration(
            installationID: installationID,
            idempotencyKey: "trigger-cleanup",
            requestFingerprint: Data(repeating: 7, count: 32),
            now: retryTime.addingTimeInterval(86_401),
            quota: .default
        )

        let preserved = try await store.reserveGeneration(
            installationID: installationID,
            idempotencyKey: key,
            requestFingerprint: fingerprint,
            now: retryTime.addingTimeInterval(86_402),
            quota: .default
        )
        guard case .inProgress = preserved else { return XCTFail("Cleanup must preserve the recently renewed reservation.") }
    }

    func testConcurrentSameIdempotencyKeyRunsProviderOnceAndReturnsReplay() async throws {
        let fixture = try generationFixture()
        let intent = String(decoding: try fixtureBody("ready", fixture: fixture), as: UTF8.self)
        let provider = BlockingIntentProvider(intent: intent)
        let store = InMemoryGenerationServiceStore()
        let service = makeService(
            store: store,
            provider: provider,
            clock: ManualGenerationClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        )
        let token = try await enroll(service)
        let request = try await generationRequest(from: fixture, service: service, token: token, idempotencyKey: "same-in-flight-operation")
        let overlappingRequest = try await generationRequest(from: fixture, service: service, token: token, idempotencyKey: "same-in-flight-operation")
        let firstTask = Task { await service.handle(request) }
        let started = await provider.waitUntilStarted(timeoutNanoseconds: 2_000_000_000)
        guard started else {
            await provider.release()
            _ = await firstTask.value
            XCTFail("Provider did not start within the bounded wait.")
            return
        }
        let overlapping = await service.handle(overlappingRequest)
        await provider.release()
        let first = await firstTask.value
        let retryRequest = try await generationRequest(from: fixture, service: service, token: token, idempotencyKey: "same-in-flight-operation")
        let retry = await service.handle(retryRequest)

        XCTAssertEqual(overlapping.statusCode, 409)
        XCTAssertEqual(try errorCode(overlapping), "generation_in_progress")
        XCTAssertEqual(first.statusCode, 200)
        XCTAssertEqual(retry.statusCode, 200)
        XCTAssertEqual(retry.body, first.body)
        let calls = await provider.callCount()
        XCTAssertEqual(calls, 1)
    }

    func testEveryProviderRetryCountsTowardInstallationQuota() async throws {
        let fixture = try generationFixture()
        let intent = String(decoding: try fixtureBody("ready", fixture: fixture), as: UTF8.self)
        let provider = ScriptedIntentProvider(intent: intent, initialFailures: 5)
        let harness = try await makeHarness(provider: provider)

        for attempt in 1...5 {
            let response = await harness.service.handle(try await generationRequest(
                from: fixture,
                service: harness.service,
                token: harness.token,
                idempotencyKey: "retry-same-operation"
            ))
            XCTAssertEqual(response.statusCode, 503, "provider attempt \(attempt) should be retryable")
            XCTAssertEqual(try errorCode(response), "service_unavailable")
        }

        let deniedRetry = await harness.service.handle(try await generationRequest(
            from: fixture,
            service: harness.service,
            token: harness.token,
            idempotencyKey: "retry-same-operation"
        ))
        XCTAssertEqual(deniedRetry.statusCode, 429)
        XCTAssertEqual(try errorCode(deniedRetry), "quota_exceeded")
        harness.clock.advance(by: 61)
        let allowedAfterWindow = await harness.service.handle(try await generationRequest(
            from: fixture,
            service: harness.service,
            token: harness.token,
            idempotencyKey: "retry-same-operation"
        ))
        XCTAssertEqual(allowedAfterWindow.statusCode, 200)
        let calls = await provider.callCount()
        XCTAssertEqual(calls, 6)
    }

    func testRetryQuotaIsDurableAcrossSQLiteStoreRestart() async throws {
        let fixture = try generationFixture()
        let intent = String(decoding: try fixtureBody("ready", fixture: fixture), as: UTF8.self)
        let databaseURL = try testDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let clock = ManualGenerationClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        let provider = ScriptedIntentProvider(intent: intent, initialFailures: 5)
        let firstStore = try SQLiteGenerationServiceStore(databaseURL: databaseURL)
        let firstService = makeService(store: firstStore, provider: provider, clock: clock)
        let token = try await enroll(firstService)

        for _ in 1...5 {
            let response = await firstService.handle(try await generationRequest(
                from: fixture,
                service: firstService,
                token: token,
                idempotencyKey: "sqlite-retry-budget"
            ))
            XCTAssertEqual(response.statusCode, 503)
        }

        let restartedStore = try SQLiteGenerationServiceStore(databaseURL: databaseURL)
        let restartedService = makeService(store: restartedStore, provider: provider, clock: clock)
        let deniedRetry = await restartedService.handle(try await generationRequest(
            from: fixture,
            service: restartedService,
            token: token,
            idempotencyKey: "sqlite-retry-budget"
        ))
        XCTAssertEqual(deniedRetry.statusCode, 429)
        XCTAssertEqual(try errorCode(deniedRetry), "quota_exceeded")
        clock.advance(by: 61)
        let allowedAfterWindow = await restartedService.handle(try await generationRequest(
            from: fixture,
            service: restartedService,
            token: token,
            idempotencyKey: "sqlite-retry-budget"
        ))
        XCTAssertEqual(allowedAfterWindow.statusCode, 200)
        let calls = await provider.callCount()
        XCTAssertEqual(calls, 6)
    }

    func testDefaultHourlyAndDailyLimitsArePerInstallation() async throws {
        let fixture = try generationFixture()
        let intent = String(decoding: try fixtureBody("ready", fixture: fixture), as: UTF8.self)
        let clock = ManualGenerationClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        let harness = try await makeHarness(provider: ScriptedIntentProvider(intent: intent), clock: clock)

        for index in 0..<10 {
            let response = await harness.service.handle(try await generationRequest(
                from: fixture,
                service: harness.service,
                token: harness.token,
                idempotencyKey: "hour-\(index)"
            ))
            XCTAssertEqual(response.statusCode, 200)
            clock.advance(by: 61)
        }
        let hourly = await harness.service.handle(try await generationRequest(from: fixture, service: harness.service, token: harness.token, idempotencyKey: "hour-limit"))
        XCTAssertEqual(hourly.statusCode, 429)

        clock.advance(by: 3_601)
        for index in 10..<30 {
            let response = await harness.service.handle(try await generationRequest(
                from: fixture,
                service: harness.service,
                token: harness.token,
                idempotencyKey: "day-\(index)"
            ))
            XCTAssertEqual(response.statusCode, 200)
            if index % 10 == 9 { clock.advance(by: 3_601) }
            else { clock.advance(by: 61) }
        }
        let daily = await harness.service.handle(try await generationRequest(from: fixture, service: harness.service, token: harness.token, idempotencyKey: "day-limit"))
        XCTAssertEqual(daily.statusCode, 429)
        XCTAssertEqual(try errorCode(daily), "quota_exceeded")
    }

    func testQuotaStateSurvivesServiceAndSQLiteStoreRecreation() async throws {
        let fixture = try generationFixture()
        let intent = String(decoding: try fixtureBody("ready", fixture: fixture), as: UTF8.self)
        let databaseURL = try testDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let clock = ManualGenerationClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        let token = try await seedSQLiteQuota(
            databaseURL: databaseURL,
            fixture: fixture,
            intent: intent,
            clock: clock
        )

        let secondStore = try SQLiteGenerationServiceStore(databaseURL: databaseURL)
        let restartedService = makeService(
            store: secondStore,
            provider: ScriptedIntentProvider(intent: intent),
            clock: clock
        )
        let afterRestart = await restartedService.handle(try await generationRequest(from: fixture, service: restartedService, token: token, idempotencyKey: "restart-six"))
        XCTAssertEqual(afterRestart.statusCode, 429)
        XCTAssertEqual(try errorCode(afterRestart), "quota_exceeded")
    }

    private func seedSQLiteQuota(
        databaseURL: URL,
        fixture: [String: Any],
        intent: String,
        clock: ManualGenerationClock
    ) async throws -> String {
        let store = try SQLiteGenerationServiceStore(databaseURL: databaseURL)
        let service = makeService(store: store, provider: ScriptedIntentProvider(intent: intent), clock: clock)
        let token = try await enroll(service)
        for index in 0..<5 {
            let response = await service.handle(
                try await generationRequest(from: fixture, service: service, token: token, idempotencyKey: "restart-\(index)")
            )
            XCTAssertEqual(response.statusCode, 200)
        }
        return token
    }

    private func makeHarness(
        provider: ScriptedIntentProvider? = nil,
        clock: ManualGenerationClock = ManualGenerationClock(now: Date(timeIntervalSince1970: 1_800_000_000))
    ) async throws -> Harness {
        let store = InMemoryGenerationServiceStore()
        let generationProvider: ScriptedIntentProvider
        if let provider {
            generationProvider = provider
        } else {
            let fixtureIntent = String(decoding: try fixtureBody("ready", fixture: generationFixture()), as: UTF8.self)
            generationProvider = ScriptedIntentProvider(intent: fixtureIntent)
        }
        let service = makeService(store: store, provider: generationProvider, clock: clock)
        return Harness(service: service, token: try await enroll(service), provider: generationProvider, store: store, clock: clock)
    }

    private func makeService(
        store: any GenerationServiceStore,
        provider: any GenerationIntentProviding,
        clock: ManualGenerationClock,
        attestationVerifier: any AppAttestVerifying = FixtureAttestationVerifier()
    ) -> GenerationService {
        GenerationService(
            configuration: GenerationServiceConfiguration(
                expectedAppIdentifier: "TESTTEAMID.com.craftberry.app",
                appAttestEnvironment: .development
            ),
            store: store,
            attestationVerifier: attestationVerifier,
            intentProvider: provider,
            clock: clock
        )
    }

    private func enroll(_ service: GenerationService) async throws -> String {
        let challenge = await service.handle(.init(method: "POST", path: "/v1/session/challenge", body: Data("{}".utf8)))
        XCTAssertEqual(challenge.statusCode, 200)
        let challengeJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: challenge.body) as? [String: Any])
        let challengeID = try XCTUnwrap(challengeJSON["challengeID"] as? String)
        let enrollment = try JSONSerialization.data(withJSONObject: [
            "challengeID": challengeID,
            "keyID": "fixture-app-attest-key-id",
            "attestationObject": Data("valid-attestation-fixture".utf8).base64EncodedString()
        ])
        let response = await service.handle(.init(method: "POST", path: "/v1/session/enroll", body: enrollment))
        XCTAssertEqual(response.statusCode, 200)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        return try XCTUnwrap(body["sessionToken"] as? String)
    }

    private func generationRequest(
        from fixture: [String: Any],
        service: GenerationService,
        token: String,
        idempotencyKey: String
    ) async throws -> GenerationServiceRequest {
        let body = try fixtureRequestBody(fixture)
        return try await makeRequest(body: body, service: service, token: token, idempotencyKey: idempotencyKey)
    }

    private func makeRequest(
        _ body: TestGenerationRequest,
        service: GenerationService,
        token: String,
        idempotencyKey: String
    ) async throws -> GenerationServiceRequest {
        let json = try JSONEncoder().encode(body)
        return try await makeRequest(body: json, service: service, token: token, idempotencyKey: idempotencyKey)
    }

    private func makeRequest(
        body: Data,
        service: GenerationService,
        token: String,
        idempotencyKey: String
    ) async throws -> GenerationServiceRequest {
        let challengeResponse = await service.handle(.init(method: "POST", path: "/v1/session/challenge", body: Data("{}".utf8)))
        XCTAssertEqual(challengeResponse.statusCode, 200)
        let challengeJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: challengeResponse.body) as? [String: Any])
        let challengeID = try XCTUnwrap(challengeJSON["challengeID"] as? String)
        let challenge = try XCTUnwrap(challengeJSON["challenge"] as? String)
        let clientData = GenerationAssertionClientData(
            challengeID: challengeID,
            challenge: challenge,
            requestBodySHA256: Self.base64URL(Data(SHA256.hash(data: body))),
            idempotencyKey: idempotencyKey
        )
        let encodedClientData = try clientData.canonicalData()
        let counter = await Self.assertionSequence.next()
        var bigEndianCounter = counter.bigEndian
        let assertionObject = withUnsafeBytes(of: &bigEndianCounter) { Data($0) }
        return .init(
            method: "POST",
            path: "/v1/generate",
            headers: [
                "Authorization": "Bearer \(token)",
                "Idempotency-Key": idempotencyKey,
                "App-Attest-Challenge-ID": challengeID,
                "App-Attest-Client-Data": encodedClientData.base64EncodedString(),
                "App-Attest-Assertion": assertionObject.base64EncodedString()
            ],
            body: body
        )
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generationFixture() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "GenerationV1", withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func fixtureRequestBody(_ fixture: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: XCTUnwrap(fixture["request"]))
    }

    private func fixtureBody(_ name: String, fixture: [String: Any]) throws -> Data {
        let responses = try XCTUnwrap(fixture["responses"] as? [String: [String: Any]])
        let scenario = try XCTUnwrap(responses[name])
        return try JSONSerialization.data(withJSONObject: XCTUnwrap(scenario["body"]))
    }

    private func jsonValue(_ data: Data) throws -> Data {
        try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: data), options: [.sortedKeys])
    }

    private func errorCode(_ response: GenerationServiceResponse) throws -> String {
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: response.body) as? [String: String])
        return try XCTUnwrap(body["error"])
    }

    private func testDatabaseURL() throws -> URL {
        let scratch = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(path: ".scratch", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        return scratch.appending(path: "generation-service-\(UUID().uuidString).sqlite")
    }

    private func sqliteCount(_ sql: String, at url: URL) throws -> Int {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw SQLiteGenerationServiceStoreError.database("Unable to open test database.")
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteGenerationServiceStoreError.database(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw SQLiteGenerationServiceStoreError.database(String(cString: sqlite3_errmsg(database)))
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func executeSQLite(_ sql: String, at url: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw SQLiteGenerationServiceStoreError.database("Unable to open test database.")
        }
        defer { sqlite3_close(database) }
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorPointer)
            throw SQLiteGenerationServiceStoreError.database(message)
        }
    }

    private func removeDatabase(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
    }

    private static func token() -> String {
        Data(repeating: 0xA5, count: 32).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private struct Harness {
    let service: GenerationService
    let token: String
    let provider: ScriptedIntentProvider
    let store: any GenerationServiceStore
    let clock: ManualGenerationClock
}

private actor ScriptedIntentProvider: GenerationIntentProviding {
    private let intent: String
    private var failuresRemaining: Int
    private var calls = 0

    init(intent: String = "", initialFailures: Int = 0) {
        self.intent = intent
        failuresRemaining = initialFailures
    }

    func generateIntent(prompt: String) async throws -> String {
        calls += 1
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw TestProviderError.unavailable
        }
        return intent
    }

    func callCount() -> Int { calls }
}

private actor BlockingIntentProvider: GenerationIntentProviding {
    private let intent: String
    private var calls = 0
    private var hasStarted = false
    private var wasReleased = false
    private var completion: CheckedContinuation<Void, Never>?

    init(intent: String) { self.intent = intent }

    func generateIntent(prompt: String) async throws -> String {
        calls += 1
        guard calls == 1 else { return intent }
        hasStarted = true
        await withCheckedContinuation { continuation in
            if wasReleased {
                continuation.resume()
            } else {
                completion = continuation
            }
        }
        return intent
    }

    func waitUntilStarted(timeoutNanoseconds: UInt64) async -> Bool {
        let deadline = ContinuousClock.now + .nanoseconds(Int64(timeoutNanoseconds))
        while ContinuousClock.now < deadline {
            if hasStarted { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return hasStarted
    }

    func release() {
        wasReleased = true
        completion?.resume()
        completion = nil
    }

    func callCount() -> Int { calls }
}

private enum TestProviderError: Error {
    case unavailable
}

private struct FixtureAttestationVerifier: AppAttestVerifying {
    func verifyAttestation(
        object: Data,
        keyID: String,
        challenge: Data,
        expectedAppIdentifier: String,
        expectedEnvironment: AppAttestEnvironment
    ) async throws -> VerifiedAppAttestKey {
        guard String(data: object, encoding: .utf8) == "valid-attestation-fixture" else {
            throw AppleAppAttestVerificationError.malformedObject
        }
        return VerifiedAppAttestKey(
            keyID: keyID,
            publicKey: Data("public-key".utf8),
            appIdentifier: expectedAppIdentifier,
            environment: expectedEnvironment,
            bundleVersion: "1.0",
            receipt: Data("fixture-receipt".utf8)
        )
    }

    func verifyAssertion(
        object: Data,
        clientData: Data,
        credential: StoredAppAttestCredential,
        expectedAppIdentifier: String,
        expectedEnvironment: AppAttestEnvironment
    ) async throws -> VerifiedAppAttestAssertion {
        guard object.count == 4 else { throw AppleAppAttestVerificationError.malformedObject }
        let counter = object.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return VerifiedAppAttestAssertion(counter: counter)
    }
}

private struct ChallengeExpiringFixtureVerifier: AppAttestVerifying {
    let clock: ManualGenerationClock

    func verifyAttestation(
        object: Data,
        keyID: String,
        challenge: Data,
        expectedAppIdentifier: String,
        expectedEnvironment: AppAttestEnvironment
    ) async throws -> VerifiedAppAttestKey {
        let verified = try await FixtureAttestationVerifier().verifyAttestation(
            object: object,
            keyID: keyID,
            challenge: challenge,
            expectedAppIdentifier: expectedAppIdentifier,
            expectedEnvironment: expectedEnvironment
        )
        clock.advance(by: 301)
        return verified
    }

    func verifyAssertion(
        object: Data,
        clientData: Data,
        credential: StoredAppAttestCredential,
        expectedAppIdentifier: String,
        expectedEnvironment: AppAttestEnvironment
    ) async throws -> VerifiedAppAttestAssertion {
        try await FixtureAttestationVerifier().verifyAssertion(
            object: object,
            clientData: clientData,
            credential: credential,
            expectedAppIdentifier: expectedAppIdentifier,
            expectedEnvironment: expectedEnvironment
        )
    }
}

private actor TestAssertionSequence {
    private var counter: UInt32 = 0

    func next() -> UInt32 {
        counter &+= 1
        return counter
    }
}

private final class ManualGenerationClock: GenerationServiceClock, @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(now: Date) { date = now }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        date.addTimeInterval(seconds)
        lock.unlock()
    }
}

private struct TestGenerationRequest: Codable {
    let intentVersion: Int
    let profileID: String
    var prompt: String
}

private actor InstallationLookupFailingStore: GenerationServiceStore {
    private let backing = InMemoryGenerationServiceStore()

    func createEnrollmentChallenge(_ challenge: StoredEnrollmentChallenge, now: Date) async throws {
        try await backing.createEnrollmentChallenge(challenge, now: now)
    }

    func enrollmentChallenge(id: String, now: Date) async throws -> StoredEnrollmentChallenge? {
        try await backing.enrollmentChallenge(id: id, now: now)
    }

    func registerInstallation(
        challengeID: String,
        registration: GenerationInstallationRegistration,
        tokenDigest: Data,
        now: Date
    ) async throws -> Bool {
        try await backing.registerInstallation(
            challengeID: challengeID,
            registration: registration,
            tokenDigest: tokenDigest,
            now: now
        )
    }

    func installationID(forTokenDigest digest: Data) async throws -> UUID? {
        throw TestProviderError.unavailable
    }

    func appAttestCredential(for installationID: UUID) async throws -> StoredAppAttestCredential? {
        try await backing.appAttestCredential(for: installationID)
    }

    func appAttestReceipt(for installationID: UUID) async throws -> Data? {
        try await backing.appAttestReceipt(for: installationID)
    }

    func consumeAppAttestAssertion(
        challengeID: String,
        installationID: UUID,
        expectedCounter: UInt32,
        newCounter: UInt32,
        now: Date
    ) async throws -> Bool {
        try await backing.consumeAppAttestAssertion(
            challengeID: challengeID,
            installationID: installationID,
            expectedCounter: expectedCounter,
            newCounter: newCounter,
            now: now
        )
    }

    func reserveGeneration(
        installationID: UUID,
        idempotencyKey: String,
        requestFingerprint: Data,
        now: Date,
        quota: GenerationQuotaPolicy
    ) async throws -> GenerationReservation {
        try await backing.reserveGeneration(
            installationID: installationID,
            idempotencyKey: idempotencyKey,
            requestFingerprint: requestFingerprint,
            now: now,
            quota: quota
        )
    }

    func completeGeneration(
        installationID: UUID,
        idempotencyKey: String,
        reservationID: UUID,
        response: Data,
        now: Date
    ) async throws -> Bool {
        try await backing.completeGeneration(
            installationID: installationID,
            idempotencyKey: idempotencyKey,
            reservationID: reservationID,
            response: response,
            now: now
        )
    }

    func markGenerationRetryable(
        installationID: UUID,
        idempotencyKey: String,
        reservationID: UUID,
        now: Date
    ) async throws -> Bool {
        try await backing.markGenerationRetryable(
            installationID: installationID,
            idempotencyKey: idempotencyKey,
            reservationID: reservationID,
            now: now
        )
    }
}
