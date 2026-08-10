import Foundation

public struct TelemetryEvent: Equatable, Sendable {
    public let name: String
    public let properties: [String: String]
    public let timestamp: Date

    public init(name: String, properties: [String: String] = [:], timestamp: Date = Date()) {
        self.name = name
        self.properties = properties
        self.timestamp = timestamp
    }
}

public protocol TelemetrySink: Sendable {
    func record(_ event: TelemetryEvent)
}

public final class InMemoryTelemetrySink: TelemetrySink, @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [TelemetryEvent] = []

    public init() {}

    public func record(_ event: TelemetryEvent) {
        lock.lock(); defer { lock.unlock() }
        _events.append(event)
    }

    public var events: [TelemetryEvent] {
        lock.lock(); defer { lock.unlock() }
        return _events
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        _events.removeAll()
    }
}

public protocol TelemetryOptInStorage: Sendable {
    func isOptedIn() -> Bool
    func setOptedIn(_ value: Bool)
}

public final class UserDefaultsTelemetryStorage: TelemetryOptInStorage, @unchecked Sendable {
    private let key: String
    private let defaults: UserDefaults

    public init(key: String = "craftberry.telemetryOptIn", defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
    }

    public func isOptedIn() -> Bool { defaults.bool(forKey: key) }
    public func setOptedIn(_ value: Bool) { defaults.set(value, forKey: key) }
}

public final class InMemoryTelemetryStorage: TelemetryOptInStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var _optedIn = false
    public init(optedIn: Bool = false) { _optedIn = optedIn }
    public func isOptedIn() -> Bool { lock.lock(); defer { lock.unlock() }; return _optedIn }
    public func setOptedIn(_ value: Bool) { lock.lock(); defer { lock.unlock() }; _optedIn = value }
}

public final class TelemetryManager: Sendable {
    private let storage: any TelemetryOptInStorage
    private let sink: any TelemetrySink

    public init(storage: any TelemetryOptInStorage, sink: any TelemetrySink) {
        self.storage = storage
        self.sink = sink
    }

    public var isOptedIn: Bool { storage.isOptedIn() }

    public func setOptedIn(_ value: Bool) {
        storage.setOptedIn(value)
    }

    public func record(_ event: TelemetryEvent) {
        guard storage.isOptedIn() else { return }
        sink.record(event)
    }

    public func record(name: String, properties: [String: String] = [:]) {
        record(TelemetryEvent(name: name, properties: properties))
    }
}
