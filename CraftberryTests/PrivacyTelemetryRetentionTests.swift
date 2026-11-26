import Foundation
import XCTest
#if canImport(CraftberryCore)
@testable import CraftberryCore
#else
@testable import Craftberry
#endif

final class PrivacyTelemetryRetentionTests: XCTestCase {
    func testPlaceholderPrivacyContactFailsDistributionValidation() throws {
        let privacy = PrivacyDisclosure.configured(contactURLString: "https://craftberry.example.com/privacy")

        XCTAssertThrowsError(try privacy.validateForDistributableBuild())
        XCTAssertThrowsError(try PrivacyDisclosure.configured(contactURLString: "").validateForDistributableBuild())
        XCTAssertThrowsError(try PrivacyDisclosure.configured(contactURLString: "$(CRAFTBERRY_PRIVACY_CONTACT_URL)").validateForDistributableBuild())
        XCTAssertThrowsError(try PrivacyDisclosure.configured(contactURLString: "https://yourdomain.com/privacy").validateForDistributableBuild())
    }

    func testConfiguredPrivacyContactPassesDistributionValidation() throws {
        let privacy = PrivacyDisclosure.configured(contactURLString: "https://privacy-contact.craftberry.com/contact")

        XCTAssertNoThrow(try privacy.validateForDistributableBuild())
    }

    func testTelemetryDropsPromptArtworkAndUnrecognizedFields() {
        let sink = InMemoryTelemetrySink()
        let manager = TelemetryManager(storage: InMemoryTelemetryStorage(optedIn: true), sink: sink)
        manager.record(
            name: "generation.succeeded",
            properties: [
                "outcome": "ready",
                "prompt": "A personal prompt",
                "artwork": "private-image.png",
                "displayName": "My private sword"
            ]
        )
        manager.record(name: "A prompt that must never be an event name")

        XCTAssertEqual(sink.events.count, 1)
        XCTAssertEqual(sink.events.first?.name, "generation.succeeded")
        XCTAssertEqual(sink.events.first?.properties, ["outcome": "ready"])
    }

    func testOptOutPurgesExistingTelemetryAndPreventsNewRecords() {
        let sink = InMemoryTelemetrySink()
        let storage = InMemoryTelemetryStorage(optedIn: true)
        let manager = TelemetryManager(storage: storage, sink: sink)
        manager.record(name: "generation.requested")
        XCTAssertEqual(sink.events.count, 1)

        manager.setOptedIn(false)
        manager.record(name: "generation.succeeded")

        XCTAssertTrue(sink.events.isEmpty)
    }

    func testTelemetryExpiresEventsOlderThanThirtyDaysAndCanBePurged() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let storage = InMemoryTelemetryEventStorage()
        let sink = PersistentTelemetrySink(storage: storage, retentionDays: 30, clock: { now })
        sink.record(TelemetryEvent(name: "generation.requested", timestamp: now.addingTimeInterval(-31 * 86_400)))
        sink.record(TelemetryEvent(name: "generation.succeeded", timestamp: now))

        XCTAssertEqual(sink.events(asOf: now).map(\.name), ["generation.succeeded"])
        sink.purge()
        XCTAssertTrue(sink.events(asOf: now).isEmpty)
    }

    func testUserDefaultsTelemetryStoragePersistsOnlySafeEventsAndPurges() throws {
        let suiteName = "CraftberryTelemetryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storage = UserDefaultsTelemetryEventStorage(key: "events", defaults: defaults)
        let sink = PersistentTelemetrySink(storage: storage)

        sink.record(TelemetryEvent(
            name: "generation.failed",
            properties: ["outcome": "failed", "prompt": "A prompt that stays private", "artwork": "private.png"]
        ))

        XCTAssertEqual(storage.load().first?.properties, ["outcome": "failed"])
        let rawData = try XCTUnwrap(defaults.data(forKey: "events"))
        let rawStorage = try XCTUnwrap(String(data: rawData, encoding: .utf8))
        XCTAssertFalse(rawStorage.contains("A prompt that stays private"))
        XCTAssertFalse(rawStorage.contains("private.png"))
        sink.purge()
        XCTAssertTrue(storage.load().isEmpty)
    }

    func testSidecarRetentionPrunesBuildDirectoriesAndPreservesSidecarAndRecentBuilds() throws {
        let root = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileManager = FileManager.default
        let projectID = UUID()
        let projectDirectory = root.appending(path: projectID.uuidString.lowercased(), directoryHint: .isDirectory)
        let buildsDirectory = projectDirectory.appending(path: "builds", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: buildsDirectory, withIntermediateDirectories: true)
        let sidecarURL = projectDirectory.appending(path: "project.json")
        try Data("sidecar".utf8).write(to: sidecarURL)
        let now = Date(timeIntervalSince1970: 2_500_000)

        for patch in 1...6 {
            let versionDirectory = buildsDirectory.appending(path: "1.0.\(patch)", directoryHint: .isDirectory)
            try fileManager.createDirectory(at: versionDirectory, withIntermediateDirectories: true)
            try Data("addon".utf8).write(to: versionDirectory.appending(path: "fixture.mcaddon"))
            try writeBuildDate(now.addingTimeInterval(Double(patch)), to: versionDirectory)
        }

        let removed = try SidecarRetentionService().prune(in: root, now: now.addingTimeInterval(10))

        XCTAssertEqual(removed.map(\.lastPathComponent), ["1.0.1"])
        XCTAssertTrue(fileManager.fileExists(atPath: sidecarURL.path))
        XCTAssertFalse(fileManager.fileExists(atPath: buildsDirectory.appending(path: "1.0.1").path))
        for patch in 2...6 {
            XCTAssertTrue(fileManager.fileExists(atPath: buildsDirectory.appending(path: "1.0.\(patch)").path))
        }
    }

    func testSidecarRetentionExpiresOldBuildAndOnlyPrunesInsideBuildsDirectory() throws {
        let root = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileManager = FileManager.default
        let projectID = UUID()
        let projectDirectory = root.appending(path: projectID.uuidString.lowercased(), directoryHint: .isDirectory)
        let buildsDirectory = projectDirectory.appending(path: "builds", directoryHint: .isDirectory)
        let oldBuild = buildsDirectory.appending(path: "2.1.0", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: oldBuild, withIntermediateDirectories: true)
        try Data("world".utf8).write(to: oldBuild.appending(path: "world.mcworld"))
        try writeBuildDate(Date(timeIntervalSince1970: 1_000_000), to: oldBuild)
        let unrelated = projectDirectory.appending(path: "exports", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: unrelated, withIntermediateDirectories: true)
        let unrelatedExport = unrelated.appending(path: "saved.mcaddon")
        try Data("keep".utf8).write(to: unrelatedExport)

        let removed = try SidecarRetentionService().prune(in: root, now: Date(timeIntervalSince1970: 4_000_000))

        XCTAssertEqual(removed, [oldBuild])
        XCTAssertFalse(fileManager.fileExists(atPath: oldBuild.path))
        XCTAssertTrue(fileManager.fileExists(atPath: unrelatedExport.path))
    }

    func testCompilerAutomaticallyAppliesFiveBuildLimit() throws {
        let root = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = AddOnProjectIdentity.generate()
        let base = try AddOnProject.sword(
            displayName: "Retention Sword",
            originalPrompt: "A test sword",
            identity: identity
        )
        let compiler = BedrockAddOnCompiler()

        for patch in 1...6 {
            let project = AddOnProject(
                id: base.id,
                namespace: base.namespace,
                displayName: base.displayName,
                shortDescription: base.shortDescription,
                packUUIDs: base.packUUIDs,
                buildVersion: VersionTriplet(major: 1, minor: 0, patch: patch),
                targetProfileID: base.targetProfileID,
                originalPrompt: base.originalPrompt,
                content: base.content
            )
            _ = try compiler.compile(project: project, profile: .current, outputDirectory: root)
        }

        let builds = root
            .appending(path: identity.projectID.uuidString.lowercased(), directoryHint: .isDirectory)
            .appending(path: "builds", directoryHint: .isDirectory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: builds.appending(path: "1.0.1").path))
        for patch in 2...6 {
            XCTAssertTrue(FileManager.default.fileExists(atPath: builds.appending(path: "1.0.\(patch)").path))
        }
    }

    func testRetentionCleanupFailureDoesNotFailCompletedCompilation() throws {
        let root = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try AddOnProject.sword(
            displayName: "Retention Failure Sword",
            originalPrompt: "A test sword",
            identity: AddOnProjectIdentity.generate()
        )
        let retentionPruner = FailingSidecarRetentionPruner()
        let compiler = BedrockAddOnCompiler(retentionPruner: retentionPruner)

        let result = try compiler.compile(project: project, profile: .current, outputDirectory: root)

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.artifact.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.artifact.projectSidecarURL.path))
        XCTAssertTrue(retentionPruner.wasCalled)
    }

    private func makeFixtureDirectory() throws -> URL {
        let scratch = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: ".scratch/tests/privacy-telemetry", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let fixture = scratch.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        return fixture
    }

    private func writeBuildDate(_ date: Date, to buildDirectory: URL) throws {
        let marker = buildDirectory.appending(path: SidecarRetentionService.createdAtFilename)
        try Data(String(date.timeIntervalSince1970).utf8).write(to: marker)
    }
}

private final class FailingSidecarRetentionPruner: SidecarRetentionPruning, @unchecked Sendable {
    private let lock = NSLock()
    private var called = false

    var wasCalled: Bool {
        lock.lock(); defer { lock.unlock() }
        return called
    }

    func prune(in outputDirectory: URL, now: Date) throws -> [URL] {
        lock.lock()
        called = true
        lock.unlock()
        throw RetentionPrunerError.unavailable
    }
}

private enum RetentionPrunerError: Error {
    case unavailable
}
