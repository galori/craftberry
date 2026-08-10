import Foundation

public enum BackendError: LocalizedError, Equatable {
    case missingConfiguration(String)
    case invalidConfiguration(String)
    case unauthorized

    public var errorDescription: String? {
        switch self {
        case .missingConfiguration(let detail): "Backend not configured: \(detail)"
        case .invalidConfiguration(let detail): "Invalid backend configuration: \(detail)"
        case .unauthorized: "Backend authorization failed."
        }
    }
}

public struct BackendConfiguration: Equatable, Sendable {
    public let baseURL: URL?
    public let authToken: String

    public init(baseURL: URL?, authToken: String) {
        self.baseURL = baseURL
        self.authToken = authToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static var empty: BackendConfiguration {
        BackendConfiguration(baseURL: nil, authToken: "")
    }

    public var isConfigured: Bool {
        guard let url = baseURL else { return false }
        return !authToken.isEmpty && url.scheme?.hasPrefix("https") == true
    }

    public static func fromInfoDictionary(_ dict: [String: Any] = Bundle.main.infoDictionary ?? [:]) -> BackendConfiguration {
        let urlString = dict["BackendBaseURL"] as? String ?? ""
        let token = dict["BackendAuthToken"] as? String ?? ""
        let url = URL(string: urlString)
        return BackendConfiguration(baseURL: url, authToken: token)
    }

    public func validateForDistributableBuild() throws {
        guard isConfigured else {
            throw BackendError.missingConfiguration("Distributable builds require BackendBaseURL (https) and BackendAuthToken.")
        }
        guard let url = baseURL, url.scheme == "https" else {
            throw BackendError.invalidConfiguration("BackendBaseURL must be https.")
        }
        guard authToken.count >= 16 else {
            throw BackendError.invalidConfiguration("BackendAuthToken must be at least 16 characters.")
        }
    }
}

public struct BackendClient: Sendable {
    public let configuration: BackendConfiguration
    private let session: URLSession

    public init(configuration: BackendConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    public var isConfigured: Bool { configuration.isConfigured }

    public func validateForDistributableBuild() throws {
        try configuration.validateForDistributableBuild()
    }

    public func authorizedRequest(for url: URL, method: String = "GET") throws -> URLRequest {
        guard configuration.isConfigured else { throw BackendError.missingConfiguration("Backend not configured.") }
        guard let base = configuration.baseURL else { throw BackendError.missingConfiguration("Missing baseURL.") }
        guard url.absoluteString.hasPrefix(base.absoluteString) || url.host == base.host else {
            throw BackendError.invalidConfiguration("Request URL must be under configured baseURL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(configuration.authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    public func authorizedRequest(_ request: URLRequest) throws -> URLRequest {
        guard configuration.isConfigured else { throw BackendError.missingConfiguration("Backend not configured.") }
        var copy = request
        copy.setValue("Bearer \(configuration.authToken)", forHTTPHeaderField: "Authorization")
        return copy
    }
}
