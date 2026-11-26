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
        configured(contactURLString: Bundle.main.object(forInfoDictionaryKey: "PrivacyContactURL") as? String)
    }

    public static func configured(contactURLString: String?) -> PrivacyDisclosure {
        PrivacyDisclosure(
            title: "Craftberry Privacy Disclosure",
            summary: "Craftberry generates Bedrock add-ons from prompts you submit. Prompts are sent to the configured generation service only when you choose Generate or Apply revision. Project files stay on this device unless you export or share them.",
            dataCollected: [
                "The prompt text you submit, sent to the configured generation service when you generate or revise an add-on.",
                "Generated project sidecars and add-on builds, stored locally on this device.",
                "Optional anonymous generation and build events stored locally only if you enable telemetry."
            ],
            dataNotCollected: [
                "Prompt text, artwork, or project content in telemetry events.",
                "Craftberry never accesses Minecraft worlds, world-folder contents, contacts, or precise location."
            ],
            retentionSummary: "Project sidecars stay on this device. Generated build folders keep the 5 newest versions per project and expire after 30 days. Optional local telemetry expires after 30 days and is deleted when you opt out.",
            contactURL: Self.validContactURL(from: contactURLString)
        )
    }

    public static func configured(contactURL: URL?) -> PrivacyDisclosure {
        configured(contactURLString: contactURL?.absoluteString)
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
        guard !dataCollected.isEmpty, !dataNotCollected.isEmpty, !retentionSummary.isEmpty else {
            throw DistributableBuildError.missingPrivacyDisclosure
        }
        guard let contactURL, Self.isUsableContactURL(contactURL) else {
            throw DistributableBuildError.missingPrivacyContact
        }
    }

    private static func validContactURL(from value: String?) -> URL? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains("$") else { return nil }
        guard let url = URL(string: trimmed), isUsableContactURL(url) else { return nil }
        return url
    }

    private static func isUsableContactURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              !host.isEmpty else { return false }
        let placeholderHosts = ["example.com", "example.org", "example.net", "example.invalid"]
        guard !placeholderHosts.contains(host),
              host != "localhost",
              host != "127.0.0.1",
              host != "::1",
              !host.hasSuffix(".example"),
              !host.hasSuffix(".example.com"),
              !host.hasSuffix(".example.org"),
              !host.hasSuffix(".example.net"),
              !host.hasSuffix(".invalid"),
              !host.hasSuffix(".test") else { return false }
        let loweredURL = url.absoluteString.lowercased()
        let placeholderTerms = ["placeholder", "your-domain", "yourdomain", "replace-me", "change-me", "$", "<", ">"]
        return !placeholderTerms.contains { loweredURL.contains($0) }
    }
}

public enum DistributableBuildError: LocalizedError, Equatable {
    case missingBackendConfiguration
    case missingPrivacyDisclosure
    case missingPrivacyContact
    case missingProfileMigration

    public var errorDescription: String? {
        switch self {
        case .missingBackendConfiguration: "Distributable builds require a configured backend (https baseURL + token)."
        case .missingPrivacyDisclosure: "Distributable builds require a complete privacy disclosure."
        case .missingPrivacyContact: "Distributable builds require a configured HTTPS privacy contact URL."
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
        } catch DistributableBuildError.missingPrivacyContact {
            throw DistributableBuildError.missingPrivacyContact
        } catch {
            throw DistributableBuildError.missingPrivacyDisclosure
        }
    }
}
