export function base64Encode(data: Uint8Array): string {
	let binary = "";
	for (const byte of data) binary += String.fromCharCode(byte);
	return btoa(binary);
}

/** Strict standard base64 (padding required), like Foundation's Data(base64Encoded:). */
export function base64Decode(value: string): Uint8Array | null {
	if (value.length % 4 !== 0 || !/^[A-Za-z0-9+/]*={0,2}$/.test(value)) return null;
	try {
		return Uint8Array.from(atob(value), (c) => c.charCodeAt(0));
	} catch {
		return null;
	}
}

export function base64URL(data: Uint8Array): string {
	return base64Encode(data).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

/** 32 random bytes encoded as unpadded base64url are exactly 43 characters. */
export function isSessionToken(value: string): boolean {
	return /^[A-Za-z0-9_-]{43}$/.test(value);
}

export async function sha256(data: Uint8Array | string): Promise<Uint8Array> {
	const input = typeof data === "string" ? new TextEncoder().encode(data) : data;
	return new Uint8Array(await crypto.subtle.digest("SHA-256", input));
}

export function randomBytes(count: number): Uint8Array {
	return crypto.getRandomValues(new Uint8Array(count));
}

/** Matches Swift ISO8601DateFormatter output (no fractional seconds), which the iOS client parses. */
export function isoSeconds(ms: number): string {
	return new Date(ms).toISOString().replace(/\.\d{3}Z$/, "Z");
}
