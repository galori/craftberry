// TEMPORARY STUB. Replace by deleting this file once feat/worker-appattest merges:
// './appattest' then resolves to src/appattest/index.ts with the same interface.
// The stub fails closed: every call rejects, so nothing can enroll or generate.

export type AppAttestErrorCode = string;

export class AppAttestError extends Error {
	readonly code: AppAttestErrorCode;
	constructor(code: AppAttestErrorCode, message?: string) {
		super(message ?? code);
		this.name = "AppAttestError";
		this.code = code;
	}
}

export interface VerifyAttestationInput {
	keyId: string;
	attestationObject: Uint8Array;
	challenge: Uint8Array;
	appId: string;
	environment: "development" | "production";
	allowedBundleVersions?: string[];
	appleRootCA: string;
}

export interface VerifyAssertionInput {
	assertion: Uint8Array;
	clientDataHash: Uint8Array;
	publicKeyDer: Uint8Array;
	appId: string;
	previousCounter: number;
}

export async function verifyAttestation(
	_input: VerifyAttestationInput,
): Promise<{ publicKeyDer: Uint8Array; receipt: Uint8Array; counter: number }> {
	throw new AppAttestError("unsupported_format", "App Attest verifier is not installed");
}

export async function verifyAssertion(_input: VerifyAssertionInput): Promise<{ counter: number }> {
	throw new AppAttestError("unsupported_format", "App Attest verifier is not installed");
}
