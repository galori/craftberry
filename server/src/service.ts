import { AppAttestError } from "./appattest";
import type { VerifyAssertionInput, VerifyAttestationInput } from "./appattest";
import {
	base64Decode,
	base64Encode,
	base64URL,
	isoSeconds,
	isSessionToken,
	randomBytes,
	sha256,
} from "./encoding";
import { validateIntentDocument } from "./intent";
import type { IntentProvider } from "./openai";
import type { AppAttestEnvironment, GenerationStore, QuotaPolicy } from "./store";
import { QUOTA_RETRY_AFTER } from "./store";

export const PROFILE_ID = "bedrock-stable-1.26.30";

export interface Verifier {
	verifyAttestation(
		input: VerifyAttestationInput,
	): Promise<{ publicKeyDer: Uint8Array; receipt: Uint8Array; counter: number }>;
	verifyAssertion(input: VerifyAssertionInput): Promise<{ counter: number }>;
}

export interface ServiceConfig {
	appId: string;
	environment: AppAttestEnvironment;
	allowedBundleVersions?: string[];
	appleRootCA: string;
	profileID: string;
	maxPromptCharacters: number;
	maxRequestBytes: number;
	challengeLifetimeMs: number;
	quota: QuotaPolicy;
}

export interface ServiceDeps {
	store: DurableObjectStub<GenerationStore>;
	verifier: Verifier;
	/** null when OPENAI_API_KEY is not set; generation then answers 503 service_not_configured. */
	provider: IntentProvider | null;
	config: ServiceConfig;
	now: () => number;
}

const JSON_HEADERS = {
	"Content-Type": "application/json; charset=utf-8",
	"Cache-Control": "no-store",
};

function json(status: number, payload: unknown, headers: Record<string, string> = {}): Response {
	return new Response(JSON.stringify(payload), {
		status,
		headers: { ...JSON_HEADERS, ...headers },
	});
}

function fail(status: number, error: string, headers: Record<string, string> = {}): Response {
	return json(status, { error }, headers);
}

const UNAVAILABLE = () => fail(503, "service_unavailable");

async function readBody(request: Request, limit: number): Promise<Uint8Array | null> {
	const declared = Number(request.headers.get("Content-Length") ?? "0");
	if (declared > limit) return null;
	const body = new Uint8Array(await request.arrayBuffer());
	return body.length > limit ? null : body;
}

function parseJSONObject(body: Uint8Array): Record<string, unknown> | null {
	try {
		const value: unknown = JSON.parse(
			new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(body),
		);
		return typeof value === "object" && value !== null && !Array.isArray(value)
			? (value as Record<string, unknown>)
			: null;
	} catch {
		return null;
	}
}

function graphemeCount(value: string): number {
	if (value.length <= 600) return value.length; // UTF-16 length never undercounts graphemes
	return [...new Intl.Segmenter().segment(value)].length;
}

function bearerToken(header: string | null): string | null {
	if (!header || header.length <= 7 || header.slice(0, 7).toLowerCase() !== "bearer ") return null;
	const token = header.slice(7).trim();
	return isSessionToken(token) ? token : null;
}

function isValidIdempotencyKey(value: string): boolean {
	if (value.length === 0 || value.length > 128) return false;
	for (let i = 0; i < value.length; i++) {
		const code = value.charCodeAt(i);
		if (code < 33 || code > 126) return false;
	}
	return true;
}

/** Same bytes Swift's sorted-keys JSONEncoder produces for GenerationAssertionClientData. */
export function canonicalClientData(data: {
	challenge: string;
	challengeID: string;
	idempotencyKey: string;
	method: string;
	path: string;
	requestBodySHA256: string;
}): string {
	return JSON.stringify({
		challenge: data.challenge,
		challengeID: data.challengeID,
		idempotencyKey: data.idempotencyKey,
		method: data.method,
		path: data.path,
		requestBodySHA256: data.requestBodySHA256,
	});
}

export function canonicalFingerprintInput(prompt: string): string {
	return JSON.stringify({ intentVersion: 1, profileID: PROFILE_ID, prompt });
}

function isString(value: unknown): value is string {
	return typeof value === "string";
}

export async function handleRequest(
	request: Request,
	deps: ServiceDeps,
	clientKey: string,
): Promise<Response> {
	const path = new URL(request.url).pathname;
	if (request.method === "GET" && path === "/health") {
		return json(200, { ok: true, configured: deps.provider !== null });
	}
	if (request.method !== "POST") return fail(404, "not_found");
	try {
		switch (path) {
			case "/v1/session/challenge":
				return await issueChallenge(request, deps, clientKey);
			case "/v1/session/enroll":
				return await enroll(request, deps);
			case "/v1/generate":
				return await generate(request, deps);
			default:
				return fail(404, "not_found");
		}
	} catch {
		// Storage, provider and verifier faults all surface as one opaque 503.
		return UNAVAILABLE();
	}
}

async function issueChallenge(
	request: Request,
	deps: ServiceDeps,
	clientKey: string,
): Promise<Response> {
	if ((await readBody(request, 1_024)) === null) return fail(413, "request_too_large");
	const now = deps.now();
	const id = crypto.randomUUID();
	const challenge = randomBytes(32);
	const expiresAt = now + deps.config.challengeLifetimeMs;
	const result = await deps.store.createChallenge({ id, challenge, expiresAt, now, clientKey });
	if (result === "rate_limited") return fail(429, "quota_exceeded", { "Retry-After": "60" });
	if (result === "full") return UNAVAILABLE();
	return json(200, {
		challengeID: id,
		challenge: base64Encode(challenge),
		expiresAt: isoSeconds(expiresAt),
	});
}

async function enroll(request: Request, deps: ServiceDeps): Promise<Response> {
	const { config } = deps;
	const raw = await readBody(request, config.maxRequestBytes);
	if (raw === null) return fail(413, "request_too_large");
	const body = parseJSONObject(raw);
	const attestationObject =
		body && isString(body.attestationObject) ? base64Decode(body.attestationObject) : null;
	if (
		!body ||
		!isString(body.challengeID) ||
		!isString(body.keyID) ||
		body.keyID.length === 0 ||
		attestationObject === null
	) {
		return fail(400, "invalid_request");
	}
	const { challengeID, keyID } = body as { challengeID: string; keyID: string };

	const stored = await deps.store.getChallenge(challengeID, deps.now());
	if (!stored) return fail(401, "unauthorized");
	let verified: { publicKeyDer: Uint8Array; receipt: Uint8Array; counter: number };
	try {
		verified = await deps.verifier.verifyAttestation({
			keyId: keyID,
			attestationObject,
			challenge: stored.challenge,
			appId: config.appId,
			environment: config.environment,
			allowedBundleVersions: config.allowedBundleVersions,
			appleRootCA: config.appleRootCA,
		});
	} catch (error) {
		if (error instanceof AppAttestError) return fail(401, "unauthorized");
		throw error;
	}
	if (verified.publicKeyDer.length === 0 || verified.receipt.length === 0)
		return fail(401, "unauthorized");

	const sessionToken = base64URL(randomBytes(32));
	const registered = await deps.store.registerInstallation({
		challengeID,
		installationID: crypto.randomUUID(),
		keyID,
		publicKeyDer: verified.publicKeyDer,
		receipt: verified.receipt,
		appId: config.appId,
		environment: config.environment,
		counter: verified.counter,
		tokenDigest: await sha256(sessionToken),
		now: deps.now(),
	});
	if (!registered) return fail(401, "unauthorized");
	return json(200, { sessionToken });
}

async function generate(request: Request, deps: ServiceDeps): Promise<Response> {
	const { config, store } = deps;
	const raw = await readBody(request, config.maxRequestBytes);
	if (raw === null) return fail(413, "request_too_large");
	const bearer = bearerToken(request.headers.get("Authorization"));
	if (bearer === null) return fail(401, "unauthorized");

	const body = parseJSONObject(raw);
	if (
		!body ||
		body.intentVersion !== 1 ||
		body.profileID !== config.profileID ||
		!isString(body.prompt) ||
		body.prompt.trim().length === 0
	) {
		return fail(400, "invalid_request");
	}
	const prompt = body.prompt;
	if (graphemeCount(prompt) > config.maxPromptCharacters) return fail(400, "prompt_too_long");

	const installationID = await store.installationForToken(await sha256(bearer));
	if (installationID === null) return fail(401, "unknown_session");

	const idempotencyKey = request.headers.get("Idempotency-Key");
	if (idempotencyKey === null || !isValidIdempotencyKey(idempotencyKey)) {
		return fail(400, "invalid_idempotency_key");
	}

	const challengeID = request.headers.get("App-Attest-Challenge-ID");
	const clientDataHeader = request.headers.get("App-Attest-Client-Data");
	const assertionHeader = request.headers.get("App-Attest-Assertion");
	const clientData = clientDataHeader === null ? null : base64Decode(clientDataHeader);
	const assertion = assertionHeader === null ? null : base64Decode(assertionHeader);
	if (challengeID === null || clientData === null || assertion === null)
		return fail(401, "unauthorized");
	const parsedClientData = parseJSONObject(clientData);
	if (
		!parsedClientData ||
		!isString(parsedClientData.challengeID) ||
		!isString(parsedClientData.challenge) ||
		!isString(parsedClientData.idempotencyKey) ||
		!isString(parsedClientData.method) ||
		!isString(parsedClientData.path) ||
		!isString(parsedClientData.requestBodySHA256)
	) {
		return fail(401, "unauthorized");
	}
	const signed = parsedClientData as {
		challengeID: string;
		challenge: string;
		idempotencyKey: string;
		method: string;
		path: string;
		requestBodySHA256: string;
	};
	if (
		signed.challengeID !== challengeID ||
		canonicalClientData(signed) !== new TextDecoder().decode(clientData) ||
		signed.method !== "POST" ||
		signed.path !== "/v1/generate" ||
		signed.idempotencyKey !== idempotencyKey ||
		signed.requestBodySHA256 !== base64URL(await sha256(raw))
	) {
		return fail(401, "unauthorized");
	}

	const challenge = await store.getChallenge(challengeID, deps.now());
	const signedChallenge = base64Decode(signed.challenge);
	const credential = await store.credential(installationID);
	if (
		!challenge ||
		!signedChallenge ||
		base64Encode(challenge.challenge) !== base64Encode(signedChallenge) ||
		!credential ||
		credential.appId !== config.appId ||
		credential.environment !== config.environment
	) {
		return fail(401, "unauthorized");
	}

	let verifiedCounter: number;
	try {
		({ counter: verifiedCounter } = await deps.verifier.verifyAssertion({
			assertion,
			clientDataHash: await sha256(clientData),
			publicKeyDer: credential.publicKeyDer,
			appId: config.appId,
			previousCounter: credential.counter,
		}));
	} catch (error) {
		if (error instanceof AppAttestError) {
			return error.code === "invalid_assertion_counter"
				? fail(409, "assertion_counter_out_of_order")
				: fail(401, "unauthorized");
		}
		throw error;
	}
	if (verifiedCounter <= credential.counter) return fail(409, "assertion_counter_out_of_order");
	const consumed = await store.consumeAssertion({
		challengeID,
		installationID,
		expectedCounter: credential.counter,
		newCounter: verifiedCounter,
		now: deps.now(),
	});
	if (!consumed) return fail(409, "assertion_counter_out_of_order");

	// Checked after authentication so unauthenticated callers cannot probe configuration,
	// and before reserving so a missing secret never spends quota.
	if (deps.provider === null) return fail(503, "service_not_configured");

	const fingerprint = base64Encode(await sha256(canonicalFingerprintInput(prompt)));
	const reservation = await store.reserveGeneration({
		installationID,
		idempotencyKey,
		fingerprint,
		now: deps.now(),
		quota: config.quota,
	});
	switch (reservation.kind) {
		case "replay":
			return new Response(reservation.response, { status: 200, headers: JSON_HEADERS });
		case "inProgress":
			return fail(409, "generation_in_progress", { "Retry-After": "1" });
		case "idempotencyConflict":
			return fail(409, "idempotency_conflict");
		case "limited":
			return fail(429, "quota_exceeded", {
				"Retry-After": String(QUOTA_RETRY_AFTER[reservation.window]),
			});
		case "reserved":
			break;
	}

	const { reservationID } = reservation;
	try {
		const intent = await deps.provider.generateIntent(prompt);
		validateIntentDocument(intent);
		let completed = false;
		for (let attempt = 1; attempt <= 3; attempt++) {
			try {
				completed = await store.completeGeneration({
					installationID,
					idempotencyKey,
					reservationID,
					response: intent,
					now: deps.now(),
				});
				break;
			} catch (error) {
				if (attempt === 3) throw error;
			}
		}
		if (!completed) return fail(409, "generation_in_progress", { "Retry-After": "1" });
		return new Response(intent, { status: 200, headers: JSON_HEADERS });
	} catch {
		try {
			const marked = await store.markGenerationRetryable({
				installationID,
				idempotencyKey,
				reservationID,
				now: deps.now(),
			});
			if (!marked) return fail(409, "generation_in_progress", { "Retry-After": "1" });
		} catch {
			return UNAVAILABLE();
		}
		return UNAVAILABLE();
	}
}
