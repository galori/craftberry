import { env } from "cloudflare:test";
import { AppAttestError } from "../src/appattest";
import { base64Encode, base64URL, sha256 } from "../src/encoding";
import type { IntentProvider } from "../src/openai";
import { canonicalClientData, handleRequest, PROFILE_ID } from "../src/service";
import type { ServiceConfig, ServiceDeps, Verifier } from "../src/service";
import { DEFAULT_QUOTA, storeStub } from "../src/store";

let counter = 0;
export function freshStore() {
	return storeStub(env, `test-${crypto.randomUUID()}-${counter++}`);
}

export const READY_INTENT = JSON.stringify({
	schemaVersion: 1,
	outcome: "ready",
	message: "Ready",
	shortDescription: "A sword pack.",
	sword: { displayName: "Harbor" },
	materialSwordSet: null,
});

export function baseConfig(): ServiceConfig {
	return {
		appId: "TEAM.com.craftberry.app",
		environment: "development",
		allowedBundleVersions: ["1"],
		appleRootCA: "pem",
		profileID: PROFILE_ID,
		maxPromptCharacters: 600,
		maxRequestBytes: 65_536,
		challengeLifetimeMs: 300_000,
		quota: DEFAULT_QUOTA,
	};
}

/** Accepts any attestation/assertion unless told otherwise; assertion counter = previous + 1. */
export class FakeVerifier implements Verifier {
	attestationError: AppAttestError | null = null;
	assertionError: AppAttestError | null = null;
	assertionCounterOverride: number | null = null;
	async verifyAttestation() {
		if (this.attestationError) throw this.attestationError;
		return { publicKeyDer: new Uint8Array([1, 2, 3]), receipt: new Uint8Array([4, 5]), counter: 0 };
	}
	async verifyAssertion(input: { previousCounter: number }) {
		if (this.assertionError) throw this.assertionError;
		return { counter: this.assertionCounterOverride ?? input.previousCounter + 1 };
	}
}

export class FakeProvider implements IntentProvider {
	calls = 0;
	failNext = false;
	async generateIntent(_prompt?: string): Promise<string> {
		this.calls++;
		if (this.failNext) {
			this.failNext = false;
			throw new Error("provider down");
		}
		return READY_INTENT;
	}
}

export interface Harness {
	deps: ServiceDeps;
	verifier: FakeVerifier;
	provider: FakeProvider;
	clock: { now: number };
	call(
		method: string,
		path: string,
		init?: { body?: string; headers?: Record<string, string> },
	): Promise<Response>;
}

export function harness(overrides: Partial<ServiceDeps> = {}): Harness {
	const verifier = new FakeVerifier();
	const provider = new FakeProvider();
	const clock = { now: 1_800_000_000_000 };
	const deps: ServiceDeps = {
		store: freshStore(),
		verifier,
		provider,
		config: baseConfig(),
		now: () => clock.now,
		...overrides,
	};
	return {
		deps,
		verifier,
		provider,
		clock,
		call: (method, path, init = {}) =>
			handleRequest(
				new Request(`https://worker.test${path}`, {
					method,
					body: init.body,
					headers: init.headers,
				}),
				deps,
				"client-a",
			),
	};
}

export async function enrollSession(h: Harness): Promise<string> {
	const challenge = (await (
		await h.call("POST", "/v1/session/challenge", { body: "{}" })
	).json()) as {
		challengeID: string;
	};
	const response = await h.call("POST", "/v1/session/enroll", {
		body: JSON.stringify({
			challengeID: challenge.challengeID,
			keyID: `key-${crypto.randomUUID()}`,
			attestationObject: base64Encode(new Uint8Array([9, 9])),
		}),
	});
	return ((await response.json()) as { sessionToken: string }).sessionToken;
}

export async function generateHeaders(h: Harness, token: string, body: string, key: string) {
	const challenge = (await (
		await h.call("POST", "/v1/session/challenge", { body: "{}" })
	).json()) as {
		challengeID: string;
		challenge: string;
	};
	const clientData = canonicalClientData({
		challenge: challenge.challenge,
		challengeID: challenge.challengeID,
		idempotencyKey: key,
		method: "POST",
		path: "/v1/generate",
		requestBodySHA256: base64URL(await sha256(new TextEncoder().encode(body))),
	});
	return {
		Authorization: `Bearer ${token}`,
		"Idempotency-Key": key,
		"App-Attest-Challenge-ID": challenge.challengeID,
		"App-Attest-Client-Data": base64Encode(new TextEncoder().encode(clientData)),
		"App-Attest-Assertion": base64Encode(new Uint8Array([7])),
	};
}

export function generateBody(prompt = "make a harbor sword") {
	return JSON.stringify({ intentVersion: 1, profileID: PROFILE_ID, prompt });
}

export async function generate(h: Harness, token: string, key: string, prompt?: string) {
	const body = generateBody(prompt);
	return h.call("POST", "/v1/generate", {
		body,
		headers: await generateHeaders(h, token, body, key),
	});
}
