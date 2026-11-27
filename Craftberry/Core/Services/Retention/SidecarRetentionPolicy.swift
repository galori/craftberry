import Foundation

public struct SidecarBuildMetadata: Equatable, Sendable, Identifiable {
    public let id: String
    public let projectID: UUID
    public let version: VersionTriplet
    public let createdAt: Date

    public init(projectID: UUID, version: VersionTriplet, createdAt: Date) {
        self.projectID = projectID
        self.version = version
        self.createdAt = createdAt
        self.id = "\(projectID.uuidString)-\(version.major).\(version.minor).\(version.patch)"
    }
}

public struct SidecarRetentionPolicy: Equatable, Sendable {
    public let maxBuildsPerProject: Int
    public let maxAgeDays: Int

    public init(maxBuildsPerProject: Int = 5, maxAgeDays: Int = 30) {
        self.maxBuildsPerProject = maxBuildsPerProject
        self.maxAgeDays = maxAgeDays
    }

    public static let `default` = SidecarRetentionPolicy()

    public func buildsToPrune(
        builds: [SidecarBuildMetadata],
        now: Date = Date(),
        preserving protectedBuilds: Set<SidecarBuildMetadata> = []
    ) -> [SidecarBuildMetadata] {
        guard !builds.isEmpty else { return [] }
        var toPrune: Set<SidecarBuildMetadata> = []
        let ageCutoff = now.addingTimeInterval(TimeInterval(-maxAgeDays * 24 * 3600))

        for build in builds where build.createdAt < ageCutoff && !protectedBuilds.contains(build) {
            toPrune.insert(build)
        }

        let byProject = Dictionary(grouping: builds) { $0.projectID }
        for (_, group) in byProject {
            let protectedCount = group.filter(protectedBuilds.contains).count
            let remainingCapacity = max(0, maxBuildsPerProject - protectedCount)
            let candidates = group.filter { !protectedBuilds.contains($0) }
            let sorted = candidates.sorted { a, b in
                if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
                if a.version.major != b.version.major { return a.version.major > b.version.major }
                if a.version.minor != b.version.minor { return a.version.minor > b.version.minor }
                if a.version.patch != b.version.patch { return a.version.patch > b.version.patch }
                return a.id < b.id
            }
            if sorted.count > remainingCapacity {
                for extra in sorted.suffix(from: remainingCapacity) {
                    toPrune.insert(extra)
                }
            }
        }
        return builds.filter { toPrune.contains($0) }
    }

    public func buildsToKeep(
        builds: [SidecarBuildMetadata],
        now: Date = Date(),
        preserving protectedBuilds: Set<SidecarBuildMetadata> = []
    ) -> [SidecarBuildMetadata] {
        let pruneSet = Set(buildsToPrune(builds: builds, now: now, preserving: protectedBuilds))
        return builds.filter { !pruneSet.contains($0) }
    }

    public func prune(
        builds: [SidecarBuildMetadata],
        in directory: URL,
        fileManager: FileManager = .default,
        preserving protectedBuilds: Set<SidecarBuildMetadata> = []
    ) throws -> [URL] {
        let toPrune = buildsToPrune(builds: builds, preserving: protectedBuilds)
        var removed: [URL] = []
        for build in toPrune {
            let url = directory
                .appending(path: build.projectID.uuidString, directoryHint: .isDirectory)
                .appending(path: "builds", directoryHint: .isDirectory)
                .appending(path: "\(build.version.major).\(build.version.minor).\(build.version.patch)", directoryHint: .isDirectory)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
                removed.append(url)
            }
        }
        return removed
    }
}

/// Serializes build publication, retention, and artifact snapshot operations.
/// The recursive lock permits a compiler operation to invoke the retention service while locked.
public final class SidecarBuildAccessCoordinator: @unchecked Sendable {
    public static let shared = SidecarBuildAccessCoordinator()

    private let lock = NSRecursiveLock()

    private init() {}

    public func withExclusiveAccess<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}

public enum SidecarShareSnapshotError: LocalizedError {
    case sourceUnavailable

    public var errorDescription: String? {
        "The generated file is no longer available to share. Build it again and retry."
    }
}

public protocol SidecarRetentionPruning: Sendable {
    func prune(
        in outputDirectory: URL,
        now: Date,
        preserving protectedBuilds: Set<SidecarBuildMetadata>
    ) throws -> [URL]
}

public struct SidecarRetentionService: SidecarRetentionPruning, @unchecked Sendable {
    public static let createdAtFilename = ".craftberry-created-at"
    public static let shareSnapshotsDirectoryName = ".craftberry-share-snapshots"

    private let policy: SidecarRetentionPolicy
    private let fileManager: FileManager

    public init(
        policy: SidecarRetentionPolicy = .default,
        fileManager: FileManager = .default
    ) {
        self.policy = policy
        self.fileManager = fileManager
    }

    @discardableResult
    public func prune(
        in outputDirectory: URL,
        now: Date = Date(),
        preserving protectedBuilds: Set<SidecarBuildMetadata> = []
    ) throws -> [URL] {
        try SidecarBuildAccessCoordinator.shared.withExclusiveAccess {
            guard fileManager.fileExists(atPath: outputDirectory.path) else { return [] }
            _ = try? pruneStaleShareSnapshots(in: outputDirectory, now: now)
            let projectDirectories = try fileManager.contentsOfDirectory(
                at: outputDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            var metadataAndURLs: [(SidecarBuildMetadata, URL)] = []

            for projectDirectory in projectDirectories {
                guard let projectID = UUID(uuidString: projectDirectory.lastPathComponent),
                      try projectDirectory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { continue }
                let buildsDirectory = projectDirectory.appending(path: "builds", directoryHint: .isDirectory)
                guard fileManager.fileExists(atPath: buildsDirectory.path),
                      try buildsDirectory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { continue }
                let versionDirectories = try fileManager.contentsOfDirectory(
                    at: buildsDirectory,
                    includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                )
                for versionDirectory in versionDirectories {
                    guard try versionDirectory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true,
                          let version = Self.version(from: versionDirectory.lastPathComponent) else { continue }
                    let createdAt = try Self.createdAt(in: versionDirectory)
                    metadataAndURLs.append((
                        SidecarBuildMetadata(projectID: projectID, version: version, createdAt: createdAt),
                        versionDirectory
                    ))
                }
            }

            let byID = Dictionary(grouping: metadataAndURLs, by: { $0.0.id })
                .compactMapValues { $0.first?.1 }
            let metadata = metadataAndURLs.map(\.0)
            let toPrune = policy.buildsToPrune(builds: metadata, now: now, preserving: protectedBuilds)
            var removed: [URL] = []
            for build in toPrune {
                guard let url = byID[build.id], fileManager.fileExists(atPath: url.path) else { continue }
                try fileManager.removeItem(at: url)
                removed.append(url)
            }
            return removed.sorted { $0.path < $1.path }
        }
    }

    @discardableResult
    public func pruneStaleShareSnapshots(in outputDirectory: URL, now: Date = Date()) throws -> [URL] {
        try SidecarBuildAccessCoordinator.shared.withExclusiveAccess {
            let snapshotsDirectory = outputDirectory.appending(
                path: Self.shareSnapshotsDirectoryName,
                directoryHint: .isDirectory
            )
            guard fileManager.fileExists(atPath: snapshotsDirectory.path) else { return [] }
            let cutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
            let snapshots = try fileManager.contentsOfDirectory(
                at: snapshotsDirectory,
                includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            var removed: [URL] = []
            for snapshotDirectory in snapshots {
                guard try snapshotDirectory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { continue }
                let dates = try snapshotDirectory.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                let lastModified = dates.contentModificationDate ?? dates.creationDate ?? .distantPast
                guard lastModified < cutoff else { continue }
                try fileManager.removeItem(at: snapshotDirectory)
                removed.append(snapshotDirectory)
            }
            return removed.sorted { $0.path < $1.path }
        }
    }

    public func makeShareSnapshot(of sourceURL: URL, in outputDirectory: URL) throws -> URL {
        try SidecarBuildAccessCoordinator.shared.withExclusiveAccess {
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw SidecarShareSnapshotError.sourceUnavailable
            }
            let snapshotRoot = outputDirectory.appending(
                path: Self.shareSnapshotsDirectoryName,
                directoryHint: .isDirectory
            )
            let snapshotDirectory = snapshotRoot.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try fileManager.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)
            let snapshotURL = snapshotDirectory.appending(path: sourceURL.lastPathComponent)
            do {
                try fileManager.copyItem(at: sourceURL, to: snapshotURL)
                return snapshotURL
            } catch {
                try? fileManager.removeItem(at: snapshotDirectory)
                throw error
            }
        }
    }

    public func removeShareSnapshot(at snapshotURL: URL, in outputDirectory: URL) {
        SidecarBuildAccessCoordinator.shared.withExclusiveAccess {
            let snapshotRoot = outputDirectory.appending(
                path: Self.shareSnapshotsDirectoryName,
                directoryHint: .isDirectory
            ).standardizedFileURL
            let snapshotDirectory = snapshotURL.deletingLastPathComponent().standardizedFileURL
            guard snapshotDirectory.deletingLastPathComponent() == snapshotRoot,
                  UUID(uuidString: snapshotDirectory.lastPathComponent) != nil else { return }
            try? fileManager.removeItem(at: snapshotDirectory)
        }
    }

    private static func version(from directoryName: String) -> VersionTriplet? {
        let parts = directoryName.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts.allSatisfy({ $0.allSatisfy(\.isNumber) }),
              let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]),
              major >= 0, minor >= 0, patch >= 0,
              directoryName == "\(major).\(minor).\(patch)" else { return nil }
        return VersionTriplet(major: major, minor: minor, patch: patch)
    }

    private static func createdAt(in versionDirectory: URL) throws -> Date {
        let marker = versionDirectory.appending(path: createdAtFilename)
        if let markerData = try? Data(contentsOf: marker),
           let timestamp = Double(String(decoding: markerData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)),
           timestamp.isFinite {
            return Date(timeIntervalSince1970: timestamp)
        }
        let values = try versionDirectory.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values.creationDate ?? values.contentModificationDate ?? .distantPast
    }
}

extension SidecarBuildMetadata: Hashable {
    public static func == (lhs: SidecarBuildMetadata, rhs: SidecarBuildMetadata) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
