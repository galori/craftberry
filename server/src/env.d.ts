// Not declared in cloudflare.config.ts, so a deploy never writes it; set with `cf workers secrets update`.
interface Env {
	OPENAI_API_KEY?: string;
}
