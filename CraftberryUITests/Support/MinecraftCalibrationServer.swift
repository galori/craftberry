import Foundation
import Network

/// A test-only TCP listener that exposes a `MinecraftCalibrationController` on
/// `127.0.0.1:8765` (via `iproxy`) using one newline-delimited JSON request per
/// TCP connection.
///
/// The listener exists only for the lifetime of the calibration UI test; the
/// fixed port is acceptable because the host side binds only to localhost and
/// the listener is torn down when the test ends.
final class MinecraftCalibrationServer {
    static let defaultPort: UInt16 = 8765

    private let port: NWEndpoint.Port
    private let controller: MinecraftCalibrationController
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "craftberry.calibration.server")

    init(port: UInt16 = defaultPort, controller: MinecraftCalibrationController) {
        self.port = NWEndpoint.Port(rawValue: port)!
        self.controller = controller
    }

    func start() throws {
        let parameters = NWParameters.tcp
        // No TLS, no bonjour — plain TCP on the USB-forwarded localhost.
        let listener = try NWListener(using: parameters, on: port)
        self.listener = listener

        listener.newConnectionHandler = { [controller, queue] connection in
            connection.start(queue: queue)
            Self.handle(connection: connection, controller: controller, queue: queue)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .failed(let error):
                print("[CalibrationServer] listener failed: \(error)")
            case .ready:
                print("[CalibrationServer] listening on \(String(describing: listener.port))")
            default:
                break
            }
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Per-connection handler

    private static func handle(
        connection: NWConnection,
        controller: MinecraftCalibrationController,
        queue: DispatchQueue
    ) {
        connection.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                print("[CalibrationServer] connection failed: \(error)")
                connection.cancel()
            }
        }

        // Accumulate bytes until newline, then handle one request per connection.
        var buffer = Data()
        func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let data = data, !data.isEmpty {
                    buffer.append(data)
                    // Look for newline delimiter.
                    if let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                        let lineData = buffer[..<newlineIndex]
                        // Drain buffer after consuming this line (ignore trailing remainder).
                        buffer.removeAll()
                        let response = handleLine(Data(lineData), controller: controller)
                        send(response: response, over: connection, queue: queue)
                        return
                    }
                }
                if isComplete || error != nil {
                    // No newline-terminated JSON arrived; treat as malformed.
                    if !buffer.isEmpty {
                        let response = handleLine(buffer, controller: controller)
                        send(response: response, over: connection, queue: queue)
                    } else if let error = error {
                        print("[CalibrationServer] receive error: \(error)")
                        connection.cancel()
                    } else {
                        connection.cancel()
                    }
                    return
                }
                receive()
            }
        }
        receive()
    }

    private static func handleLine(_ data: Data, controller: MinecraftCalibrationController) -> MinecraftCalibrationResponse {
        // Empty line => error.
        let trimmed = data.trimmingNewlines()
        guard !trimmed.isEmpty else {
            return MinecraftCalibrationResponse(success: false, error: "empty request")
        }
        do {
            let request = try JSONDecoder().decode(MinecraftCalibrationRequest.self, from: trimmed)
            return controller.handle(request)
        } catch {
            return MinecraftCalibrationResponse(success: false, error: "malformed JSON: \(error.localizedDescription)")
        }
    }

    private static func send(
        response: MinecraftCalibrationResponse,
        over connection: NWConnection,
        queue: DispatchQueue
    ) {
        do {
            var data = try JSONEncoder().encode(response)
            data.append(UInt8(ascii: "\n"))
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    print("[CalibrationServer] send error: \(error)")
                }
                connection.cancel()
            })
        } catch {
            var fallback = try? JSONEncoder().encode(MinecraftCalibrationResponse(success: false, error: "failed to encode response: \(error.localizedDescription)"))
            fallback?.append(UInt8(ascii: "\n"))
            if let fallback = fallback {
                connection.send(content: fallback, completion: .contentProcessed { _ in connection.cancel() })
            } else {
                connection.cancel()
            }
        }
    }
}

private extension Data {
    func trimmingNewlines() -> Data {
        var start = startIndex
        var end = endIndex
        while start < end && (self[start] == UInt8(ascii: "\n") || self[start] == UInt8(ascii: "\r") || self[start] == UInt8(ascii: " ") || self[start] == UInt8(ascii: "\t")) {
            start = index(after: start)
        }
        while end > start {
            let prev = index(before: end)
            if self[prev] == UInt8(ascii: "\n") || self[prev] == UInt8(ascii: "\r") || self[prev] == UInt8(ascii: " ") || self[prev] == UInt8(ascii: "\t") {
                end = prev
            } else {
                break
            }
        }
        return self[start..<end]
    }
}
