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

    #if os(macOS)
    func testReleasePrivacyContactBuildGateRejectsPlaceholderAndAcceptsConfiguredURL() throws {
        XCTAssertNotEqual(
            try privacyContactBuildGateStatus("https://craftberry.example.com/privacy"),
            0
        )
        XCTAssertEqual(
            try privacyContactBuildGateStatus("https://privacy-contact.craftberry.com/contact"),
            0
        )
        XCTAssertEqual(
            try privacyContactBuildGateStatus("$(CRAFTBERRY_PRIVACY_CONTACT_URL)", configuration: "Debug"),
            0
        )
    }
    #endif

    func testPrivacyDisclosureQualifiesTelemetryExpiryCleanupTiming() {
        let disclosure = PrivacyDisclosure.configured(contactURLString: nil)

        XCTAssertTrue(disclosure.retentionSummary.contains("next time the app performs cleanup"))
    }

    func testProtectedBuildIdentityIgnoresRefreshedCreationDate() {
        let policy = SidecarRetentionPolicy(maxBuildsPerProject: 1, maxAgeDays: 1)
        let projectID = UUID()
        let version = VersionTriplet(major: 1, minor: 0, patch: 1)
        let storedBuild = SidecarBuildMetadata(
            projectID: projectID,
            version: version,
            createdAt: Date(timeIntervalSince1970: 1_000_000)
        )
        let rebuiltBuild = SidecarBuildMetadata(
            projectID: projectID,
            version: version,
            createdAt: Date(timeIntervalSince1970: 2_000_000)
        )

        let toPrune = policy.buildsToPrune(
            builds: [storedBuild],
            now: Date(timeIntervalSince1970: 2_000_000),
            preserving: [rebuiltBuild]
        )

        XCTAssertTrue(toPrune.isEmpty)
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

    func testShareSnapshotSurvivesRetentionPruneAndCanBeCleaned() throws {
        let root = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let projectID = UUID()
        let buildDirectory = root
            .appending(path: projectID.uuidString.lowercased(), directoryHint: .isDirectory)
            .appending(path: "builds/1.0.0", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: buildDirectory, withIntermediateDirectories: true)
        let artifactURL = buildDirectory.appending(path: "fixture.mcaddon")
        let artifactContents = Data("addon bytes".utf8)
        try artifactContents.write(to: artifactURL)
        try writeBuildDate(Date(timeIntervalSince1970: 1_000_000), to: buildDirectory)

        let retentionService = SidecarRetentionService()
        let snapshotURL = try retentionService.makeShareSnapshot(of: artifactURL, in: root)
        _ = try retentionService.prune(in: root, now: Date(timeIntervalSince1970: 4_000_000))

        XCTAssertFalse(FileManager.default.fileExists(atPath: artifactURL.path))
        XCTAssertEqual(try Data(contentsOf: snapshotURL), artifactContents)
        retentionService.removeShareSnapshot(at: snapshotURL, in: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path))
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

    func testCompilerPreservesArtifactWhenRebuildingAnOlderVersion() throws {
        let root = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = AddOnProjectIdentity.generate()
        let base = try AddOnProject.sword(
            displayName: "Rebuilt Old Version Sword",
            originalPrompt: "A test sword",
            identity: identity
        )
        let compiler = BedrockAddOnCompiler()

        for patch in 1...6 {
            let project = project(base, version: VersionTriplet(major: 1, minor: 0, patch: patch))
            _ = try compiler.compile(project: project, profile: .current, outputDirectory: root)
        }

        let rebuiltProject = project(base, version: VersionTriplet(major: 1, minor: 0, patch: 1))
        let result = try compiler.compile(project: rebuiltProject, profile: .current, outputDirectory: root)
        _ = try SidecarRetentionService().prune(in: root)

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.artifact.url.path))
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

    #if os(macOS)
    private func privacyContactBuildGateStatus(
        _ contactURL: String,
        configuration: String = "Release"
    ) throws -> Int32 {
        let root = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let appDirectory = root.appending(path: "Craftberry.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["PrivacyContactURL": contactURL],
            format: .xml,
            options: 0
        )
        try plist.write(to: appDirectory.appending(path: "Info.plist"))

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = repositoryRoot.appending(path: "scripts/validate-distribution-privacy-contact.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path]
        var environment = ProcessInfo.processInfo.environment
        environment["CONFIGURATION"] = configuration
        environment["BUILT_PRODUCTS_DIR"] = root.path
        environment["INFOPLIST_PATH"] = "Craftberry.app/Info.plist"
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
    #endif

    private func project(_ base: AddOnProject, version: VersionTriplet) -> AddOnProject {
        AddOnProject(
            id: base.id,
            namespace: base.namespace,
            displayName: base.displayName,
            shortDescription: base.shortDescription,
            packUUIDs: base.packUUIDs,
            buildVersion: version,
            targetProfileID: base.targetProfileID,
            originalPrompt: base.originalPrompt,
            content: base.content
        )
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

    func prune(
        in outputDirectory: URL,
        now: Date,
        preserving protectedBuilds: Set<SidecarBuildMetadata>
    ) throws -> [URL] {
        lock.lock()
        called = true
        lock.unlock()
        throw RetentionPrunerError.unavailable
    }
}

private enum RetentionPrunerError: Error {
    case unavailable
}
