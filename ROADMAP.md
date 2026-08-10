# Craftberry Bedrock Add-On Generator Roadmap

## Product direction

Craftberry evolves through device-verified vertical slices. Each release generates a useful, bounded whole add-on—an equipment set, ore family, crop, mob, or structure—while requests beyond the active capability profile return a clear unsupported result.

```text
Prompt
→ typed semantic AddOnProject
→ local validation and asset generation
→ version-pinned Bedrock compiler
→ compilation report
→ .mcaddon export
```

The LLM never emits Bedrock JSON, JavaScript, filenames, UUIDs, or archives. Structured Outputs provide syntactic conformance for a narrow intent response; Swift independently assembles and validates the semantic project.

The active profile is `bedrock-stable-1.26.30`, pinned to Mojang `bedrock-samples` release `1.26.30.5` at commit `921fafb05c93abeae56c2f2868cd8f942bdbcc0f`. Mojang samples, exact compiler assertions, the Minecraft Content Log, and physical-device tests are authoritative. The Mojang sample repository remains under its own `LICENSE.md` terms; this repository does not vendor its assets.

Blockception schemas will be pinned and vendored selectively as advisory development/CI linting when the compiler adds the next Bedrock document families. They are not a runtime dependency or source of truth, and every exception must cite an official sample or documentation.

## Architecture

`AddOnProject` is the versioned semantic sidecar and the sole compiler input. It owns a stable project ID, namespace, display name, four pack UUIDs, build version, target profile, original prompt, and a graph of typed content nodes. References distinguish vanilla identifiers/tags from generated content IDs. Traits model intent such as combat and durability rather than raw Bedrock dictionaries.

`BedrockContentProfile` owns the format versions, minimum engine version, supported traits, manifest rules, known constraints, and generated vanilla catalog for one stable Minecraft baseline. Changing the active profile requires an explicit compatibility migration.

`BedrockAddOnCompiler` is a deep module with one public operation:

```swift
compile(project:profile:outputDirectory:) -> BedrockCompilationResult
```

It validates the complete graph before filesystem writes, emits typed `Encodable` Bedrock documents, generates deterministic resource and behavior packs, and returns an artifact plus a structured report. A stable `project.json` is stored at `<project-id>/project.json`; versioned artifacts live below `<project-id>/builds/<version>/`.

`LLMClient.generateProject` is the only external generation operation. The current adapter asks for a compact sword intent, assigns all identity locally, validates it, and permits one structured repair attempt. Later phases may split project outline and content-family requests internally without widening this public boundary.

## Simplification decision record

| Area | Chosen approach | Deferred alternative | Reconsider when |
|---|---|---|---|
| Capability scope | Common, useful stable Bedrock add-ons | Exhaustive or experimental coverage | A requested experimental feature becomes stable and device-verifiable |
| Delivery | Incremental vertical slices | One-shot universal compiler rewrite | Never by default; each family must ship as a verified slice |
| Project size | Bounded archetypes and compositions | Unrestricted overhaul prompts | Several families compose reliably and output size is the primary limit |
| UX | Prompt → generate/build → export | Editor, preview studio, conversation | Modification becomes the active milestone |
| Preview | Minecraft is authoritative | Full in-app Bedrock renderer | Summaries and thumbnails no longer provide useful pre-export inspection |
| Persistence | Versioned sidecar with stable IDs | SwiftData, cloud sync, project history | Gallery, history, sync, or collaboration is added |
| Assets | Procedural/template assets first | Uploads and generative media | Repetition limits usefulness; validate uploads before generated media |
| Scripting | Stable Script API templates later | Early or model-written JavaScript | Common mechanics cannot be expressed declaratively |
| Script safety | Typed event/condition/action DSL | Free-form generated scripts | Only after sandboxing and a separate security review |
| Bedrock versions | One pinned stable profile | Multiple selectable profiles | Users or saved projects require older compatibility |
| Vanilla inputs | Generated versioned catalog | Hand-maintained enum cases | Only if Mojang publishes a stronger registry |
| Schema validation | Advisory pinned Blockception CI lint | Runtime or sole validator | Coverage/versioning match the pinned profile; device tests still remain |
| API credentials | Ignored Debug-only key | Backend gateway | Mandatory before TestFlight, sharing, or distribution |
| Product systems | Deferred during capabilities | Auth, quotas, telemetry, cloud storage | Begin before any distributable build |
| Java comparison | Bedrock capabilities only | Java mod parity | Not planned |

## Incremental delivery

1. **Foundation and sword parity.** Introduce the semantic project, stable identity, typed references/documents, profile resources, compilation reports and sidecars; port the sword; add fake-client state tests. Code is implemented. Physical-device import, activation, Creative crafting, localized-name OCR, and in-hand selection passed for the generated Emerald Test Sword; clean Content Log and Survival checks remain pending.
2. **Material sword set (Phase 2A).** A named ingot plus matching sword, typed shapeless and shaped recipes, two original sprites, a pinned ten-input vanilla catalog, and schema-v2 sidecars are implemented. Device acceptance remains pending; see `PHASE2_MATERIAL_SWORD_SET.md`.
3. **General items and stable recipes.** Material tool sets are implemented for sword, pickaxe, axe, shovel, and hoe variants generated from one named ingot. Material melee weapon sets are implemented for sword, dagger, spear, and hammer variants generated from one named ingot. Material armor sets are implemented for helmet, chestplate, leggings, and boots variants generated from one named ingot, including `minecraft:wearable` and body-rendering attachables. Material furnace sets are implemented for a furnace-smelted ingot plus matching sword via `minecraft:recipe_furnace` (`tags: ["furnace"]`, string `input`/`output`, `unlock`). Material brewing sets are implemented for a brewing-stand elixir collection (ingot + elixir) via `minecraft:recipe_brewing_mix` and `minecraft:recipe_brewing_container` (`tags: ["brewing_stand"]`, string `input`/`reagent`/`output`). Continue with wearables beyond armor, repair/enchantment traits, throwable/projectile items, records, placers, and remaining stable recipe forms (smithing).
3. **Materials, blocks, crops, and ores.** Storage blocks (`minecraft:block` + `terrain_texture.json`/`blocks.json`, self-drop loot), ore blocks (ingot-dropping `minecraft:block` + `loot_tables/blocks/*.json` → ingot, `terrain_texture.json`/`blocks.json`), and crop blocks (seed + crop `minecraft:block` with `craftberry:growth` 0..7 `states`/`permutations` + produce loot, `terrain_texture.json`/`blocks.json`) are implemented; feature placement (`features/` + `feature_rules/`) remains pending.
4. **Entities and gameplay content.** Add passive, hostile, tameable, rideable, projectile, and boss-like templates with behavior/resource wiring, spawning, loot, particles, sounds, then dialogue and trades.
5. **Structures, biomes, and world generation.** Bounded 3×3 hut `.mcstructure` + `structure_template_feature`/`feature_rules` is implemented (reusing block definitions, deterministic NBT, pinned to `1.26.30.5 @921fafb`); jigsaw sets, biomes, and cooperative composition remain pending.
6. **Stable scripted mechanics and richer assets.** Compile a typed mechanic DSL into reviewed stable Script API templates; add validated uploads before optional generated media.
7. **Revision workflow.** Load the semantic sidecar, apply a new prompt, summarize changes, preserve IDs, increment versions, and rebuild. Add history only if sidecars prove insufficient.
8. **Pre-publication hardening.** Add an authenticated backend, quotas, abuse controls, privacy disclosures, telemetry, retention, and profile migrations before any distribution.

## Acceptance policy

Each compiler family needs semantic validation tests, exact normalized Bedrock JSON assertions, archive-tree fixtures, advisory schema linting, a generic iOS build, deterministic fake-client flows, and a physical-iPhone import on the exact profile release with both packs active and a clean Content Log. Relevant Survival checks—crafting, appearance, equipment, combat, durability, drops, spawning, world generation, and pack updates—are required before marking that family device-verified.
