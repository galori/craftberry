import Foundation

public enum ProfileMigrationError: LocalizedError, Equatable {
    case incompatibleProfile(expected: String, found: String)
    case unsupportedSchema(Int)
    case migrationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .incompatibleProfile(let expected, let found):
            "Project targets profile \(found), expected \(expected). Migrate before compiling."
        case .unsupportedSchema(let version):
            "Project schema version \(version) is newer than this app supports."
        case .migrationFailed(let detail): "Migration failed: \(detail)"
        }
    }
}

public struct ProfileMigrationGate: Sendable {
    public let currentProfile: BedrockContentProfile

    public init(currentProfile: BedrockContentProfile = .current) {
        self.currentProfile = currentProfile
    }

    public func requiresMigration(for project: AddOnProject) -> Bool {
        project.targetProfileID != currentProfile.id || project.schemaVersion != AddOnProject.currentSchemaVersion
    }

    public func validate(_ project: AddOnProject) throws {
        if project.schemaVersion > AddOnProject.currentSchemaVersion {
            throw ProfileMigrationError.unsupportedSchema(project.schemaVersion)
        }
        if project.targetProfileID != currentProfile.id {
            throw ProfileMigrationError.incompatibleProfile(expected: currentProfile.id, found: project.targetProfileID)
        }
        if project.schemaVersion != AddOnProject.currentSchemaVersion {
            throw ProfileMigrationError.incompatibleProfile(
                expected: "schema \(AddOnProject.currentSchemaVersion)",
                found: "schema \(project.schemaVersion)"
            )
        }
    }

    public func migratedProject(_ project: AddOnProject) throws -> AddOnProject {
        var migrated = project
        if migrated.schemaVersion != AddOnProject.currentSchemaVersion {
            migrated = try migrated.migratedToCurrentSchema()
        }
        if migrated.targetProfileID != currentProfile.id {
            let report = AddOnProjectValidator.validate(migrated, profile: currentProfile)
            let compatible = report.errors.allSatisfy { $0.code != "incompatible_profile" } == false
            _ = compatible
            migrated = AddOnProject(
                schemaVersion: migrated.schemaVersion,
                id: migrated.id,
                namespace: migrated.namespace,
                displayName: migrated.displayName,
                shortDescription: migrated.shortDescription,
                packUUIDs: migrated.packUUIDs,
                buildVersion: migrated.buildVersion,
                targetProfileID: currentProfile.id,
                originalPrompt: migrated.originalPrompt,
                content: migrated.content
            )
        }
        try validate(migrated)
        return migrated
    }

    public func validatedOrMigrated(_ project: AddOnProject) throws -> AddOnProject {
        do {
            try validate(project)
            return project
        } catch {
            return try migratedProject(project)
        }
    }
}
