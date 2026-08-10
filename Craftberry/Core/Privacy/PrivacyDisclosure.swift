import Foundation

public struct PrivacyDisclosure: Equatable, Sendable {
    public let title: String
    public let summary: String
    public let dataCollected: [String]
    public let dataNotCollected: [String]
    public let retentionSummary: String
    public let contactURL: URL?

    public init(
        title: String,
        summary: String,
        dataCollected: [String],
        dataNotCollected: [String],
        retentionSummary: String,
        contactURL: URL?
    ) {
        self.title = title
        self.summary = summary
        self.dataCollected = dataCollected
        self.dataNotCollected = dataNotCollected
        self.retentionSummary = retentionSummary
        self.contactURL = contactURL
    }

    public static var current: PrivacyDisclosure {
        PrivacyDisclosure(
            title: "Craftberry Privacy Disclosure",
            summary: "Craftberry generates Bedrock add-ons locally from a prompt. Prompts are sent to the configured backend/LLM only when you tap Generate. No Minecraft world data is collected.",
            dataCollected: [
                "Prompt text you enter and the generated AddOnProject sidecar (stored locally).",
                "Anonymous generation counts for quota/abuse controls (no prompt content).",
                "Opt-in telemetry events only if you enable telemetry (anonymous, no PII)."
            ],
            dataNotCollected: [
                "Minecraft worlds, worlds folder contents, or device identifiers.",
                "Precise location, contacts, or third-party advertising identifiers."
            ],
            retentionSummary: "Sidecars are kept locally; builds under <project-id>/builds/<version>/ are pruned by retention policy (default keeps 5 latest builds per project, max 30 days). Telemetry, when opted in, is retained 30 days.",
            contactURL: URL(string: "https://craftberry.example.com/privacy")
        )
    }

    public var asDictionary: [String: Any] {
        [
            "title": title,
            "summary": summary,
            "dataCollected": dataCollected,
            "dataNotCollected": dataNotCollected,
            "retentionSummary": retentionSummary,
            "contactURL": contactURL?.absoluteString ?? ""
        ]
    }

    public func validateForDistributableBuild() throws {
        guard !title.isEmpty, !summary.isEmpty else {
            throw DistributableBuildError.missingPrivacyDisclosure
        }
        guard !dataCollected.isEmpty else {
            throw DistributableBuildError.missingPrivacyDisclosure
        }
    }
}

public enum DistributableBuildError: LocalizedError, Equatable {
    case missingBackendConfiguration
    case missingPrivacyDisclosure
    case missingProfileMigration

    public var errorDescription: String? {
        switch self {
        case .missingBackendConfiguration: "Distributable builds require a configured backend (https baseURL + token)."
        case .missingPrivacyDisclosure: "Distributable builds require a complete privacy disclosure."
        case .missingProfileMigration: "Project profile is incompatible; migrate before distribution."
        }
    }
}

public struct DistributableBuildValidator: Sendable {
    public init() {}

    public func validate(
        backend: BackendConfiguration,
        privacy: PrivacyDisclosure = .current
    ) throws {
        do {
            try backend.validateForDistributableBuild()
        } catch {
            throw DistributableBuildError.missingBackendConfiguration
        }
        do {
            try privacy.validateForDistributableBuild()
        } catch {
            throw DistributableBuildError.missingPrivacyDisclosure
        }
    }
}
