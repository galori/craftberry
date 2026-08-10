import Foundation
import XCTest
#if canImport(CraftberryCore)
@testable import CraftberryCore
#else
@testable import Craftberry
#endif

final class HardeningTests: XCTestCase {

    // MARK: - Backend

    func testBackendConfigurationIsConfiguredRequiresHttpsAndToken() {
        let good = BackendConfiguration(baseURL: URL(string: "https://api.craftberry.example.com")!, authToken: "1234567890123456")
        XCTAssertTrue(good.isConfigured)
        let http = BackendConfiguration(baseURL: URL(string: "http://api.craftberry.example.com")!, authToken: "1234567890123456")
        XCTAssertFalse(http.isConfigured)
        let shortToken = BackendConfiguration(baseURL: URL(string: "https://api.craftberry.example.com")!, authToken: "short")
        XCTAssertTrue(shortToken.isConfigured) // isConfigured only checks non-empty; distributable validates length
        let empty = BackendConfiguration.empty
        XCTAssertFalse(empty.isConfigured)
    }

    func testBackendConfigurationValidateForDistributableBuild() {
        let good = BackendConfiguration(baseURL: URL(string: "https://api.craftberry.example.com")!, authToken: "1234567890123456")
        XCTAssertNoThrow(try good.validateForDistributableBuild())
        XCTAssertThrowsError(try BackendConfiguration.empty.validateForDistributableBuild())
        let http = BackendConfiguration(baseURL: URL(string: "http://api.craftberry.example.com")!, authToken: "1234567890123456")
        XCTAssertThrowsError(try http.validateForDistributableBuild())
        let short = BackendConfiguration(baseURL: URL(string: "https://api.craftberry.example.com")!, authToken: "short")
        XCTAssertThrowsError(try short.validateForDistributableBuild())
    }

    func testBackendClientAuthorizedRequestAddsBearerHeader() throws {
        let config = BackendConfiguration(baseURL: URL(string: "https://api.craftberry.example.com")!, authToken: "token123456789012")
        let client = BackendClient(configuration: config)
        let url = URL(string: "https://api.craftberry.example.com/v1/generate")!
        let req = try client.authorizedRequest(for: url)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer token123456789012")
    }

    func testBackendClientRejectsMissingConfiguration() {
        let client = BackendClient(configuration: .empty)
        XCTAssertThrowsError(try client.authorizedRequest(for: URL(string: "https://api.example.com")!))
        XCTAssertThrowsError(try client.validateForDistributableBuild())
    }

    func testBackendClientRejectsURLOutsideBase() throws {
        let config = BackendConfiguration(baseURL: URL(string: "https://api.craftberry.example.com")!, authToken: "token12345678901234")
        let client = BackendClient(configuration: config)
        XCTAssertThrowsError(try client.authorizedRequest(for: URL(string: "https://evil.example.com/steal")!))
    }

    // MARK: - Quota

    func testQuotaGateEnforcesHourlyQuota() async throws {
        let clock = ManualQuotaClock(now: Date())
        let gate = QuotaGate(policy: QuotaPolicy(maxGenerationsPerHour: 2, maxGenerationsPerDay: 100, maxPromptCharacters: 1000, abuseThresholdPerMinute: 100), clock: clock)
        try await gate.checkAndRecord(prompt: "a")
        try await gate.checkAndRecord(prompt: "b")
        do {
            try await gate.checkAndRecord(prompt: "c")
            XCTFail("Should have thrown quota exceeded")
        } catch let error as QuotaError {
            if case .quotaExceeded = error {} else { XCTFail("Wrong error \(error)") }
        }
    }

    func testQuotaGateEnforcesAbuseThreshold() async throws {
        let clock = ManualQuotaClock(now: Date())
        let gate = QuotaGate(policy: QuotaPolicy(maxGenerationsPerHour: 100, maxGenerationsPerDay: 1000, maxPromptCharacters: 1000, abuseThresholdPerMinute: 2), clock: clock)
        try await gate.checkAndRecord(prompt: "a")
        try await gate.checkAndRecord(prompt: "b")
        do {
            try await gate.checkAndRecord(prompt: "c")
            XCTFail("Should have thrown abuse")
        } catch let error as QuotaError {
            if case .abuseDetected = error {} else { XCTFail("Wrong error \(error)") }
        }
    }

    func testQuotaGateRejectsPromptTooLong() async {
        let gate = QuotaGate(policy: QuotaPolicy(maxPromptCharacters: 5))
        do {
            try await gate.canGenerate(prompt: "123456")
            XCTFail("Should throw promptTooLong")
        } catch let error as QuotaError {
            if case .promptTooLong(let limit) = error { XCTAssertEqual(limit, 5) } else { XCTFail("Wrong error") }
        } catch { XCTFail("Wrong error") }
    }

    func testQuotaGateResetClearsCounts() async throws {
        let gate = QuotaGate(policy: QuotaPolicy(maxGenerationsPerHour: 1, maxGenerationsPerDay: 10, abuseThresholdPerMinute: 10))
        try await gate.checkAndRecord(prompt: "a")
        await gate.reset()
        try await gate.checkAndRecord(prompt: "b")
        let count = await gate.count
        XCTAssertEqual(count, 1)
    }

    func testQuotaGatedClientBlocksBeforeWrapping() async throws {
        let gate = QuotaGate(policy: QuotaPolicy(maxGenerationsPerHour: 1, maxGenerationsPerDay: 10, maxPromptCharacters: 1000, abuseThresholdPerMinute: 10))
        let fake = FakeLLMClient(generation: ProjectGeneration(outcome: .unsupported, message: "no", project: nil))
        let gated = QuotaGatedLLMClient(wrapping: fake, gate: gate)
        _ = try await gated.generateProject(from: "first")
        do {
            _ = try await gated.generateProject(from: "second")
            XCTFail("Should have thrown quota")
        } catch let error as QuotaError {
            if case .quotaExceeded = error {} else { XCTFail("Wrong error \(error)") }
        }
        let calls = await fake.calls
        XCTAssertEqual(calls, 1)
    }

    // MARK: - Telemetry

    func testTelemetryDoesNotRecordWhenOptedOut() {
        let storage = InMemoryTelemetryStorage(optedIn: false)
        let sink = InMemoryTelemetrySink()
        let manager = TelemetryManager(storage: storage, sink: sink)
        manager.record(name: "generate.tapped")
        XCTAssertTrue(sink.events.isEmpty)
    }

    func testTelemetryRecordsWhenOptedIn() {
        let storage = InMemoryTelemetryStorage(optedIn: true)
        let sink = InMemoryTelemetrySink()
        let manager = TelemetryManager(storage: storage, sink: sink)
        manager.record(name: "generate.succeeded", properties: ["outcome": "ready"])
        XCTAssertEqual(sink.events.count, 1)
        XCTAssertEqual(sink.events.first?.name, "generate.succeeded")
    }

    func testTelemetryOptInToggle() {
        let storage = InMemoryTelemetryStorage(optedIn: false)
        let sink = InMemoryTelemetrySink()
        let manager = TelemetryManager(storage: storage, sink: sink)
        XCTAssertFalse(manager.isOptedIn)
        manager.setOptedIn(true)
        XCTAssertTrue(manager.isOptedIn)
        manager.record(name: "x")
        XCTAssertEqual(sink.events.count, 1)
        manager.setOptedIn(false)
        manager.record(name: "y")
        XCTAssertEqual(sink.events.count, 1)
    }

    // MARK: - Privacy

    func testPrivacyDisclosureCurrentIsValidForDistribution() {
        XCTAssertNoThrow(try PrivacyDisclosure.current.validateForDistributableBuild())
    }

    func testPrivacyDisclosureEmptyFailsValidation() {
        let empty = PrivacyDisclosure(title: "", summary: "", dataCollected: [], dataNotCollected: [], retentionSummary: "", contactURL: nil)
        XCTAssertThrowsError(try empty.validateForDistributableBuild())
    }

    func testDistributableValidatorRequiresBackendAndPrivacy() {
        let validator = DistributableBuildValidator()
        let goodBackend = BackendConfiguration(baseURL: URL(string: "https://api.craftberry.example.com")!, authToken: "1234567890123456")
        XCTAssertNoThrow(try validator.validate(backend: goodBackend, privacy: .current))
        XCTAssertThrowsError(try validator.validate(backend: .empty, privacy: .current)) { error in
            XCTAssertEqual(error as? DistributableBuildError, .missingBackendConfiguration)
        }
        let badPrivacy = PrivacyDisclosure(title: "", summary: "", dataCollected: [], dataNotCollected: [], retentionSummary: "", contactURL: nil)
        XCTAssertThrowsError(try validator.validate(backend: goodBackend, privacy: badPrivacy))
    }

    // MARK: - Retention

    func testRetentionKeepsLatestFivePerProject() {
        let policy = SidecarRetentionPolicy(maxBuildsPerProject: 2, maxAgeDays: 365)
        let pid = UUID()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let builds = (1...5).map { i in SidecarBuildMetadata(projectID: pid, version: VersionTriplet(major: 1, minor: 0, patch: i), createdAt: now.addingTimeInterval(Double(i))) }
        let prune = policy.buildsToPrune(builds: builds, now: now.addingTimeInterval(100))
        XCTAssertEqual(prune.count, 3)
        let keep = policy.buildsToKeep(builds: builds, now: now.addingTimeInterval(100))
        XCTAssertEqual(keep.map(\.version.patch).sorted(), [4, 5])
    }

    func testRetentionPrunesByAge() {
        let policy = SidecarRetentionPolicy(maxBuildsPerProject: 10, maxAgeDays: 1)
        let pid = UUID()
        let now = Date()
        let old = SidecarBuildMetadata(projectID: pid, version: VersionTriplet(major: 1, minor: 0, patch: 0), createdAt: now.addingTimeInterval(-2 * 86_400))
        let fresh = SidecarBuildMetadata(projectID: pid, version: VersionTriplet(major: 1, minor: 0, patch: 1), createdAt: now)
        let prune = policy.buildsToPrune(builds: [old, fresh], now: now)
        XCTAssertTrue(prune.contains(old))
        XCTAssertFalse(prune.contains(fresh))
    }

    func testRetentionIsolatedPerProject() {
        let policy = SidecarRetentionPolicy(maxBuildsPerProject: 1, maxAgeDays: 365)
        let a = UUID(); let b = UUID()
        let now = Date(timeIntervalSince1970: 2_000_000)
        let builds = [
            SidecarBuildMetadata(projectID: a, version: VersionTriplet(major: 1, minor: 0, patch: 0), createdAt: now),
            SidecarBuildMetadata(projectID: a, version: VersionTriplet(major: 1, minor: 0, patch: 1), createdAt: now.addingTimeInterval(10)),
            SidecarBuildMetadata(projectID: b, version: VersionTriplet(major: 1, minor: 0, patch: 0), createdAt: now)
        ]
        let prune = policy.buildsToPrune(builds: builds, now: now.addingTimeInterval(20))
        XCTAssertEqual(prune.count, 1)
        XCTAssertTrue(prune.contains { $0.projectID == a && $0.version.patch == 0 })
    }

    // MARK: - Profile Migration

    func testMigrationGateDetectsSchemaAndProfileMismatch() throws {
        let gate = ProfileMigrationGate()
        let project = try AddOnProject.sword(displayName: "Test Sword", originalPrompt: "prompt", identity: testIdentity())
        XCTAssertFalse(gate.requiresMigration(for: project))
        try gate.validate(project)

        let oldSchema = AddOnProject(schemaVersion: 1, id: project.id, namespace: project.namespace, displayName: project.displayName, shortDescription: project.shortDescription, packUUIDs: project.packUUIDs, buildVersion: project.buildVersion, targetProfileID: project.targetProfileID, originalPrompt: project.originalPrompt, content: project.content)
        XCTAssertTrue(gate.requiresMigration(for: oldSchema))
        XCTAssertThrowsError(try gate.validate(oldSchema))

        let wrongProfile = AddOnProject(schemaVersion: project.schemaVersion, id: project.id, namespace: project.namespace, displayName: project.displayName, shortDescription: project.shortDescription, packUUIDs: project.packUUIDs, buildVersion: project.buildVersion, targetProfileID: "old-profile", originalPrompt: project.originalPrompt, content: project.content)
        XCTAssertTrue(gate.requiresMigration(for: wrongProfile))
        XCTAssertThrowsError(try gate.validate(wrongProfile))
    }

    func testMigrationGateMigratesOldSchema() throws {
        let gate = ProfileMigrationGate()
        let project = try AddOnProject.sword(displayName: "Test Sword", originalPrompt: "prompt", identity: testIdentity())
        let old = AddOnProject(schemaVersion: 2, id: project.id, namespace: project.namespace, displayName: project.displayName, shortDescription: project.shortDescription, packUUIDs: project.packUUIDs, buildVersion: project.buildVersion, targetProfileID: project.targetProfileID, originalPrompt: project.originalPrompt, content: project.content)
        let migrated = try gate.migratedProject(old)
        XCTAssertEqual(migrated.schemaVersion, AddOnProject.currentSchemaVersion)
        XCTAssertNoThrow(try gate.validate(migrated))
    }

    func testMigrationGateMigratesProfileID() throws {
        let gate = ProfileMigrationGate()
        let project = try AddOnProject.sword(displayName: "Test Sword", originalPrompt: "prompt", identity: testIdentity())
        let oldProfile = AddOnProject(schemaVersion: project.schemaVersion, id: project.id, namespace: project.namespace, displayName: project.displayName, shortDescription: project.shortDescription, packUUIDs: project.packUUIDs, buildVersion: project.buildVersion, targetProfileID: "bedrock-stable-1.0.0", originalPrompt: project.originalPrompt, content: project.content)
        let migrated = try gate.migratedProject(oldProfile)
        XCTAssertEqual(migrated.targetProfileID, BedrockContentProfile.current.id)
        XCTAssertNoThrow(try gate.validate(migrated))
    }

    func testMigrationGateRejectsFutureSchema() {
        let gate = ProfileMigrationGate()
        let project = AddOnProject(schemaVersion: 99, id: UUID(), namespace: "craftberry", displayName: "Future", shortDescription: "x", packUUIDs: PackUUIDs(behaviorHeader: UUID(), behaviorModule: UUID(), resourceHeader: UUID(), resourceModule: UUID()), buildVersion: VersionTriplet(major: 1, minor: 0, patch: 0), targetProfileID: BedrockContentProfile.current.id, originalPrompt: "p", content: [])
        XCTAssertThrowsError(try gate.validate(project))
        XCTAssertThrowsError(try gate.migratedProject(project))
    }

    // MARK: - Helpers

    private func testIdentity() -> AddOnProjectIdentity {
        AddOnProjectIdentity(
            projectID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            namespace: "craftberry",
            contentSuffix: "a1b2c3",
            packUUIDs: PackUUIDs(
                behaviorHeader: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                behaviorModule: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                resourceHeader: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                resourceModule: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
            )
        )
    }
}

private actor FakeLLMClient: LLMClient {
    let generation: ProjectGeneration
    var calls = 0
    init(generation: ProjectGeneration) { self.generation = generation }
    func generateProject(from prompt: String) async throws -> ProjectGeneration {
        calls += 1
        return generation
    }
}

private final class ManualQuotaClock: QuotaClock, @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date
    init(now: Date) { _now = now }
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return _now }
    func advance(by interval: TimeInterval) { lock.lock(); defer { lock.unlock() }; _now = _now.addingTimeInterval(interval) }
}
