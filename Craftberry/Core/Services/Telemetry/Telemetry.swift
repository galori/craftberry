import Foundation

public struct TelemetryEvent: Codable, Equatable, Sendable {
    public let name: String
    public let properties: [String: String]
    public let timestamp: Date

    private static let allowedNames: Set<String> = [
        "generation.requested",
        "generation.succeeded",
        "generation.unsupported",
        "generation.failed",
        "build.succeeded",
        "build.failed"
    ]
    private static let allowedPropertyValues: [String: Set<String>] = [
        "outcome": ["ready", "unsupported", "failed"]
    ]

    public init(name: String, properties: [String: String] = [:], timestamp: Date = Date()) {
        self.name = name
        self.properties = properties
        self.timestamp = timestamp
    }

    fileprivate var sanitized: TelemetryEvent? {
        guard Self.allowedNames.contains(name) else { return nil }
        let safeProperties = properties.filter { key, value in
            guard let allowedValues = Self.allowedPropertyValues[key] else { return false }
            return allowedValues.contains(value)
        }
        return TelemetryEvent(name: name, properties: safeProperties, timestamp: timestamp)
    }
}

public protocol TelemetrySink: Sendable {
    func record(_ event: TelemetryEvent)
    func pruneExpired(at date: Date)
    func purge()
}

public final class InMemoryTelemetrySink: TelemetrySink, @unchecked Sendable {
    private let lock = NSLock()
    private let retentionDays: Int
    private var _events: [TelemetryEvent] = []

    public init(retentionDays: Int = 30) {
        self.retentionDays = max(0, retentionDays)
    }

    public func record(_ event: TelemetryEvent) {
        guard let event = event.sanitized else { return }
        lock.lock(); defer { lock.unlock() }
        pruneExpiredLocked(at: Date())
        _events.append(event)
    }

    public var events: [TelemetryEvent] {
        lock.lock(); defer { lock.unlock() }
        pruneExpiredLocked(at: Date())
        return _events
    }

    public func pruneExpired(at date: Date) {
        lock.lock(); defer { lock.unlock() }
        pruneExpiredLocked(at: date)
    }

    public func purge() {
        lock.lock(); defer { lock.unlock() }
        _events.removeAll()
    }

    public func reset() { purge() }

    private func pruneExpiredLocked(at date: Date) {
        let cutoff = date.addingTimeInterval(TimeInterval(-retentionDays * 24 * 60 * 60))
        _events = _events.filter { $0.timestamp >= cutoff }
    }
}

public protocol TelemetryOptInStorage: Sendable {
    func isOptedIn() -> Bool
    func setOptedIn(_ value: Bool)
}

public final class UserDefaultsTelemetryStorage: TelemetryOptInStorage, @unchecked Sendable {
    private let key: String
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(key: String = "craftberry.telemetryOptIn", defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
    }

    public func isOptedIn() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return defaults.bool(forKey: key)
    }

    public func setOptedIn(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        defaults.set(value, forKey: key)
    }
}

public final class InMemoryTelemetryStorage: TelemetryOptInStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var _optedIn: Bool

    public init(optedIn: Bool = false) { _optedIn = optedIn }

    public func isOptedIn() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return _optedIn
    }

    public func setOptedIn(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        _optedIn = value
    }
}

public protocol TelemetryEventStorage: Sendable {
    func load() -> [TelemetryEvent]
    func save(_ events: [TelemetryEvent])
    func purge()
}

public final class InMemoryTelemetryEventStorage: TelemetryEventStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var events: [TelemetryEvent] = []

    public init() {}

    public func load() -> [TelemetryEvent] {
        lock.lock(); defer { lock.unlock() }
        return events
    }

    public func save(_ events: [TelemetryEvent]) {
        lock.lock(); defer { lock.unlock() }
        self.events = events
    }

    public func purge() {
        lock.lock(); defer { lock.unlock() }
        events.removeAll()
    }
}

public final class UserDefaultsTelemetryEventStorage: TelemetryEventStorage, @unchecked Sendable {
    private let key: String
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(key: String = "craftberry.telemetryEvents", defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
    }

    public func load() -> [TelemetryEvent] {
        lock.lock(); defer { lock.unlock() }
        guard let data = defaults.data(forKey: key),
              let events = try? JSONDecoder().decode([TelemetryEvent].self, from: data) else { return [] }
        return events.compactMap(\.sanitized)
    }

    public func save(_ events: [TelemetryEvent]) {
        lock.lock(); defer { lock.unlock() }
        let safeEvents = events.compactMap(\.sanitized)
        guard let data = try? JSONEncoder().encode(safeEvents) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }

    public func purge() {
        lock.lock(); defer { lock.unlock() }
        defaults.removeObject(forKey: key)
    }
}

public final class PersistentTelemetrySink: TelemetrySink, @unchecked Sendable {
    private let storage: any TelemetryEventStorage
    private let retentionDays: Int
    private let clock: @Sendable () -> Date
    private let lock = NSLock()

    public init(
        storage: any TelemetryEventStorage,
        retentionDays: Int = 30,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.storage = storage
        self.retentionDays = max(0, retentionDays)
        self.clock = clock
        pruneExpired(at: clock())
    }

    public func record(_ event: TelemetryEvent) {
        guard let event = event.sanitized else { return }
        lock.lock(); defer { lock.unlock() }
        pruneExpiredLocked(at: clock())
        let cutoff = cutoffDate
        guard event.timestamp >= cutoff else { return }
        var events = storage.load()
        events.append(event)
        storage.save(events)
    }

    public var events: [TelemetryEvent] { events(asOf: clock()) }

    public func events(asOf date: Date) -> [TelemetryEvent] {
        lock.lock(); defer { lock.unlock() }
        pruneExpiredLocked(at: date)
        return storage.load()
    }

    public func pruneExpired(at date: Date) {
        lock.lock(); defer { lock.unlock() }
        pruneExpiredLocked(at: date)
    }

    public func purge() {
        lock.lock(); defer { lock.unlock() }
        storage.purge()
    }

    private var cutoffDate: Date {
        clock().addingTimeInterval(TimeInterval(-retentionDays * 24 * 60 * 60))
    }

    private func pruneExpiredLocked(at date: Date) {
        let cutoff = date.addingTimeInterval(TimeInterval(-retentionDays * 24 * 60 * 60))
        let safeEvents = storage.load().compactMap(\.sanitized).filter { $0.timestamp >= cutoff }
        storage.save(safeEvents)
    }
}

public final class TelemetryManager: @unchecked Sendable {
    private let storage: any TelemetryOptInStorage
    private let sink: any TelemetrySink
    private let lock = NSLock()

    public init(storage: any TelemetryOptInStorage, sink: any TelemetrySink) {
        self.storage = storage
        self.sink = sink
        if storage.isOptedIn() {
            sink.pruneExpired(at: Date())
        } else {
            sink.purge()
        }
    }

    public var isOptedIn: Bool { storage.isOptedIn() }

    public func setOptedIn(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        storage.setOptedIn(value)
        if value {
            sink.pruneExpired(at: Date())
        } else {
            sink.purge()
        }
    }

    public func record(_ event: TelemetryEvent) {
        lock.lock(); defer { lock.unlock() }
        guard storage.isOptedIn() else { return }
        sink.record(event)
    }

    public func record(name: String, properties: [String: String] = [:]) {
        record(TelemetryEvent(name: name, properties: properties))
    }

    public func deleteStoredEvents() {
        lock.lock(); defer { lock.unlock() }
        sink.purge()
    }
}
