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

public protocol SidecarRetentionPruning: Sendable {
    func prune(in outputDirectory: URL, now: Date) throws -> [URL]
}

public struct SidecarRetentionService: SidecarRetentionPruning, @unchecked Sendable {
    public static let createdAtFilename = ".craftberry-created-at"

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
    public func prune(in outputDirectory: URL, now: Date = Date()) throws -> [URL] {
        guard fileManager.fileExists(atPath: outputDirectory.path) else { return [] }
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
        let toPrune = policy.buildsToPrune(builds: metadata, now: now)
        var removed: [URL] = []
        for build in toPrune {
            guard let url = byID[build.id], fileManager.fileExists(atPath: url.path) else { continue }
            try fileManager.removeItem(at: url)
            removed.append(url)
        }
        return removed.sorted { $0.path < $1.path }
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
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
