import { describe, expect, it } from "vite-plus/test";
import { AppAttestError } from "../src/appattest";
import { base64Encode } from "../src/encoding";
import {
	enrollSession,
	generate,
	generateBody,
	generateHeaders,
	harness,
	READY_INTENT,
} from "./helpers";
import type { Harness } from "./helpers";

const POST = "POST";

async function newChallenge(h: Harness) {
	const response = await h.call(POST, "/v1/session/challenge", { body: "{}" });
	return (await response.json()) as { challengeID: string; challenge: string; expiresAt: string };
}

function enrollBody(challengeID: string, keyID = "k1") {
	return JSON.stringify({
		challengeID,
		keyID,
		attestationObject: base64Encode(new Uint8Array([1])),
	});
}

describe("challenge", () => {
	it("issues a 32-byte challenge with an ISO8601 expiry without fractional seconds", async () => {
		const h = harness();
		const response = await h.call(POST, "/v1/session/challenge", { body: "{}" });
		expect(response.status).toBe(200);
		expect(response.headers.get("Cache-Control")).toBe("no-store");
		const body = (await response.json()) as { challenge: string; expiresAt: string };
		expect(atob(body.challenge)).toHaveLength(32);
		expect(body.expiresAt).toMatch(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/);
		expect(Date.parse(body.expiresAt)).toBe(h.clock.now + 300_000);
	});

	it("rejects oversized bodies and unknown routes", async () => {
		const h = harness();
		expect((await h.call(POST, "/v1/session/challenge", { body: "x".repeat(2_000) })).status).toBe(
			413,
		);
		expect(await (await h.call(POST, "/nope")).json()).toEqual({ error: "not_found" });
		expect((await h.call("GET", "/v1/generate")).status).toBe(404);
	});

	it("rate-limits the unauthenticated endpoint", async () => {
		const h = harness();
		let limited: Response | null = null;
		for (let i = 0; i < 40 && !limited; i++) {
			const r = await h.call(POST, "/v1/session/challenge", { body: "{}" });
			if (r.status === 429) limited = r;
		}
		expect(limited?.headers.get("Retry-After")).toBe("60");
		expect(await limited?.json()).toEqual({ error: "quota_exceeded" });
	});
});

describe("health", () => {
	it("reports whether the provider key is set", async () => {
		expect(await (await harness().call("GET", "/health")).json()).toEqual({
			ok: true,
			configured: true,
		});
		const h = harness({ provider: null });
		expect(await (await h.call("GET", "/health")).json()).toEqual({ ok: true, configured: false });
	});
});

describe("enroll", () => {
	it("returns a session token for a valid attestation and consumes the challenge", async () => {
		const h = harness();
		const { challengeID } = await newChallenge(h);
		const body = enrollBody(challengeID);
		const ok = await h.call(POST, "/v1/session/enroll", { body });
		expect(ok.status).toBe(200);
		expect(((await ok.json()) as { sessionToken: string }).sessionToken).toMatch(
			/^[A-Za-z0-9_-]{43}$/,
		);
		expect((await h.call(POST, "/v1/session/enroll", { body })).status).toBe(401);
	});

	it("maps validation, unknown challenge and verifier failures", async () => {
		const h = harness();
		expect((await h.call(POST, "/v1/session/enroll", { body: "{}" })).status).toBe(400);
		const badBase64 = JSON.stringify({ challengeID: "x", keyID: "k", attestationObject: "!!" });
		expect((await h.call(POST, "/v1/session/enroll", { body: badBase64 })).status).toBe(400);
		expect((await h.call(POST, "/v1/session/enroll", { body: enrollBody("missing") })).status).toBe(
			401,
		);

		h.verifier.attestationError = new AppAttestError("invalid_certificate_chain");
		const { challengeID } = await newChallenge(h);
		const rejected = await h.call(POST, "/v1/session/enroll", { body: enrollBody(challengeID) });
		expect(rejected.status).toBe(401);
		expect(await rejected.json()).toEqual({ error: "unauthorized" });
	});
});

describe("generate", () => {
	it("returns the intent, then replays it for the same key without calling the provider", async () => {
		const h = harness();
		const token = await enrollSession(h);
		const first = await generate(h, token, "key-1");
		expect(first.status).toBe(200);
		expect(await first.text()).toBe(READY_INTENT);
		const replay = await generate(h, token, "key-1");
		expect(replay.status).toBe(200);
		expect(await replay.text()).toBe(READY_INTENT);
		expect(h.provider.calls).toBe(1);
	});

	it("rejects missing or malformed credentials", async () => {
		const h = harness();
		const body = generateBody();
		expect((await h.call(POST, "/v1/generate", { body })).status).toBe(401);
		const short = { Authorization: "Bearer short" };
		expect((await h.call(POST, "/v1/generate", { body, headers: short })).status).toBe(401);
		const unknown = { Authorization: `Bearer ${"A".repeat(43)}` };
		const response = await h.call(POST, "/v1/generate", { body, headers: unknown });
		expect(response.status).toBe(401);
		expect(await response.json()).toEqual({ error: "unknown_session" });
	});

	it("validates the request body and idempotency key", async () => {
		const h = harness();
		const token = await enrollSession(h);
		const headers = { Authorization: `Bearer ${token}` };
		expect((await h.call(POST, "/v1/generate", { body: "nope", headers })).status).toBe(400);
		expect(
			(await h.call(POST, "/v1/generate", { body: generateBody("   "), headers })).status,
		).toBe(400);
		const long = await h.call(POST, "/v1/generate", {
			body: generateBody("x".repeat(601)),
			headers,
		});
		expect(await long.json()).toEqual({ error: "prompt_too_long" });
		const noKey = await h.call(POST, "/v1/generate", { body: generateBody(), headers });
		expect(await noKey.json()).toEqual({ error: "invalid_idempotency_key" });
		expect((await h.call(POST, "/v1/generate", { body: "x".repeat(70_000), headers })).status).toBe(
			413,
		);
	});

	it("requires the signed client data to match the request", async () => {
		const h = harness();
		const token = await enrollSession(h);
		const body = generateBody();
		const headers = await generateHeaders(h, token, body, "key-2");
		const tampered = await h.call(POST, "/v1/generate", {
			body: generateBody("a different prompt"),
			headers,
		});
		expect(tampered.status).toBe(401);
		const wrongKey = await h.call(POST, "/v1/generate", {
			body,
			headers: { ...headers, "Idempotency-Key": "other" },
		});
		expect(wrongKey.status).toBe(401);
		expect(h.provider.calls).toBe(0);
	});

	it("returns 401 for a failed assertion and 409 for an out-of-order counter", async () => {
		const h = harness();
		const token = await enrollSession(h);
		h.verifier.assertionError = new AppAttestError("invalid_assertion_signature");
		expect((await generate(h, token, "key-3")).status).toBe(401);
		h.verifier.assertionError = new AppAttestError("invalid_assertion_counter");
		const stale = await generate(h, token, "key-3");
		expect(stale.status).toBe(409);
		expect(await stale.json()).toEqual({ error: "assertion_counter_out_of_order" });
		h.verifier.assertionError = null;
		h.verifier.assertionCounterOverride = 0;
		expect((await generate(h, token, "key-3")).status).toBe(409);
		h.verifier.assertionCounterOverride = null;
		expect((await generate(h, token, "key-3")).status).toBe(200);
	});

	it("uses each assertion challenge only once", async () => {
		const h = harness();
		const token = await enrollSession(h);
		const body = generateBody();
		const headers = await generateHeaders(h, token, body, "key-4");
		expect((await h.call(POST, "/v1/generate", { body, headers })).status).toBe(200);
		expect((await h.call(POST, "/v1/generate", { body, headers })).status).toBe(401);
	});

	it("rejects a different request under a used key and limits to 5 per minute", async () => {
		const h = harness();
		const token = await enrollSession(h);
		expect((await generate(h, token, "same", "one")).status).toBe(200);
		const conflict = await generate(h, token, "same", "two");
		expect(conflict.status).toBe(409);
		expect(await conflict.json()).toEqual({ error: "idempotency_conflict" });
		for (let i = 1; i < 5; i++) expect((await generate(h, token, `q${i}`)).status).toBe(200);
		const limited = await generate(h, token, "q-over");
		expect(limited.status).toBe(429);
		expect(limited.headers.get("Retry-After")).toBe("60");
		expect(await limited.json()).toEqual({ error: "quota_exceeded" });
	});

	it("answers 503 and allows a retry with the same key after a provider failure", async () => {
		const h = harness();
		const token = await enrollSession(h);
		h.provider.failNext = true;
		const failed = await generate(h, token, "key-5");
		expect(failed.status).toBe(503);
		expect(await failed.json()).toEqual({ error: "service_unavailable" });
		expect((await generate(h, token, "key-5")).status).toBe(200);
		expect(h.provider.calls).toBe(2);
	});

	it("answers 409 generation_in_progress for a duplicate while one is running", async () => {
		const h = harness();
		const token = await enrollSession(h);
		let release: () => void = () => {};
		h.provider.generateIntent = () =>
			new Promise((resolve) => (release = () => resolve(READY_INTENT)));
		const running = generate(h, token, "slow");
		await new Promise((r) => setTimeout(r, 50));
		const duplicate = await generate(h, token, "slow");
		expect(duplicate.status).toBe(409);
		expect(duplicate.headers.get("Retry-After")).toBe("1");
		expect(await duplicate.json()).toEqual({ error: "generation_in_progress" });
		release();
		expect((await running).status).toBe(200);
	});

	it("rejects an intent that fails validation and answers 503", async () => {
		const h = harness();
		const token = await enrollSession(h);
		h.provider.generateIntent = async () => '{"schemaVersion":2}';
		expect((await generate(h, token, "bad")).status).toBe(503);
	});

	it("answers a clear 503 config error, without spending quota, while OPENAI_API_KEY is unset", async () => {
		const h = harness({ provider: null });
		const token = await enrollSession(h);
		const response = await generate(h, token, "key-6");
		expect(response.status).toBe(503);
		expect(await response.json()).toEqual({ error: "service_not_configured" });
		expect((await h.call(POST, "/v1/generate", { body: generateBody() })).status).toBe(401);
	});
});
