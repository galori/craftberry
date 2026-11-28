import { describe, expect, it } from "vite-plus/test";
import {
	CHALLENGE_RATE_LIMIT_PER_MINUTE,
	DEFAULT_QUOTA,
	PROCESSING_TIMEOUT_MS,
} from "../src/store";
import { freshStore } from "./helpers";

const T0 = 1_800_000_000_000;
const bytes = (...values: number[]) => new Uint8Array(values);

function arm(
	store: ReturnType<typeof freshStore>,
	id: string,
	now = T0,
	ttl = 300_000,
	clientKey = "k",
) {
	return store.createChallenge({ id, challenge: bytes(1), expiresAt: now + ttl, now, clientKey });
}

async function installation(store = freshStore(), now = T0) {
	const challengeID = crypto.randomUUID();
	await arm(store, challengeID, now);
	const installationID = crypto.randomUUID();
	const ok = await store.registerInstallation({
		challengeID,
		installationID,
		keyID: `key-${installationID}`,
		publicKeyDer: bytes(1),
		receipt: bytes(2),
		appId: "app",
		environment: "development",
		counter: 0,
		tokenDigest: crypto.getRandomValues(new Uint8Array(32)),
		now,
	});
	expect(ok).toBe(true);
	return { store, installationID };
}

type Inst = Awaited<ReturnType<typeof installation>>;

const reserve = (s: Inst, key: string, now: number, fingerprint = "fp") =>
	s.store.reserveGeneration({
		installationID: s.installationID,
		idempotencyKey: key,
		fingerprint,
		now,
		quota: DEFAULT_QUOTA,
	});

describe("quota", () => {
	it("limits to 5 per minute, then frees the window", async () => {
		const s = await installation();
		for (let i = 0; i < 5; i++) expect((await reserve(s, `k${i}`, T0 + i)).kind).toBe("reserved");
		expect(await reserve(s, "k5", T0 + 10)).toEqual({ kind: "limited", window: "minute" });
		expect((await reserve(s, "k5", T0 + 61_000)).kind).toBe("reserved");
	});

	it("limits to 10 per hour", async () => {
		const s = await installation();
		for (let i = 0; i < 10; i++) {
			expect((await reserve(s, `h${i}`, T0 + Math.floor(i / 5) * 120_000)).kind).toBe("reserved");
		}
		expect(await reserve(s, "h10", T0 + 300_000)).toEqual({ kind: "limited", window: "hour" });
	});

	it("limits to 30 per day", async () => {
		const s = await installation();
		for (let i = 0; i < 30; i++) {
			const at = T0 + Math.floor(i / 10) * 3_700_000 + Math.floor((i % 10) / 5) * 120_000;
			expect((await reserve(s, `d${i}`, at)).kind).toBe("reserved");
		}
		expect(await reserve(s, "d30", T0 + 3 * 3_700_000)).toEqual({ kind: "limited", window: "day" });
	});

	it("is per installation", async () => {
		const a = await installation();
		const b = await installation();
		for (let i = 0; i < 5; i++) await reserve(a, `k${i}`, T0);
		expect((await reserve(a, "x", T0)).kind).toBe("limited");
		expect((await reserve(b, "x", T0)).kind).toBe("reserved");
	});

	it("stays atomic under concurrent reservations", async () => {
		const s = await installation();
		const results = await Promise.all(
			Array.from({ length: 12 }, (_, i) => reserve(s, `c${i}`, T0)),
		);
		expect(results.filter((r) => r.kind === "reserved")).toHaveLength(5);
		expect(results.filter((r) => r.kind === "limited")).toHaveLength(7);
	});
});

describe("idempotency", () => {
	it("replays a completed result without spending quota", async () => {
		const s = await installation();
		const first = await reserve(s, "key", T0);
		if (first.kind !== "reserved") throw new Error("expected reservation");
		await s.store.completeGeneration({
			installationID: s.installationID,
			idempotencyKey: "key",
			reservationID: first.reservationID,
			response: '{"ok":1}',
			now: T0,
		});
		for (let i = 0; i < 20; i++) {
			expect(await reserve(s, "key", T0 + 1)).toEqual({ kind: "replay", response: '{"ok":1}' });
		}
		expect((await reserve(s, "other", T0 + 2)).kind).toBe("reserved");
	});

	it("rejects a different request under the same key", async () => {
		const s = await installation();
		await reserve(s, "key", T0, "one");
		expect(await reserve(s, "key", T0, "two")).toEqual({ kind: "idempotencyConflict" });
	});

	it("reports in progress, then allows a retry once the attempt is abandoned", async () => {
		const s = await installation();
		await reserve(s, "key", T0);
		expect(await reserve(s, "key", T0 + 1_000)).toEqual({ kind: "inProgress" });
		expect((await reserve(s, "key", T0 + PROCESSING_TIMEOUT_MS + 1)).kind).toBe("reserved");
	});

	it("a retryable attempt reserves a new quota event; a stale reservation cannot complete", async () => {
		const s = await installation();
		const first = await reserve(s, "key", T0);
		if (first.kind !== "reserved") throw new Error("expected reservation");
		const marked = await s.store.markGenerationRetryable({
			installationID: s.installationID,
			idempotencyKey: "key",
			reservationID: first.reservationID,
			now: T0,
		});
		expect(marked).toBe(true);
		expect((await reserve(s, "key", T0 + 1)).kind).toBe("reserved");
		const stale = await s.store.completeGeneration({
			installationID: s.installationID,
			idempotencyKey: "key",
			reservationID: first.reservationID,
			response: "{}",
			now: T0 + 2,
		});
		expect(stale).toBe(false);
		// two attempts with one key used two of the five per-minute events
		for (let i = 0; i < 3; i++) expect((await reserve(s, `n${i}`, T0 + 3)).kind).toBe("reserved");
		expect((await reserve(s, "n3", T0 + 3)).kind).toBe("limited");
	});
});

describe("challenges, sessions and assertions", () => {
	it("expires challenges", async () => {
		const store = freshStore();
		await arm(store, "c1", T0, 1_000);
		expect(await store.getChallenge("c1", T0 + 500)).not.toBeNull();
		expect(await store.getChallenge("c1", T0 + 1_000)).toBeNull();
	});

	it("registers once per key and resolves sessions by digest", async () => {
		const store = freshStore();
		const digest = crypto.getRandomValues(new Uint8Array(32));
		await arm(store, "c1");
		await arm(store, "c2");
		const base = {
			keyID: "same-key",
			publicKeyDer: bytes(1),
			receipt: bytes(1),
			appId: "a",
			environment: "development" as const,
			counter: 0,
			now: T0,
		};
		expect(
			await store.registerInstallation({
				...base,
				challengeID: "c1",
				installationID: "i1",
				tokenDigest: digest,
			}),
		).toBe(true);
		const other = crypto.getRandomValues(new Uint8Array(32));
		expect(
			await store.registerInstallation({
				...base,
				challengeID: "c2",
				installationID: "i2",
				tokenDigest: other,
			}),
		).toBe(false);
		expect(await store.installationForToken(digest)).toBe("i1");
		expect(await store.installationForToken(new Uint8Array(32))).toBeNull();
		expect(await store.getChallenge("c1", T0)).toBeNull();
	});

	it("advances the counter only from the expected value and burns the challenge", async () => {
		const s = await installation();
		await arm(s.store, "a1");
		const input = {
			challengeID: "a1",
			installationID: s.installationID,
			expectedCounter: 0,
			newCounter: 1,
			now: T0,
		};
		expect(await s.store.consumeAssertion(input)).toBe(true);
		expect(await s.store.consumeAssertion(input)).toBe(false);
		await arm(s.store, "a2");
		expect(await s.store.consumeAssertion({ ...input, challengeID: "a2" })).toBe(false);
		expect((await s.store.credential(s.installationID))?.counter).toBe(1);
		expect(await s.store.getChallenge("a2", T0)).not.toBeNull();
	});

	it("rate-limits challenge issuance per client", async () => {
		const store = freshStore();
		for (let i = 0; i < CHALLENGE_RATE_LIMIT_PER_MINUTE; i++) {
			expect(await arm(store, `r${i}`, T0, 5_000, "ip")).toBe("ok");
		}
		expect(await arm(store, "over", T0, 5_000, "ip")).toBe("rate_limited");
		expect(await arm(store, "other", T0, 5_000, "ip2")).toBe("ok");
		expect(await arm(store, "later", T0 + 61_000, 30_000, "ip")).toBe("ok");
	});
});
