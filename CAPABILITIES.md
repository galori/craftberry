# Bedrock Capability Matrix

Status as of 2026-08-02. “Automated” means deterministic local XCTest coverage. “Device” requires an exported artifact imported into the exact Minecraft release on a physical iPhone with a clean Content Log.

## Active profile

| Profile | Mojang sample source | Minimum engine | Compiler | Automated | Device |
|---|---|---:|---|---|---|
| `bedrock-stable-1.26.30` | `bedrock-samples` `1.26.30.5`, commit `921fafb05c93abeae56c2f2868cd8f942bdbcc0f` | 1.26.30 | Active | Passing locally | Pending |

The profile currently carries the format versions and the small vanilla item catalog required by the foundation slice. Catalog generation from the pinned samples, selective Blockception schema vendoring, license notices for any vendored material, and schema exception tracking are planned before Phase 2 is accepted.

## Content support

| Family | Semantic IR | Compiler/assets | Schema/sample evidence | Automated | Device | Status |
|---|---|---|---|---|---|---|
| Single melee sword | Supported | Typed item, shaped recipe, texture, localization, manifests, packs | Exact assertions derived from current working Bedrock forms; Mojang commit pinned | Yes | Pending | Foundation code complete |
| Material ingot + matching sword collection | Supported | Typed items, shaped/shapeless recipes, sprites, localization, packs | Pinned fire-charge recipe and diamond-spear item forms | Yes | Pending | Phase 2A code complete |
| Multi-item collections, tools, armor, food, wearables | Planned | Planned | Required per emitted shape | Planned | Pending | Later Phase 2 |
| Shapeless, furnace, brewing, smithing transform/trim | Shapeless supported for material ingots | Furnace/brewing/smithing planned | Fire-charge evidence for shapeless only | Yes for shapeless | Pending | Phase 2A |
| Blocks, ores, crops, material families | Planned | Planned | Required per archetype | Planned | Pending | Phase 3 |
| Entities, projectiles, spawning, loot, trades | Planned | Planned | Required per archetype | Planned | Pending | Phase 4 |
| Structures, biomes, features, world generation | Planned | Planned | Required per archetype | Planned | Pending | Phase 5 |
| Stable typed scripted mechanics | Planned | Planned templates only | Stable Script API evidence required | Planned | Pending | Phase 6 |
| User-supplied validated assets | Planned | Planned | Validation rules required | Planned | Pending | Phase 6 |
| Experimental APIs | Intentionally unsupported | None | N/A | N/A | N/A | Reconsider after stable promotion |
| Free-form generated JavaScript | Intentionally unsupported | None | N/A | N/A | N/A | Requires different trust model |
| Destructive vanilla replacements/global UI overrides | Intentionally unsupported | None | Cooperative add-on policy | N/A | N/A | Not planned |

## Foundation verification detail

| Concern | Status |
|---|---|
| Versioned project sidecar, stable project/content/pack identity | Automated |
| Profile mismatch and migration gate | Automated |
| Duplicate IDs/UUIDs, missing references/resources, dependency cycles | Automated |
| Item trait and recipe grid/count/symbol/unlock limits | Automated |
| Namespace-prefixed equipment menu group | Exact compiler assertion |
| Typed item, manifest, dependency, recipe, texture-map documents | Exact normalized JSON assertions |
| Texture dimensions and deterministic PNG | Automated |
| `.mcpack`/`.mcaddon` archive tree and deterministic bytes | Automated |
| No partial filesystem output after semantic validation failure | Automated |
| Fake-client ready, unsupported, network, validation, build, export-ready flows | Automated on iOS simulator |
| Blockception schema lint | Pending |
| Physical iPhone import, both packs active, clean Content Log | Pending |
| Survival crafting, appearance, combat, durability | Pending |

## Decision changes

| Date | Decision | Reason |
|---|---|---|
| 2026-08-02 | Pin the active profile to Mojang sample release `1.26.30.5` instead of the historical POC’s 1.21.80+ target | The implementation must target one current, explicit baseline; changing it now requires migration |
| 2026-08-02 | Keep Blockception lint pending for the foundation rather than treating it as an authority | The compiler emits only already assertion-covered foundation documents; selective vendoring begins with the next document families |
| 2026-08-02 | Keep the foundation device status pending | This development environment was not authorized or equipped to mutate Minecraft or physical-device state |
