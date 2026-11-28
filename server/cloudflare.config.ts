import { bindings, defineConfig, exports } from "cf/config";
import * as entrypoint from "./src/index.ts" with { type: "cf-worker" };

// Two modes, each a separate Worker with its own Durable Object namespace, App Attest
// environment and secrets. `cf build --mode staging|production`; no mode means staging.
const APP_ID = "N3G3T6D9G9.com.craftberry.app";

export default defineConfig(({ mode }) => {
	const production = mode === "production";
	const name = production ? "craftberry-generation-production" : "craftberry-generation-staging";
	return {
		worker: {
			name,
			compatibilityDate: "2026-11-23",
			entrypoint,
			exports: {
				GenerationStore: exports.durableObject({ storage: "sqlite" }),
			},
			env: {
				STORE: bindings.durableObject({ worker: name, exportName: "GenerationStore" }),
				APP_ATTEST_APP_ID: bindings.text(APP_ID),
				APP_ATTEST_ENVIRONMENT: bindings.text(production ? "production" : "development"),
				APP_ATTEST_ALLOWED_BUNDLE_VERSIONS: bindings.text("1"),
				OPENAI_API_KEY: bindings.secret(),
			},
		},
	};
});
