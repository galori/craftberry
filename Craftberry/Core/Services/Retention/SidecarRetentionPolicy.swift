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
        now: Date = Date()
    ) -> [SidecarBuildMetadata] {
        guard !builds.isEmpty else { return [] }
        var toPrune: Set<SidecarBuildMetadata> = []
        let ageCutoff = now.addingTimeInterval(TimeInterval(-maxAgeDays * 24 * 3600))

        for build in builds where build.createdAt < ageCutoff {
            toPrune.insert(build)
        }

        let byProject = Dictionary(grouping: builds) { $0.projectID }
        for (_, group) in byProject {
            let sorted = group.sorted { a, b in
                if a.version.major != b.version.major { return a.version.major > b.version.major }
                if a.version.minor != b.version.minor { return a.version.minor > b.version.minor }
                if a.version.patch != b.version.patch { return a.version.patch > b.version.patch }
                return a.createdAt > b.createdAt
            }
            if sorted.count > maxBuildsPerProject {
                for extra in sorted.suffix(from: maxBuildsPerProject) {
                    toPrune.insert(extra)
                }
            }
        }
        return builds.filter { toPrune.contains($0) }
    }

    public func buildsToKeep(
        builds: [SidecarBuildMetadata],
        now: Date = Date()
    ) -> [SidecarBuildMetadata] {
        let pruneSet = Set(buildsToPrune(builds: builds, now: now))
        return builds.filter { !pruneSet.contains($0) }
    }

    public func prune(
        builds: [SidecarBuildMetadata],
        in directory: URL,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        let toPrune = buildsToPrune(builds: builds)
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

extension SidecarBuildMetadata: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
