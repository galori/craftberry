import { describe, expect, it } from "vite-plus/test";
import { validateIntentDocument } from "../src/intent";
import { buildOpenAIRequest } from "../src/openai";
import { READY_INTENT } from "./helpers";

describe("intent validation", () => {
	it("accepts ready and unsupported documents", () => {
		expect(() => validateIntentDocument(READY_INTENT)).not.toThrow();
		const unsupported =
			'{"schemaVersion":1,"outcome":"unsupported","message":"No","shortDescription":null,"sword":null}';
		expect(() => validateIntentDocument(unsupported)).not.toThrow();
	});

	it("rejects malformed documents", () => {
		const bad = [
			"x",
			"[]",
			'{"schemaVersion":1,"outcome":"ready","message":"m","shortDescription":"d"}',
			'{"schemaVersion":1,"outcome":"unsupported","message":"m","sword":{}}',
		];
		for (const text of bad) expect(() => validateIntentDocument(text)).toThrow();
	});
});

describe("provider request", () => {
	it("substitutes only the user prompt and keeps the strict schema", () => {
		const body = buildOpenAIRequest("a ruby sword");
		const user = body.input.find((m) => m.role === "user");
		expect(user?.content[0].text).toBe("a ruby sword");
		expect(body.text.format.strict).toBe(true);
		expect(JSON.stringify(body)).not.toContain("PROMPT_PLACEHOLDER");
	});
});
