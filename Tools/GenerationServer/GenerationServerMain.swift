import CraftberryCore
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@main
enum GenerationServerMain {
    static func main() async {
        do {
            try await run()
        } catch {
            fputs("GenerationServer: \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    private static func run() async throws {
        let environment = ProcessInfo.processInfo.environment
        _ = umask(0o077)
        let appIdentifier = try requiredEnvironment("APP_ATTEST_APP_ID", in: environment)
        _ = try requiredEnvironment("OPENAI_API_KEY", in: environment)
        let appEnvironmentValue = try requiredEnvironment("APP_ATTEST_ENVIRONMENT", in: environment)
        guard let appEnvironment = AppAttestEnvironment(rawValue: appEnvironmentValue) else {
            throw ServerStartupError.invalidAppAttestEnvironment
        }
        let allowedVersionValues = try requiredEnvironment("APP_ATTEST_ALLOWED_BUNDLE_VERSIONS", in: environment)
        let allowedVersions = Set(allowedVersionValues.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })
        guard !allowedVersions.isEmpty else { throw ServerStartupError.missingAllowedBundleVersions }
        let databasePath = environment["GENERATION_DATABASE_PATH"] ?? "craftberry-generation.sqlite"
        let databaseURL = URL(fileURLWithPath: databasePath).standardizedFileURL
        let bindHost = environment["GENERATION_BIND_HOST"] ?? "127.0.0.1"
        guard let port = UInt16(environment["GENERATION_PORT"] ?? "8787"), port > 0 else {
            throw ServerStartupError.invalidPort
        }
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let databaseLock = try GenerationDatabaseProcessLock(databaseURL: databaseURL)
        defer { databaseLock.unlock() }

        guard let rootURL = Bundle.module.url(
            forResource: "Apple_App_Attestation_Root_CA",
            withExtension: "pem"
        ), let rootPEM = try? String(contentsOf: rootURL, encoding: .utf8),
           let rootDER = pemCertificate(rootPEM) else {
            throw ServerStartupError.missingAppleAttestationRoot
        }
        guard let receiptRootURL = Bundle.module.url(forResource: "AppleRootCA-G3", withExtension: "cer"),
              let receiptRootDER = try? Data(contentsOf: receiptRootURL) else {
            throw ServerStartupError.missingAppleReceiptRoot
        }

        let service = GenerationService(
            configuration: GenerationServiceConfiguration(
                expectedAppIdentifier: appIdentifier,
                appAttestEnvironment: appEnvironment
            ),
            store: try SQLiteGenerationServiceStore(databaseURL: databaseURL),
            attestationVerifier: AppleAppAttestVerifier(
                rootCertificateDER: rootDER,
                receiptRootCertificateDER: receiptRootDER,
                allowedBundleVersions: allowedVersions
            ),
            intentProvider: EnvironmentOpenAIIntentProvider(environment: environment)
        )

        let socketServer = GenerationHTTPServer(bindHost: bindHost, port: port)
        print("Generation service listening on \(bindHost):\(port); database \(databasePath)")
        try await socketServer.run(service: service)
    }

    private static func requiredEnvironment(_ key: String, in environment: [String: String]) throws -> String {
        guard let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            throw ServerStartupError.missingEnvironment(key)
        }
        return value
    }

    private static func pemCertificate(_ pem: String) -> Data? {
        let content = pem
            .replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
            .replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        return Data(base64Encoded: content)
    }
}

private enum ServerStartupError: LocalizedError {
    case missingEnvironment(String)
    case missingAppleAttestationRoot
    case missingAppleReceiptRoot
    case invalidAppAttestEnvironment
    case missingAllowedBundleVersions
    case invalidPort
    case databaseAlreadyRunning(String)
    case databaseLockUnavailable(String, String)

    var errorDescription: String? {
        switch self {
        case .missingEnvironment(let name): "Required server environment variable is missing: \(name)"
        case .missingAppleAttestationRoot: "The Apple App Attestation Root CA resource is missing or invalid."
        case .missingAppleReceiptRoot: "The Apple Root CA G3 resource for App Attest receipt verification is missing or invalid."
        case .invalidAppAttestEnvironment: "APP_ATTEST_ENVIRONMENT must be development or production."
        case .missingAllowedBundleVersions: "APP_ATTEST_ALLOWED_BUNDLE_VERSIONS must contain at least one version."
        case .invalidPort: "GENERATION_PORT must be a TCP port between 1 and 65535."
        case .databaseAlreadyRunning(let path):
            "Another GenerationServer process already holds the database lock for \(path)."
        case .databaseLockUnavailable(let path, let reason):
            "Unable to lock the generation database at \(path): \(reason)"
        }
    }
}

private final class GenerationDatabaseProcessLock {
    private let descriptor: Int32
    private var isLocked = true

    init(databaseURL: URL) throws {
        let lockPath = databaseURL.path + ".lock"
        let opened = open(lockPath, O_CREAT | O_RDWR | O_NOFOLLOW, mode_t(0o600))
        guard opened >= 0 else {
            throw ServerStartupError.databaseLockUnavailable(lockPath, String(cString: strerror(errno)))
        }
        guard fchmod(opened, mode_t(0o600)) == 0 else {
            let reason = String(cString: strerror(errno))
            close(opened)
            throw ServerStartupError.databaseLockUnavailable(lockPath, reason)
        }
        guard flock(opened, LOCK_EX | LOCK_NB) == 0 else {
            let lockError = errno
            let reason = lockError == EWOULDBLOCK
                ? "another server process is using this database"
                : String(cString: strerror(lockError))
            close(opened)
            if lockError == EWOULDBLOCK {
                throw ServerStartupError.databaseAlreadyRunning(databaseURL.path)
            }
            throw ServerStartupError.databaseLockUnavailable(lockPath, reason)
        }
        descriptor = opened
    }

    func unlock() {
        guard isLocked else { return }
        isLocked = false
        _ = flock(descriptor, LOCK_UN)
        _ = close(descriptor)
    }

    deinit { unlock() }
}

private struct GenerationHTTPServer {
    let bindHost: String
    let port: UInt16
    private let maximumHeaderBytes = 16_384
    private let maximumBodyBytes = 65_536
    private let socketDeadlineNanoseconds: UInt64 = 10_000_000_000
    private let blockingIOQueue = DispatchQueue(
        label: "com.craftberry.generation-server.blocking-io",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private let connectionSlots = DispatchSemaphore(value: 32)

    func run(service: GenerationService) async throws {
        signal(SIGPIPE, SIG_IGN)
        let listener = try makeListener()
        defer { _ = close(listener) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let acceptThread = Thread { [self] in
                do {
                    try acceptLoop(listener: listener, service: service)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            acceptThread.name = "com.craftberry.generation-server.accept"
            acceptThread.start()
        }
    }

    private func acceptLoop(listener: Int32, service: GenerationService) throws {
        while true {
            let client = accept(listener, nil, nil)
            guard client >= 0 else {
                if errno == EINTR || errno == ECONNABORTED { continue }
                throw SocketServerError.systemCall("accept", errno)
            }
            connectionSlots.wait()
            guard configureClientSocket(client) else {
                _ = close(client)
                connectionSlots.signal()
                continue
            }
            blockingIOQueue.async { [self] in
                receiveAndDispatch(client: client, service: service)
            }
        }
    }

    private func configureClientSocket(_ descriptor: Int32) -> Bool {
        let flags = fcntl(descriptor, F_GETFL, 0)
        guard flags >= 0 else { return false }
        return fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0
    }

    private func makeListener() throws -> Int32 {
        let descriptor = socket(AF_INET, Int32(SOCK_STREAM), 0)
        guard descriptor >= 0 else { throw SocketServerError.systemCall("socket", errno) }
        var reuse: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            let failure = errno
            _ = close(descriptor)
            throw SocketServerError.systemCall("setsockopt", failure)
        }
        #if canImport(Darwin)
        var noPipe: Int32 = 1
        _ = setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noPipe, socklen_t(MemoryLayout<Int32>.size))
        #endif

        var address = sockaddr_in()
        #if canImport(Darwin)
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        let parsedHost = bindHost.withCString { inet_pton(AF_INET, $0, &address.sin_addr) }
        guard parsedHost == 1 else {
            _ = close(descriptor)
            throw SocketServerError.invalidBindAddress(bindHost)
        }
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            let failure = errno
            _ = close(descriptor)
            throw SocketServerError.systemCall("bind", failure)
        }
        guard listen(descriptor, 128) == 0 else {
            let failure = errno
            _ = close(descriptor)
            throw SocketServerError.systemCall("listen", failure)
        }
        return descriptor
    }

    private func receiveAndDispatch(client: Int32, service: GenerationService) {
        do {
            let request = try readRequest(client)
            Task {
                let response = await service.handle(request)
                blockingIOQueue.async { [self] in
                    defer { finish(client) }
                    try? writeResponse(response, to: client)
                }
            }
        } catch let error as HTTPParseError {
            let status = error == .bodyTooLarge ? 413 : 400
            let payload = Data((status == 413 ? "{\"error\":\"request_too_large\"}" : "{\"error\":\"invalid_request\"}").utf8)
            try? writeResponse(
                GenerationServiceResponse(statusCode: status, headers: ["Content-Type": "application/json"], body: payload),
                to: client
            )
            finish(client)
        } catch {
            let payload = Data("{\"error\":\"service_unavailable\"}".utf8)
            try? writeResponse(
                GenerationServiceResponse(statusCode: 503, headers: ["Content-Type": "application/json"], body: payload),
                to: client
            )
            finish(client)
        }
    }

    private func finish(_ descriptor: Int32) {
        _ = close(descriptor)
        connectionSlots.signal()
    }

    private func readRequest(_ descriptor: Int32) throws -> GenerationServiceRequest {
        let deadline = DispatchTime.now().uptimeNanoseconds + socketDeadlineNanoseconds
        var accumulated = Data()
        let headerDelimiter = Data([13, 10, 13, 10])
        var headerRange: Range<Data.Index>?
        while headerRange == nil {
            let chunk = try receive(descriptor, maximum: 4_096, deadline: deadline)
            guard !chunk.isEmpty else { throw HTTPParseError.invalid }
            accumulated.append(chunk)
            guard accumulated.count <= maximumHeaderBytes + maximumBodyBytes else { throw HTTPParseError.bodyTooLarge }
            headerRange = accumulated.range(of: headerDelimiter)
            if headerRange == nil, accumulated.count > maximumHeaderBytes { throw HTTPParseError.invalid }
        }
        guard let headerRange else { throw HTTPParseError.invalid }
        let headerData = accumulated[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { throw HTTPParseError.invalid }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { throw HTTPParseError.invalid }
        let components = requestLine.split(separator: " ")
        guard components.count == 3, components[2].hasPrefix("HTTP/") else { throw HTTPParseError.invalid }
        let requestPath = String(components[1]).split(separator: "?", maxSplits: 1).first.map(String.init) ?? "/"
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { throw HTTPParseError.invalid }
            let name = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedName = name.lowercased()
            guard !normalizedName.isEmpty, headers[normalizedName] == nil else {
                throw HTTPParseError.invalid
            }
            headers[normalizedName] = value
        }
        guard headers["transfer-encoding"] == nil else { throw HTTPParseError.invalid }
        let contentLength: Int
        if let value = headers["content-length"] {
            guard let parsedLength = Int(value) else { throw HTTPParseError.invalid }
            contentLength = parsedLength
        } else {
            contentLength = 0
        }
        guard contentLength >= 0, contentLength <= maximumBodyBytes else { throw HTTPParseError.bodyTooLarge }
        var body = Data(accumulated[headerRange.upperBound...])
        while body.count < contentLength {
            let chunk = try receive(descriptor, maximum: min(4_096, contentLength - body.count), deadline: deadline)
            guard !chunk.isEmpty else { throw HTTPParseError.invalid }
            body.append(chunk)
        }
        guard body.count >= contentLength else { throw HTTPParseError.invalid }
        body = Data(body.prefix(contentLength))
        return GenerationServiceRequest(
            method: String(components[0]),
            path: requestPath,
            headers: headers,
            body: body
        )
    }

    private func receive(_ descriptor: Int32, maximum: Int, deadline: UInt64) throws -> Data {
        while true {
            try waitUntilReady(descriptor, for: Int16(POLLIN), deadline: deadline, operation: "read")
            var buffer = [UInt8](repeating: 0, count: maximum)
            let received = buffer.withUnsafeMutableBytes { rawBuffer in
                recv(descriptor, rawBuffer.baseAddress, maximum, 0)
            }
            if received < 0 {
                if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK { continue }
                throw SocketServerError.systemCall("recv", errno)
            }
            return Data(buffer.prefix(Int(received)))
        }
    }

    private func writeResponse(_ response: GenerationServiceResponse, to descriptor: Int32) throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + socketDeadlineNanoseconds
        let reason: String
        switch response.statusCode {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 404: reason = "Not Found"
        case 409: reason = "Conflict"
        case 413: reason = "Payload Too Large"
        case 429: reason = "Too Many Requests"
        case 500: reason = "Internal Server Error"
        case 503: reason = "Service Unavailable"
        default: reason = "Error"
        }
        var headers = response.headers
        headers["Content-Length"] = String(response.body.count)
        headers["Connection"] = "close"
        let headerLines = headers.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "\r\n")
        var output = Data("HTTP/1.1 \(response.statusCode) \(reason)\r\n\(headerLines)\r\n\r\n".utf8)
        output.append(response.body)
        var offset = 0
        while offset < output.count {
            try waitUntilReady(descriptor, for: Int16(POLLOUT), deadline: deadline, operation: "write")
            let sent = output.withUnsafeBytes { rawBuffer -> Int in
                let base = rawBuffer.baseAddress!.advanced(by: offset)
                #if canImport(Darwin)
                return Darwin.send(descriptor, base, output.count - offset, 0)
                #else
                return Glibc.send(descriptor, base, output.count - offset, Int32(MSG_NOSIGNAL))
                #endif
            }
            if sent < 0 {
                if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK { continue }
                throw SocketServerError.systemCall("send", errno)
            }
            guard sent > 0 else { throw SocketServerError.systemCall("send", EPIPE) }
            offset += sent
        }
    }

    private func waitUntilReady(
        _ descriptor: Int32,
        for events: Int16,
        deadline: UInt64,
        operation: String
    ) throws {
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { throw SocketServerError.deadlineExceeded(operation) }
            let remainingNanoseconds = deadline - now
            let remainingMilliseconds = min((remainingNanoseconds + 999_999) / 1_000_000, UInt64(Int32.max))
            var state = pollfd(fd: descriptor, events: events, revents: 0)
            let result = poll(&state, 1, Int32(remainingMilliseconds))
            if result > 0 { return }
            if result == 0 { throw SocketServerError.deadlineExceeded(operation) }
            if errno == EINTR { continue }
            throw SocketServerError.systemCall("poll", errno)
        }
    }
}

private enum HTTPParseError: Error, Equatable {
    case invalid
    case bodyTooLarge
}

private enum SocketServerError: LocalizedError {
    case systemCall(String, Int32)
    case invalidBindAddress(String)
    case deadlineExceeded(String)

    var errorDescription: String? {
        switch self {
        case .systemCall(let name, let code): "Socket \(name) failed with errno \(code)."
        case .invalidBindAddress(let host): "Bind host must be an IPv4 address, got \(host)."
        case .deadlineExceeded(let operation): "Socket \(operation) deadline expired."
        }
    }
}
