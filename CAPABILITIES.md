# Bedrock Capability Matrix

Status as of 2026-08-05. “Automated” means deterministic local XCTest coverage. “Device” requires an exported artifact imported into the exact Minecraft release on a physical iPhone with a clean Content Log.

## Active profile

| Profile | Mojang sample source | Minimum engine | Compiler | Automated | Device |
|---|---|---:|---|---|---|
| `bedrock-stable-1.26.30` | `bedrock-samples` `1.26.30.5`, commit `921fafb05c93abeae56c2f2868cd8f942bdbcc0f` | 1.26.30 | Active | Passing locally | Pending |

The profile currently carries the format versions and the small vanilla item catalog required by the foundation slice. Catalog generation from the pinned samples, selective Blockception schema vendoring, license notices for any vendored material, and schema exception tracking are planned before Phase 2 is accepted.

## Content support

| Family | Semantic IR | Compiler/assets | Schema/sample evidence | Automated | Device | Status |
|---|---|---|---|---|---|---|
| Single melee sword | Supported | Typed item, shaped recipe, texture, localization, manifests, packs | Exact assertions derived from current working Bedrock forms; Mojang commit pinned | Yes | Partial: physical iPhone import, activation, Creative crafting, localized-name OCR, and in-hand selection passed for Emerald Test Sword | Foundation code complete; clean Content Log and Survival checks pending |
| Material ingot + matching sword collection | Supported | Typed items, shaped/shapeless recipes, sprites, localization, packs | Pinned fire-charge recipe and diamond-spear item forms | Yes | Pending | Phase 2A code complete |
| Material ingot + matching tool collection | Supported | Typed sword, pickaxe, axe, shovel, hoe items; shaped/shapeless recipes; sprites; localization; packs | Reuses the pinned item and crafting-table recipe forms from earlier item slices | Yes | Pending | Phase 2B code complete |
| Armor, food, wearables, broader item traits | Planned | Planned | Required per emitted shape | Planned | Pending | Later Phase 2 |
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
| Material tool set generation through OpenAI structured intent | Automated |
| Blockception schema lint | Pending |
| Physical iPhone import and both packs active | Verified for a generated Emerald Test Sword on iPhone 16e / Minecraft 26.33; the complete Craftberry export-to-Minecraft test passed on 2026-08-05. |
| Creative crafting, localized name, and in-hand selection | Verified for Emerald Test Sword by the same physical-device test. |
| Clean Content Log; Survival crafting, appearance, combat, durability | Pending |

## Decision changes

| Date | Decision | Reason |
|---|---|---|
| 2026-08-02 | Pin the active profile to Mojang sample release `1.26.30.5` instead of the historical POC’s 1.21.80+ target | The implementation must target one current, explicit baseline; changing it now requires migration |
| 2026-08-02 | Keep Blockception lint pending for the foundation rather than treating it as an authority | The compiler emits only already assertion-covered foundation documents; selective vendoring begins with the next document families |
| 2026-08-02 | Keep the foundation device status pending | This development environment was not authorized or equipped to mutate Minecraft or physical-device state |
| 2026-08-02 | Calibrate standalone Minecraft validation tooling on the physical iPhone while retaining the foundation's overall Device status as pending | `minecraft-import.sh` reliably imports a fresh fixture through Safari. `minecraft-mirror-drive.sh` activates it in My World with keyboard focus navigation because Minecraft Ore UI ignores mirrored pointer clicks; OCR matched the fixture pack ID in the load-time Content Log and the custom sword rendered in hand/hotbar. Clean Content Log, inventory-name lookup, survival crafting, combat, and durability remain pending. |
| 2026-08-04 | Add material tool sets as the next item-family slice before armor/food/blocks | They reuse the already assertion-covered item and crafting-table recipe document families while expanding from one generated item to a coherent multi-item collection. |
| 2026-08-05 | Record partial physical acceptance for the single-sword foundation | The generated Emerald Test Sword imported through Craftberry's own share path, activated both packs, crafted successfully in Creative, showed its localized name by OCR, and was selected in-hand on the dedicated iPhone. This does not replace the outstanding clean-Content-Log or Survival checks. |
