/**
 * Structural check of the model's intent document before it is stored and returned.
 * shortcut: the Swift service also ran the full AddOnProjectValidator/compiler pipeline here;
 * this port checks the schema envelope only. The iOS client still validates and assembles the
 * intent locally, so a document that passes here but fails there surfaces as invalidResponse.
 */
const INTENT_KEYS = [
	"sword",
	"materialSwordSet",
	"materialToolSet",
	"materialWeaponSet",
	"materialArmorSet",
	"materialConsumableSet",
	"materialBlockSet",
	"materialFurnaceSet",
	"materialSmithingSet",
	"materialBrewingSet",
	"materialOreSet",
	"materialCropSet",
	"materialStructureSet",
	"materialHostileEntitySet",
	"materialBossEntitySet",
	"musicRecordSet",
] as const;

export function validateIntentDocument(text: string): void {
	let doc: unknown;
	try {
		doc = JSON.parse(text);
	} catch {
		throw new Error("intent is not JSON");
	}
	if (typeof doc !== "object" || doc === null || Array.isArray(doc))
		throw new Error("intent is not an object");
	const record = doc as Record<string, unknown>;
	if (record.schemaVersion !== 1) throw new Error("unsupported schemaVersion");
	if (typeof record.message !== "string" || record.message.length === 0)
		throw new Error("missing message");
	const populated = INTENT_KEYS.filter((key) => record[key] !== null && record[key] !== undefined);
	if (record.outcome === "unsupported") {
		if (populated.length !== 0) throw new Error("unsupported intent carries a payload");
		return;
	}
	if (record.outcome !== "ready") throw new Error("unknown outcome");
	if (populated.length !== 1 || populated[0] === "musicRecordSet")
		throw new Error("ready intent needs one payload");
	if (typeof record.shortDescription !== "string" || record.shortDescription.length === 0) {
		throw new Error("ready intent needs shortDescription");
	}
}
