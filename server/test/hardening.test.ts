import { describe, expect, it } from "vite-plus/test";
import { AppAttestError } from "../src/appattest";
import { base64Encode } from "../src/encoding";
import { serviceConfig } from "../src/index";
import { handleRequest } from "../src/service";
import { ENROLL_RATE_LIMIT_PER_MINUTE } from "../src/store";
import { harness } from "./helpers";

const POST = "POST";

function enrollBody(challengeID: string, keyID = "k1") {
	return JSON.stringify({
		challengeID,
		keyID,
		attestationObject: base64Encode(new Uint8Array([1])),
	});
}

async function newChallenge(h: ReturnType<typeof harness>) {
	const response = await h.call(POST, "/v1/session/challenge", { body: "{}" });
	return ((await response.json()) as { challengeID: string }).challengeID;
}

describe("serviceConfig", () => {
	const base = {
		APP_ATTEST_APP_ID: "TEAM.com.craftberry.app",
		APP_ATTEST_ENVIRONMENT: "development",
	};

	it("fails closed when the bundle-version allowlist is empty or missing", () => {
		for (const versions of [undefined, "", " , "]) {
			const env = { ...base, APP_ATTEST_ALLOWED_BUNDLE_VERSIONS: versions } as unknown as Env;
			expect(serviceConfig(env)).toBeNull();
		}
	});

	it("passes the allowlist through when set", () => {
		const env = { ...base, APP_ATTEST_ALLOWED_BUNDLE_VERSIONS: "1, 2" } as unknown as Env;
		expect(serviceConfig(env)?.allowedBundleVersions).toEqual(["1", "2"]);
	});
});

describe("enroll hardening", () => {
	it("burns the challenge when attestation fails", async () => {
		const h = harness();
		const challengeID = await newChallenge(h);
		h.verifier.attestationError = new AppAttestError("invalid_certificate_chain");
		expect(
			(await h.call(POST, "/v1/session/enroll", { body: enrollBody(challengeID) })).status,
		).toBe(401);
		// The same challenge must not allow a second try, even with a valid attestation.
		h.verifier.attestationError = null;
		expect(
			(await h.call(POST, "/v1/session/enroll", { body: enrollBody(challengeID) })).status,
		).toBe(401);
		expect(await h.deps.store.getChallenge(challengeID, h.clock.now)).toBeNull();
	});

	it("rate-limits enroll per client and recovers after a minute", async () => {
		const h = harness();
		for (let i = 0; i < ENROLL_RATE_LIMIT_PER_MINUTE; i++) {
			expect((await h.call(POST, "/v1/session/enroll", { body: "{}" })).status).toBe(400);
		}
		const limited = await h.call(POST, "/v1/session/enroll", { body: "{}" });
		expect(limited.status).toBe(429);
		expect(limited.headers.get("Retry-After")).toBe("60");
		h.clock.now += 61_000;
		expect((await h.call(POST, "/v1/session/enroll", { body: "{}" })).status).toBe(400);
	});
});

describe("body limit", () => {
	function chunked(
		chunks: number,
		size: number,
	): { body: ReadableStream<Uint8Array>; pulled: () => number } {
		let pulled = 0;
		const body = new ReadableStream<Uint8Array>({
			pull(controller) {
				if (pulled >= chunks) return controller.close();
				pulled++;
				controller.enqueue(new Uint8Array(size).fill(0x20));
			},
		});
		return { body, pulled: () => pulled };
	}

	it("rejects a chunked body without Content-Length and stops reading early", async () => {
		const h = harness();
		const { body, pulled } = chunked(1_000, 1_024); // 1 MiB if fully read
		const request = new Request("https://worker.test/v1/session/enroll", {
			method: POST,
			body,
			duplex: "half",
		} as RequestInit);
		expect(request.headers.get("Content-Length")).toBeNull();
		const response = await handleRequest(request, h.deps, "client-a");
		expect(response.status).toBe(413);
		expect(pulled()).toBeLessThan(200);
	});

	it("accepts a chunked body within the limit", async () => {
		const h = harness();
		const { body } = chunked(4, 1_024);
		const request = new Request("https://worker.test/v1/session/enroll", {
			method: POST,
			body,
			duplex: "half",
		} as RequestInit);
		// Whitespace is not a JSON object, so it passes the size check and fails validation.
		expect((await handleRequest(request, h.deps, "client-a")).status).toBe(400);
	});
});
