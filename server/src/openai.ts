import template from "./openai-request.json";

export interface IntentProvider {
	generateIntent(prompt: string): Promise<string>;
}

const PROMPT_PLACEHOLDER = "PROMPT_PLACEHOLDER";
const REQUEST_TIMEOUT_MS = 90_000;

/**
 * The request body (model, instructions, strict JSON schema) is generated from the Swift
 * OpenAIResponsesClient so both stay identical; only the user prompt is substituted.
 */
export function buildOpenAIRequest(prompt: string) {
	const body = structuredClone(template);
	for (const message of body.input) {
		for (const part of message.content) {
			if (message.role === "user" && part.text === PROMPT_PLACEHOLDER) part.text = prompt;
		}
	}
	return body;
}

export class OpenAIIntentProvider implements IntentProvider {
	constructor(
		private readonly apiKey: string,
		private readonly fetcher: typeof fetch = fetch,
	) {}

	async generateIntent(prompt: string): Promise<string> {
		const response = await this.fetcher("https://api.openai.com/v1/responses", {
			method: "POST",
			headers: { Authorization: `Bearer ${this.apiKey}`, "Content-Type": "application/json" },
			body: JSON.stringify(buildOpenAIRequest(prompt)),
			signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
		});
		if (!response.ok) throw new Error(`provider HTTP ${response.status}`);
		const payload = (await response.json()) as {
			output?: { content?: { type: string; text?: string }[] }[];
		};
		const text = payload.output
			?.flatMap((item) => item.content ?? [])
			.find((part) => part.type === "output_text")?.text;
		if (typeof text !== "string") throw new Error("provider response has no output_text");
		return text;
	}
}
