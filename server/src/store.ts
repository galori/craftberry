import { DurableObject } from "cloudflare:workers";

export type AppAttestEnvironment = "development" | "production";
export type QuotaWindow = "minute" | "hour" | "day";

export interface QuotaPolicy {
	perMinute: number;
	perHour: number;
	perDay: number;
}

export const DEFAULT_QUOTA: QuotaPolicy = { perMinute: 5, perHour: 10, perDay: 30 };
export const QUOTA_RETRY_AFTER: Record<QuotaWindow, number> = {
	minute: 60,
	hour: 3_600,
	day: 86_400,
};

/** A provider call that has not finished within this time is treated as abandoned and may be retried. */
export const PROCESSING_TIMEOUT_MS = 120_000;
const DAY_MS = 86_400_000;
/** shortcut: fixed per-client challenge cap, tune when real traffic shows the right number. */
export const CHALLENGE_RATE_LIMIT_PER_MINUTE = 30;
/** shortcut: fixed per-client enroll cap, tune when real traffic shows the right number. */
export const ENROLL_RATE_LIMIT_PER_MINUTE = 10;
const MAX_OUTSTANDING_CHALLENGES = 20_000;

export interface Credential {
	keyID: string;
	publicKeyDer: Uint8Array;
	appId: string;
	environment: AppAttestEnvironment;
	counter: number;
}

export interface Registration {
	challengeID: string;
	installationID: string;
	keyID: string;
	publicKeyDer: Uint8Array;
	receipt: Uint8Array;
	appId: string;
	environment: AppAttestEnvironment;
	counter: number;
	tokenDigest: Uint8Array;
	now: number;
}

export type Reservation =
	| { kind: "reserved"; reservationID: string }
	| { kind: "replay"; response: string }
	| { kind: "inProgress" }
	| { kind: "idempotencyConflict" }
	| { kind: "limited"; window: QuotaWindow };

export type ChallengeResult = "ok" | "rate_limited" | "full";

const SCHEMA = [
	`CREATE TABLE IF NOT EXISTS challenges (
		challenge_id TEXT PRIMARY KEY NOT NULL,
		challenge BLOB NOT NULL,
		expires_at INTEGER NOT NULL
	)`,
	`CREATE TABLE IF NOT EXISTS challenge_requests (
		client_key TEXT NOT NULL,
		occurred_at INTEGER NOT NULL
	)`,
	`CREATE INDEX IF NOT EXISTS challenge_requests_client ON challenge_requests(client_key, occurred_at)`,
	`CREATE TABLE IF NOT EXISTS installations (
		installation_id TEXT PRIMARY KEY NOT NULL,
		key_id TEXT UNIQUE NOT NULL,
		public_key BLOB NOT NULL,
		app_identifier TEXT NOT NULL,
		environment TEXT NOT NULL,
		enrolled_at INTEGER NOT NULL,
		attestation_receipt BLOB,
		assertion_counter INTEGER NOT NULL DEFAULT 0
	)`,
	`CREATE TABLE IF NOT EXISTS sessions (
		token_digest BLOB PRIMARY KEY NOT NULL,
		installation_id TEXT NOT NULL REFERENCES installations(installation_id),
		created_at INTEGER NOT NULL
	)`,
	`CREATE TABLE IF NOT EXISTS generation_events (
		installation_id TEXT NOT NULL REFERENCES installations(installation_id),
		idempotency_key TEXT NOT NULL,
		request_fingerprint TEXT NOT NULL,
		occurred_at INTEGER NOT NULL,
		updated_at INTEGER NOT NULL,
		state TEXT NOT NULL,
		response TEXT,
		reservation_id TEXT,
		PRIMARY KEY (installation_id, idempotency_key)
	)`,
	`CREATE TABLE IF NOT EXISTS quota_events (
		event_id INTEGER PRIMARY KEY AUTOINCREMENT,
		installation_id TEXT NOT NULL REFERENCES installations(installation_id),
		idempotency_key TEXT NOT NULL,
		occurred_at INTEGER NOT NULL
	)`,
	`CREATE INDEX IF NOT EXISTS quota_events_install_time ON quota_events(installation_id, occurred_at)`,
];

function bytes(value: unknown): Uint8Array {
	return new Uint8Array(value as ArrayBuffer);
}

/**
 * One Durable Object instance holds all state, so every method below runs to completion
 * before another request touches the database (no awaits inside a method). That gives the
 * same single-writer guarantee the Swift store got from a process lock plus BEGIN IMMEDIATE.
 */
export class GenerationStore extends DurableObject<Env> {
	private readonly sql: SqlStorage;

	constructor(ctx: DurableObjectState, env: Env) {
		super(ctx, env);
		this.sql = ctx.storage.sql;
		for (const statement of SCHEMA) this.sql.exec(statement);
	}

	createChallenge(input: {
		id: string;
		challenge: Uint8Array;
		expiresAt: number;
		now: number;
		clientKey: string;
	}): ChallengeResult {
		return this.ctx.storage.transactionSync(() => {
			this.sql.exec("DELETE FROM challenges WHERE expires_at <= ?", input.now);
			this.sql.exec("DELETE FROM challenge_requests WHERE occurred_at <= ?", input.now - 60_000);
			const recent = this.sql
				.exec("SELECT COUNT(*) AS n FROM challenge_requests WHERE client_key = ?", input.clientKey)
				.one().n as number;
			if (recent >= CHALLENGE_RATE_LIMIT_PER_MINUTE) return "rate_limited";
			const outstanding = this.sql.exec("SELECT COUNT(*) AS n FROM challenges").one().n as number;
			if (outstanding >= MAX_OUTSTANDING_CHALLENGES) return "full";
			this.sql.exec(
				"INSERT INTO challenge_requests(client_key, occurred_at) VALUES(?, ?)",
				input.clientKey,
				input.now,
			);
			this.sql.exec(
				"INSERT INTO challenges(challenge_id, challenge, expires_at) VALUES(?, ?, ?)",
				input.id,
				input.challenge,
				input.expiresAt,
			);
			return "ok";
		});
	}

	/** Counts an enroll attempt for this client (shares the 1-minute window table) and says whether it may proceed. */
	allowEnroll(clientKey: string, now: number): boolean {
		return this.ctx.storage.transactionSync(() => {
			this.sql.exec("DELETE FROM challenge_requests WHERE occurred_at <= ?", now - 60_000);
			const key = `enroll:${clientKey}`;
			const recent = this.sql
				.exec("SELECT COUNT(*) AS n FROM challenge_requests WHERE client_key = ?", key)
				.one().n as number;
			if (recent >= ENROLL_RATE_LIMIT_PER_MINUTE) return false;
			this.sql.exec(
				"INSERT INTO challenge_requests(client_key, occurred_at) VALUES(?, ?)",
				key,
				now,
			);
			return true;
		});
	}

	deleteChallenge(id: string): void {
		this.sql.exec("DELETE FROM challenges WHERE challenge_id = ?", id);
	}

	getChallenge(id: string, now: number): { challenge: Uint8Array; expiresAt: number } | null {
		const rows = this.sql
			.exec(
				"SELECT challenge, expires_at FROM challenges WHERE challenge_id = ? AND expires_at > ?",
				id,
				now,
			)
			.toArray();
		if (rows.length === 0) return null;
		return { challenge: bytes(rows[0].challenge), expiresAt: rows[0].expires_at as number };
	}

	registerInstallation(input: Registration): boolean {
		return this.ctx.storage.transactionSync(() => {
			const challenge = this.sql
				.exec(
					"SELECT 1 FROM challenges WHERE challenge_id = ? AND expires_at > ?",
					input.challengeID,
					input.now,
				)
				.toArray();
			if (challenge.length === 0) return false;
			const key = this.sql
				.exec("SELECT 1 FROM installations WHERE key_id = ?", input.keyID)
				.toArray();
			if (key.length > 0) return false;
			this.sql.exec(
				"INSERT INTO installations(installation_id, key_id, public_key, app_identifier, environment, enrolled_at, attestation_receipt, assertion_counter) VALUES(?, ?, ?, ?, ?, ?, ?, ?)",
				input.installationID,
				input.keyID,
				input.publicKeyDer,
				input.appId,
				input.environment,
				input.now,
				input.receipt,
				input.counter,
			);
			this.sql.exec(
				"INSERT INTO sessions(token_digest, installation_id, created_at) VALUES(?, ?, ?)",
				input.tokenDigest,
				input.installationID,
				input.now,
			);
			this.sql.exec("DELETE FROM challenges WHERE challenge_id = ?", input.challengeID);
			return true;
		});
	}

	installationForToken(digest: Uint8Array): string | null {
		const rows = this.sql
			.exec("SELECT installation_id FROM sessions WHERE token_digest = ?", digest)
			.toArray();
		return rows.length === 0 ? null : (rows[0].installation_id as string);
	}

	credential(installationID: string): Credential | null {
		const rows = this.sql
			.exec(
				"SELECT key_id, public_key, app_identifier, environment, assertion_counter FROM installations WHERE installation_id = ?",
				installationID,
			)
			.toArray();
		if (rows.length === 0) return null;
		const row = rows[0];
		return {
			keyID: row.key_id as string,
			publicKeyDer: bytes(row.public_key),
			appId: row.app_identifier as string,
			environment: row.environment as AppAttestEnvironment,
			counter: row.assertion_counter as number,
		};
	}

	/** Consumes the assertion challenge and advances the counter in one step, or changes nothing. */
	consumeAssertion(input: {
		challengeID: string;
		installationID: string;
		expectedCounter: number;
		newCounter: number;
		now: number;
	}): boolean {
		return this.ctx.storage.transactionSync(() => {
			const challenge = this.sql
				.exec(
					"SELECT 1 FROM challenges WHERE challenge_id = ? AND expires_at > ?",
					input.challengeID,
					input.now,
				)
				.toArray();
			if (challenge.length === 0) return false;
			const updated = this.sql.exec(
				"UPDATE installations SET assertion_counter = ? WHERE installation_id = ? AND assertion_counter = ? AND assertion_counter < ?",
				input.newCounter,
				input.installationID,
				input.expectedCounter,
				input.newCounter,
			);
			if (updated.rowsWritten !== 1) return false;
			this.sql.exec("DELETE FROM challenges WHERE challenge_id = ?", input.challengeID);
			return true;
		});
	}

	reserveGeneration(input: {
		installationID: string;
		idempotencyKey: string;
		fingerprint: string;
		now: number;
		quota: QuotaPolicy;
	}): Reservation {
		return this.ctx.storage.transactionSync((): Reservation => {
			const { installationID: id, idempotencyKey: key, now, quota } = input;
			this.sql.exec(
				"DELETE FROM generation_events WHERE installation_id = ? AND updated_at <= ?",
				id,
				now - DAY_MS,
			);
			this.sql.exec(
				"DELETE FROM quota_events WHERE installation_id = ? AND occurred_at <= ?",
				id,
				now - DAY_MS,
			);

			const existing = this.sql
				.exec(
					"SELECT request_fingerprint, state, response, updated_at FROM generation_events WHERE installation_id = ? AND idempotency_key = ?",
					id,
					key,
				)
				.toArray();
			const isRetry = existing.length > 0;
			if (isRetry) {
				const row = existing[0];
				if (row.request_fingerprint !== input.fingerprint) return { kind: "idempotencyConflict" };
				if (row.state === "completed") return { kind: "replay", response: row.response as string };
				if (
					row.state === "processing" &&
					(row.updated_at as number) > now - PROCESSING_TIMEOUT_MS
				) {
					return { kind: "inProgress" };
				}
			}

			const count = (since: number) =>
				this.sql
					.exec(
						"SELECT COUNT(*) AS n FROM quota_events WHERE installation_id = ? AND occurred_at > ?",
						id,
						since,
					)
					.one().n as number;
			if (count(now - 60_000) >= quota.perMinute) return { kind: "limited", window: "minute" };
			if (count(now - 3_600_000) >= quota.perHour) return { kind: "limited", window: "hour" };
			if (count(now - DAY_MS) >= quota.perDay) return { kind: "limited", window: "day" };

			const reservationID = crypto.randomUUID();
			if (isRetry) {
				this.sql.exec(
					"UPDATE generation_events SET state = 'processing', updated_at = ?, reservation_id = ? WHERE installation_id = ? AND idempotency_key = ?",
					now,
					reservationID,
					id,
					key,
				);
			} else {
				this.sql.exec(
					"INSERT INTO generation_events(installation_id, idempotency_key, request_fingerprint, occurred_at, updated_at, state, response, reservation_id) VALUES(?, ?, ?, ?, ?, 'processing', NULL, ?)",
					id,
					key,
					input.fingerprint,
					now,
					now,
					reservationID,
				);
			}
			this.sql.exec(
				"INSERT INTO quota_events(installation_id, idempotency_key, occurred_at) VALUES(?, ?, ?)",
				id,
				key,
				now,
			);
			return { kind: "reserved", reservationID };
		});
	}

	completeGeneration(input: {
		installationID: string;
		idempotencyKey: string;
		reservationID: string;
		response: string;
		now: number;
	}): boolean {
		const result = this.sql.exec(
			"UPDATE generation_events SET state = 'completed', response = ?, updated_at = ? WHERE installation_id = ? AND idempotency_key = ? AND reservation_id = ? AND state = 'processing'",
			input.response,
			input.now,
			input.installationID,
			input.idempotencyKey,
			input.reservationID,
		);
		return result.rowsWritten === 1;
	}

	markGenerationRetryable(input: {
		installationID: string;
		idempotencyKey: string;
		reservationID: string;
		now: number;
	}): boolean {
		const result = this.sql.exec(
			"UPDATE generation_events SET state = 'retryable', updated_at = ?, reservation_id = NULL WHERE installation_id = ? AND idempotency_key = ? AND reservation_id = ? AND state = 'processing'",
			input.now,
			input.installationID,
			input.idempotencyKey,
			input.reservationID,
		);
		return result.rowsWritten === 1;
	}
}

/** The generated Env types do not carry the class, so the stub type is restored here. */
export function storeStub(env: Env, name: string): DurableObjectStub<GenerationStore> {
	return env.STORE.get(env.STORE.idFromName(name)) as unknown as DurableObjectStub<GenerationStore>;
}
