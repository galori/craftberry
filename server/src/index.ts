import { APPLE_APP_ATTESTATION_ROOT_CA_PEM } from "./appleRootCA";
import * as appattest from "./appattest";
import { OpenAIIntentProvider } from "./openai";
import { handleRequest, PROFILE_ID } from "./service";
import type { ServiceConfig } from "./service";
import { DEFAULT_QUOTA, storeStub } from "./store";

export { GenerationStore } from "./store";

const STORE_NAME = "primary";

export function serviceConfig(env: Env): ServiceConfig | null {
	const appId = env.APP_ATTEST_APP_ID?.trim();
	const environment = env.APP_ATTEST_ENVIRONMENT;
	if (!appId || (environment !== "development" && environment !== "production")) return null;
	const versions = (env.APP_ATTEST_ALLOWED_BUNDLE_VERSIONS ?? "")
		.split(",")
		.map((value) => value.trim())
		.filter(Boolean);
	return {
		appId,
		environment,
		allowedBundleVersions: versions.length > 0 ? versions : undefined,
		appleRootCA: APPLE_APP_ATTESTATION_ROOT_CA_PEM,
		profileID: PROFILE_ID,
		maxPromptCharacters: 600,
		maxRequestBytes: 65_536,
		challengeLifetimeMs: 300_000,
		quota: DEFAULT_QUOTA,
	};
}

export default {
	async fetch(request, env) {
		const config = serviceConfig(env);
		if (config === null) {
			return Response.json(
				{ error: "service_not_configured" },
				{ status: 503, headers: { "Cache-Control": "no-store" } },
			);
		}
		const apiKey = env.OPENAI_API_KEY?.trim();
		const store = storeStub(env, STORE_NAME);
		// Only a one-way digest of the client address is stored, to rate-limit challenge requests.
		const address = request.headers.get("CF-Connecting-IP") ?? "unknown";
		const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(address));
		const clientKey = Array.from(new Uint8Array(digest).slice(0, 8), (b) =>
			b.toString(16).padStart(2, "0"),
		).join("");
		return handleRequest(
			request,
			{
				store,
				verifier: appattest,
				provider: apiKey ? new OpenAIIntentProvider(apiKey) : null,
				config,
				now: () => Date.now(),
			},
			clientKey,
		);
	},
} satisfies ExportedHandler<Env>;
