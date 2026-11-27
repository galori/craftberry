import CSQLite
import Foundation

/// SQLite adapter for a single-host deployment. `BEGIN IMMEDIATE` serializes quota
/// decisions across service instances, and committed reservations survive restarts.
public actor SQLiteGenerationServiceStore: GenerationServiceStore {
    private let connection: SQLiteConnection
    private let processID: String
    private var database: OpaquePointer { connection.handle }

    public init(databaseURL: URL, processID: String? = nil) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let connection = try SQLiteConnection(url: databaseURL)
        self.connection = connection
        self.processID = processID ?? GenerationStoreProcessIdentity.current
        let handle = connection.handle
        try Self.execute("PRAGMA journal_mode=WAL", on: handle)
        try Self.execute("PRAGMA synchronous=FULL", on: handle)
        try Self.execute("PRAGMA foreign_keys=ON", on: handle)
        try Self.execute("PRAGMA busy_timeout=5000", on: handle)
        try Self.execute("BEGIN IMMEDIATE", on: handle)
        do {
            try Self.execute("""
            CREATE TABLE IF NOT EXISTS enrollment_challenges (
                challenge_id TEXT PRIMARY KEY NOT NULL,
                challenge BLOB NOT NULL,
                expires_at REAL NOT NULL
            )
            """, on: handle)
            try Self.execute("""
            CREATE TABLE IF NOT EXISTS installations (
                installation_id TEXT PRIMARY KEY NOT NULL,
                key_id TEXT UNIQUE NOT NULL,
                public_key BLOB NOT NULL,
                app_identifier TEXT NOT NULL,
                environment TEXT NOT NULL,
                bundle_version TEXT NOT NULL,
                enrolled_at REAL NOT NULL,
                attestation_receipt BLOB,
                assertion_counter INTEGER NOT NULL DEFAULT 0
            )
            """, on: handle)
            if try !Self.tableHasColumn("attestation_receipt", table: "installations", on: handle) {
                try Self.execute("ALTER TABLE installations ADD COLUMN attestation_receipt BLOB", on: handle)
            }
            if try !Self.tableHasColumn("assertion_counter", table: "installations", on: handle) {
                try Self.execute(
                    "ALTER TABLE installations ADD COLUMN assertion_counter INTEGER NOT NULL DEFAULT 0",
                    on: handle
                )
            }
            try Self.execute("""
            CREATE TABLE IF NOT EXISTS generation_sessions (
                token_digest BLOB PRIMARY KEY NOT NULL,
                installation_id TEXT NOT NULL REFERENCES installations(installation_id),
                created_at REAL NOT NULL
            )
            """, on: handle)
            try Self.execute("""
            CREATE TABLE IF NOT EXISTS generation_events (
                installation_id TEXT NOT NULL REFERENCES installations(installation_id),
                idempotency_key TEXT NOT NULL,
                request_fingerprint BLOB NOT NULL,
                occurred_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                state TEXT NOT NULL,
                response BLOB,
                reservation_id TEXT,
                owner_id TEXT,
                PRIMARY KEY (installation_id, idempotency_key)
            )
            """, on: handle)
            if try !Self.tableHasColumn("reservation_id", table: "generation_events", on: handle) {
                try Self.execute("ALTER TABLE generation_events ADD COLUMN reservation_id TEXT", on: handle)
            }
            if try !Self.tableHasColumn("owner_id", table: "generation_events", on: handle) {
                try Self.execute("ALTER TABLE generation_events ADD COLUMN owner_id TEXT", on: handle)
            }
            try Self.execute("CREATE INDEX IF NOT EXISTS generation_events_install_time ON generation_events(installation_id, occurred_at)", on: handle)
            let quotaEventsTableExisted = try Self.tableExists("generation_quota_events", on: handle)
            try Self.execute("""
            CREATE TABLE IF NOT EXISTS generation_quota_events (
                event_id INTEGER PRIMARY KEY AUTOINCREMENT,
                installation_id TEXT NOT NULL REFERENCES installations(installation_id),
                idempotency_key TEXT NOT NULL,
                occurred_at REAL NOT NULL
            )
            """, on: handle)
            try Self.execute(
                "CREATE INDEX IF NOT EXISTS generation_quota_events_install_time ON generation_quota_events(installation_id, occurred_at)",
                on: handle
            )
            if !quotaEventsTableExisted {
                try Self.execute("""
                INSERT INTO generation_quota_events(installation_id, idempotency_key, occurred_at)
                SELECT installation_id, idempotency_key, occurred_at FROM generation_events
                """, on: handle)
            }
            try Self.execute("COMMIT", on: handle)
        } catch {
            try? Self.execute("ROLLBACK", on: handle)
            throw error
        }
    }

    public func createEnrollmentChallenge(_ challenge: StoredEnrollmentChallenge, now: Date) async throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try run("DELETE FROM enrollment_challenges WHERE expires_at <= ?", [.double(now.timeIntervalSince1970)])
            try run(
                "INSERT INTO enrollment_challenges(challenge_id, challenge, expires_at) VALUES(?, ?, ?)",
                [.text(challenge.id), .blob(challenge.challenge), .double(challenge.expiresAt.timeIntervalSince1970)]
            )
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    public func enrollmentChallenge(id: String, now: Date) async throws -> StoredEnrollmentChallenge? {
        let statement = try prepare(
            "SELECT challenge, expires_at FROM enrollment_challenges WHERE challenge_id = ? AND expires_at > ?",
            [.text(id), .double(now.timeIntervalSince1970)]
        )
        defer { sqlite3_finalize(statement) }
        guard try stepHasRow(statement) else { return nil }
        guard let challenge = columnData(statement, 0) else {
            throw SQLiteGenerationServiceStoreError.database("Enrollment challenge has no stored bytes.")
        }
        return StoredEnrollmentChallenge(
            id: id,
            challenge: challenge,
            expiresAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
        )
    }

    public func registerInstallation(
        challengeID: String,
        registration: GenerationInstallationRegistration,
        tokenDigest: Data,
        now: Date
    ) async throws -> Bool {
        try execute("BEGIN IMMEDIATE")
        do {
            let hasChallenge = try exists(
                "SELECT 1 FROM enrollment_challenges WHERE challenge_id = ? AND expires_at > ?",
                [.text(challengeID), .double(now.timeIntervalSince1970)]
            )
            guard hasChallenge else {
                try execute("ROLLBACK")
                return false
            }

            let keyExists = try exists("SELECT 1 FROM installations WHERE key_id = ?", [.text(registration.keyID)])
            guard !keyExists else {
                try execute("ROLLBACK")
                return false
            }

            try run(
                "INSERT INTO installations(installation_id, key_id, public_key, app_identifier, environment, bundle_version, enrolled_at, attestation_receipt) VALUES(?, ?, ?, ?, ?, ?, ?, ?)",
                [
                    .text(registration.installationID.uuidString),
                    .text(registration.keyID),
                    .blob(registration.publicKey),
                    .text(registration.appIdentifier),
                    .text(registration.environment.rawValue),
                    .text(registration.bundleVersion),
                    .double(registration.enrolledAt.timeIntervalSince1970),
                    .blob(registration.receipt)
                ]
            )
            try run(
                "INSERT INTO generation_sessions(token_digest, installation_id, created_at) VALUES(?, ?, ?)",
                [.blob(tokenDigest), .text(registration.installationID.uuidString), .double(now.timeIntervalSince1970)]
            )
            try run("DELETE FROM enrollment_challenges WHERE challenge_id = ?", [.text(challengeID)])
            try execute("COMMIT")
            return true
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    public func installationID(forTokenDigest digest: Data) async throws -> UUID? {
        let statement = try prepare("SELECT installation_id FROM generation_sessions WHERE token_digest = ?", [.blob(digest)])
        defer { sqlite3_finalize(statement) }
        guard try stepHasRow(statement) else { return nil }
        guard let value = columnText(statement, 0), let installationID = UUID(uuidString: value) else {
            throw SQLiteGenerationServiceStoreError.database("Session has an invalid installation identifier.")
        }
        return installationID
    }

    public func appAttestCredential(for installationID: UUID) async throws -> StoredAppAttestCredential? {
        let statement = try prepare(
            "SELECT key_id, public_key, app_identifier, environment, bundle_version, assertion_counter FROM installations WHERE installation_id = ?",
            [.text(installationID.uuidString)]
        )
        defer { sqlite3_finalize(statement) }
        guard try stepHasRow(statement) else { return nil }
        guard let keyID = columnText(statement, 0),
              let publicKey = columnData(statement, 1),
              let appIdentifier = columnText(statement, 2),
              let environmentValue = columnText(statement, 3),
              let environment = AppAttestEnvironment(rawValue: environmentValue),
              let bundleVersion = columnText(statement, 4) else {
            throw SQLiteGenerationServiceStoreError.database("Stored App Attest credential is incomplete.")
        }
        let rawCounter = sqlite3_column_int64(statement, 5)
        guard rawCounter >= 0, rawCounter <= Int64(UInt32.max) else {
            throw SQLiteGenerationServiceStoreError.database("Stored App Attest assertion counter is invalid.")
        }
        return StoredAppAttestCredential(
            installationID: installationID,
            keyID: keyID,
            publicKey: publicKey,
            appIdentifier: appIdentifier,
            environment: environment,
            bundleVersion: bundleVersion,
            assertionCounter: UInt32(rawCounter)
        )
    }

    public func appAttestReceipt(for installationID: UUID) async throws -> Data? {
        let statement = try prepare(
            "SELECT attestation_receipt FROM installations WHERE installation_id = ?",
            [.text(installationID.uuidString)]
        )
        defer { sqlite3_finalize(statement) }
        guard try stepHasRow(statement) else { return nil }
        return columnData(statement, 0)
    }

    public func consumeAppAttestAssertion(
        challengeID: String,
        installationID: UUID,
        expectedCounter: UInt32,
        newCounter: UInt32,
        now: Date
    ) async throws -> Bool {
        try execute("BEGIN IMMEDIATE")
        do {
            let hasChallenge = try exists(
                "SELECT 1 FROM enrollment_challenges WHERE challenge_id = ? AND expires_at > ?",
                [.text(challengeID), .double(now.timeIntervalSince1970)]
            )
            guard hasChallenge else {
                try execute("ROLLBACK")
                return false
            }
            try run(
                "UPDATE installations SET assertion_counter = ? WHERE installation_id = ? AND assertion_counter = ? AND assertion_counter < ?",
                [
                    .integer(Int64(newCounter)),
                    .text(installationID.uuidString),
                    .integer(Int64(expectedCounter)),
                    .integer(Int64(newCounter))
                ]
            )
            guard sqlite3_changes(database) == 1 else {
                try execute("ROLLBACK")
                return false
            }
            try run(
                "DELETE FROM enrollment_challenges WHERE challenge_id = ? AND expires_at > ?",
                [.text(challengeID), .double(now.timeIntervalSince1970)]
            )
            guard sqlite3_changes(database) == 1 else {
                try execute("ROLLBACK")
                return false
            }
            try execute("COMMIT")
            return true
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    public func reserveGeneration(
        installationID: UUID,
        idempotencyKey: String,
        requestFingerprint: Data,
        now: Date,
        quota: GenerationQuotaPolicy
    ) async throws -> GenerationReservation {
        try execute("BEGIN IMMEDIATE")
        var pendingReservationID: UUID?
        do {
            let id = installationID.uuidString
            try run(
                "DELETE FROM generation_events WHERE installation_id = ? AND updated_at <= ? AND (state <> 'processing' OR owner_id IS NULL OR owner_id <> ?)",
                [.text(id), .double(now.timeIntervalSince1970 - 86_400), .text(processID)]
            )
            let existing = try idempotencyRecord(installationID: id, key: idempotencyKey)
            var isRetry = false
            if let existing {
                guard existing.fingerprint == requestFingerprint else {
                    try execute("COMMIT")
                    return .idempotencyConflict
                }
                switch existing.state {
                case .completed(let response, _):
                    try execute("COMMIT")
                    return .replay(response)
                case .processing(_, let existingReservationID, let ownerID)
                    where ownerID == processID
                        && existingReservationID.map({ ActiveGenerationReservationRegistry.shared.contains($0) }) == true:
                    try execute("COMMIT")
                    return .inProgress
                case .processing, .retryable:
                    isRetry = true
                }
            }

            try run("DELETE FROM generation_quota_events WHERE installation_id = ? AND occurred_at <= ?", [
                .text(id), .double(now.timeIntervalSince1970 - 86_400)
            ])
            if try countEvents(installationID: id, after: now.addingTimeInterval(-60)) >= quota.perMinute {
                try execute("COMMIT")
                return .limited(.minute)
            }
            if try countEvents(installationID: id, after: now.addingTimeInterval(-3_600)) >= quota.perHour {
                try execute("COMMIT")
                return .limited(.hour)
            }
            if try countEvents(installationID: id, after: now.addingTimeInterval(-86_400)) >= quota.perDay {
                try execute("COMMIT")
                return .limited(.day)
            }

            let reservationID = UUID()
            if isRetry {
                try run(
                    "UPDATE generation_events SET state = 'processing', updated_at = ?, reservation_id = ?, owner_id = ? WHERE installation_id = ? AND idempotency_key = ?",
                    [.double(now.timeIntervalSince1970), .text(reservationID.uuidString), .text(processID), .text(id), .text(idempotencyKey)]
                )
            } else {
                try run(
                    "INSERT INTO generation_events(installation_id, idempotency_key, request_fingerprint, occurred_at, updated_at, state, response, reservation_id, owner_id) VALUES(?, ?, ?, ?, ?, 'processing', NULL, ?, ?)",
                    [
                        .text(id),
                        .text(idempotencyKey),
                        .blob(requestFingerprint),
                        .double(now.timeIntervalSince1970),
                        .double(now.timeIntervalSince1970),
                        .text(reservationID.uuidString),
                        .text(processID)
                    ]
                )
            }
            try run(
                "INSERT INTO generation_quota_events(installation_id, idempotency_key, occurred_at) VALUES(?, ?, ?)",
                [.text(id), .text(idempotencyKey), .double(now.timeIntervalSince1970)]
            )
            ActiveGenerationReservationRegistry.shared.activate(reservationID)
            pendingReservationID = reservationID
            try execute("COMMIT")
            pendingReservationID = nil
            return .reserved(reservationID)
        } catch {
            if let pendingReservationID {
                ActiveGenerationReservationRegistry.shared.release(pendingReservationID)
            }
            try? execute("ROLLBACK")
            throw error
        }
    }

    public func completeGeneration(
        installationID: UUID,
        idempotencyKey: String,
        reservationID: UUID,
        response: Data,
        now: Date
    ) async throws -> Bool {
        try run(
            "UPDATE generation_events SET state = 'completed', response = ?, updated_at = ? WHERE installation_id = ? AND idempotency_key = ? AND reservation_id = ? AND state = 'processing'",
            [.blob(response), .double(now.timeIntervalSince1970), .text(installationID.uuidString), .text(idempotencyKey), .text(reservationID.uuidString)]
        )
        let completed = sqlite3_changes(database) == 1
        ActiveGenerationReservationRegistry.shared.release(reservationID)
        return completed
    }

    public func markGenerationRetryable(
        installationID: UUID,
        idempotencyKey: String,
        reservationID: UUID,
        now: Date
    ) async throws -> Bool {
        try run(
            "UPDATE generation_events SET state = 'retryable', updated_at = ?, reservation_id = NULL, owner_id = NULL WHERE installation_id = ? AND idempotency_key = ? AND reservation_id = ? AND state = 'processing'",
            [.double(now.timeIntervalSince1970), .text(installationID.uuidString), .text(idempotencyKey), .text(reservationID.uuidString)]
        )
        let markedRetryable = sqlite3_changes(database) == 1
        ActiveGenerationReservationRegistry.shared.release(reservationID)
        return markedRetryable
    }

    public func releaseGenerationAttempt(reservationID: UUID) async {
        ActiveGenerationReservationRegistry.shared.release(reservationID)
    }

    private func idempotencyRecord(installationID: String, key: String) throws -> IdempotencyRecord? {
        let statement = try prepare(
            "SELECT request_fingerprint, state, response, updated_at, reservation_id, owner_id FROM generation_events WHERE installation_id = ? AND idempotency_key = ?",
            [.text(installationID), .text(key)]
        )
        defer { sqlite3_finalize(statement) }
        guard try stepHasRow(statement) else { return nil }
        guard let fingerprint = columnData(statement, 0), let stateText = columnText(statement, 1) else {
            throw SQLiteGenerationServiceStoreError.database("Generation idempotency record is incomplete.")
        }
        let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
        let state: IdempotencyState
        switch stateText {
        case "processing":
            state = .processing(
                updatedAt: updatedAt,
                reservationID: columnText(statement, 4).flatMap(UUID.init(uuidString:)),
                ownerID: columnText(statement, 5)
            )
        case "retryable": state = .retryable(updatedAt: updatedAt)
        case "completed": state = .completed(response: columnData(statement, 2) ?? Data(), updatedAt: updatedAt)
        default: throw SQLiteGenerationServiceStoreError.database("Unknown generation reservation state.")
        }
        return IdempotencyRecord(fingerprint: fingerprint, state: state)
    }

    private func countEvents(installationID: String, after date: Date) throws -> Int {
        let statement = try prepare(
            "SELECT COUNT(*) FROM generation_quota_events WHERE installation_id = ? AND occurred_at > ?",
            [.text(installationID), .double(date.timeIntervalSince1970)]
        )
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw lastError() }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func execute(_ sql: String) throws {
        try Self.execute(sql, on: database)
    }

    private static func execute(_ sql: String, on database: OpaquePointer) throws {
        var attempts = 0
        while true {
            var errorPointer: UnsafeMutablePointer<CChar>?
            let result = sqlite3_exec(database, sql, nil, nil, &errorPointer)
            if result == SQLITE_OK { return }
            let baseResult = result & 0xFF
            if (baseResult == SQLITE_BUSY || baseResult == SQLITE_LOCKED), attempts < 100 {
                sqlite3_free(errorPointer)
                attempts += 1
                Thread.sleep(forTimeInterval: 0.05)
                continue
            }
            let message = errorPointer.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorPointer)
            throw SQLiteGenerationServiceStoreError.database(message)
        }
    }

    private static func tableHasColumn(_ column: String, table: String, on database: OpaquePointer) throws -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw SQLiteGenerationServiceStoreError.database(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let name = sqlite3_column_text(statement, 1) else { continue }
            if String(cString: name) == column { return true }
        }
        return false
    }

    private static func tableExists(_ table: String, on database: OpaquePointer) throws -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw SQLiteGenerationServiceStoreError.database(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        let bindResult = table.withCString {
            sqlite3_bind_text(statement, 1, $0, -1, sqliteTransient)
        }
        guard bindResult == SQLITE_OK else {
            throw SQLiteGenerationServiceStoreError.database(String(cString: sqlite3_errmsg(database)))
        }
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func run(_ sql: String, _ values: [SQLiteValue]) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
    }

    private func prepare(_ sql: String, _ values: [SQLiteValue]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw lastError() }
        for (offset, value) in values.enumerated() {
            guard bind(value, to: statement, at: Int32(offset + 1)) == SQLITE_OK else {
                sqlite3_finalize(statement)
                throw lastError()
            }
        }
        return statement
    }

    private func bind(_ value: SQLiteValue, to statement: OpaquePointer, at index: Int32) -> Int32 {
        switch value {
        case .text(let string):
            return string.withCString { sqlite3_bind_text(statement, index, $0, -1, sqliteTransient) }
        case .blob(let data):
            return data.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(data.count), sqliteTransient)
            }
        case .double(let number):
            return sqlite3_bind_double(statement, index, number)
        case .integer(let number):
            return sqlite3_bind_int64(statement, index, number)
        }
    }

    private func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: text)
    }

    private func columnData(_ statement: OpaquePointer, _ index: Int32) -> Data? {
        guard let pointer = sqlite3_column_blob(statement, index) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, index))
        return Data(bytes: pointer, count: count)
    }

    private func lastError() -> SQLiteGenerationServiceStoreError {
        SQLiteGenerationServiceStoreError.database(String(cString: sqlite3_errmsg(database)))
    }

    private func stepHasRow(_ statement: OpaquePointer) throws -> Bool {
        let result = sqlite3_step(statement)
        if result == SQLITE_ROW { return true }
        if result == SQLITE_DONE { return false }
        throw lastError()
    }

    private func exists(_ sql: String, _ values: [SQLiteValue]) throws -> Bool {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        return try stepHasRow(statement)
    }
}

private final class SQLiteConnection: @unchecked Sendable {
    let handle: OpaquePointer

    init(url: URL) throws {
        var database: OpaquePointer?
        let result = url.path.withCString { path in
            sqlite3_open_v2(
                path,
                &database,
                SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                nil
            )
        }
        guard result == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let database { sqlite3_close(database) }
            throw SQLiteGenerationServiceStoreError.database(message)
        }
        handle = database
    }

    deinit { sqlite3_close(handle) }
}

public enum SQLiteGenerationServiceStoreError: LocalizedError {
    case database(String)
    case missingReservation

    public var errorDescription: String? {
        switch self {
        case .database(let detail): "SQLite generation store error: \(detail)"
        case .missingReservation: "Generation reservation no longer exists."
        }
    }
}

private enum SQLiteValue {
    case text(String)
    case blob(Data)
    case double(Double)
    case integer(Int64)
}

private enum IdempotencyState {
    case processing(updatedAt: Date, reservationID: UUID?, ownerID: String?)
    case retryable(updatedAt: Date)
    case completed(response: Data, updatedAt: Date)
}

private enum GenerationStoreProcessIdentity {
    static let current = UUID().uuidString.lowercased()
}

private final class ActiveGenerationReservationRegistry: @unchecked Sendable {
    static let shared = ActiveGenerationReservationRegistry()

    private let lock = NSLock()
    private var activeReservations: Set<UUID> = []

    func activate(_ reservationID: UUID) {
        lock.lock()
        activeReservations.insert(reservationID)
        lock.unlock()
    }

    func contains(_ reservationID: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeReservations.contains(reservationID)
    }

    func release(_ reservationID: UUID) {
        lock.lock()
        activeReservations.remove(reservationID)
        lock.unlock()
    }
}

private struct IdempotencyRecord {
    let fingerprint: Data
    let state: IdempotencyState
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
