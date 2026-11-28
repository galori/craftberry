import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vite-plus";

export default defineConfig({
	plugins: [cloudflareTest({ config: true })],
	// App Attest tests run under their own config (src/appattest/vitest.config.ts, server-appattest.yml).
	test: { exclude: ["test/appattest/**", "node_modules/**"] },
});
