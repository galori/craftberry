import Foundation

public enum QuotaError: LocalizedError, Equatable {
    case quotaExceeded(String)
    case abuseDetected(String)
    case promptTooLong(Int)

    public var errorDescription: String? {
        switch self {
        case .quotaExceeded(let detail): detail
        case .abuseDetected(let detail): detail
        case .promptTooLong(let limit): "Prompt exceeds \(limit) characters."
        }
    }
}

public struct QuotaPolicy: Equatable, Sendable {
    public let maxGenerationsPerHour: Int
    public let maxGenerationsPerDay: Int
    public let maxPromptCharacters: Int
    public let abuseThresholdPerMinute: Int

    public init(
        maxGenerationsPerHour: Int = 10,
        maxGenerationsPerDay: Int = 30,
        maxPromptCharacters: Int = 600,
        abuseThresholdPerMinute: Int = 5
    ) {
        self.maxGenerationsPerHour = maxGenerationsPerHour
        self.maxGenerationsPerDay = maxGenerationsPerDay
        self.maxPromptCharacters = maxPromptCharacters
        self.abuseThresholdPerMinute = abuseThresholdPerMinute
    }

    public static let `default` = QuotaPolicy()
    public static let permissiveForTests = QuotaPolicy(
        maxGenerationsPerHour: 1_000,
        maxGenerationsPerDay: 10_000,
        maxPromptCharacters: 10_000,
        abuseThresholdPerMinute: 1_000
    )
}

public protocol QuotaClock: Sendable {
    func now() -> Date
}

public struct SystemQuotaClock: QuotaClock {
    public init() {}
    public func now() -> Date { Date() }
}

public actor QuotaGate {
    private let policy: QuotaPolicy
    private let clock: any QuotaClock
    private var timestamps: [Date] = []

    public init(policy: QuotaPolicy = .default, clock: any QuotaClock = SystemQuotaClock()) {
        self.policy = policy
        self.clock = clock
    }

    public func canGenerate(prompt: String) throws {
        if prompt.count > policy.maxPromptCharacters {
            throw QuotaError.promptTooLong(policy.maxPromptCharacters)
        }
        let now = clock.now()
        prune(now: now)
        let hourAgo = now.addingTimeInterval(-3600)
        let dayAgo = now.addingTimeInterval(-86_400)
        let minuteAgo = now.addingTimeInterval(-60)
        let perHour = timestamps.filter { $0 > hourAgo }.count
        if perHour >= policy.maxGenerationsPerHour {
            throw QuotaError.quotaExceeded("Hourly quota exceeded (\(policy.maxGenerationsPerHour)/hour).")
        }
        let perDay = timestamps.filter { $0 > dayAgo }.count
        if perDay >= policy.maxGenerationsPerDay {
            throw QuotaError.quotaExceeded("Daily quota exceeded (\(policy.maxGenerationsPerDay)/day).")
        }
        let perMinute = timestamps.filter { $0 > minuteAgo }.count
        if perMinute >= policy.abuseThresholdPerMinute {
            throw QuotaError.abuseDetected("Too many requests — please wait a minute.")
        }
    }

    public func recordGeneration() {
        timestamps.append(clock.now())
    }

    public func checkAndRecord(prompt: String) throws {
        try canGenerate(prompt: prompt)
        timestamps.append(clock.now())
    }

    public func reset() {
        timestamps.removeAll()
    }

    public var count: Int { timestamps.count }

    private func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-86_400)
        timestamps.removeAll { $0 < cutoff }
    }
}

public actor QuotaGatedLLMClient: LLMClient {
    private let wrapped: any LLMClient
    private let gate: QuotaGate

    public init(wrapping wrapped: any LLMClient, gate: QuotaGate) {
        self.wrapped = wrapped
        self.gate = gate
    }

    public func generateProject(from prompt: String) async throws -> ProjectGeneration {
        try await gate.checkAndRecord(prompt: prompt)
        return try await wrapped.generateProject(from: prompt)
    }
}
