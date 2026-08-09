# Bedrock Capability Matrix

Status as of 2026-08-09. “Automated” means deterministic local XCTest coverage. “Device” requires an exported artifact imported into the exact Minecraft release on a physical iPhone with a clean Content Log.

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
| Material ingot + matching melee weapon collection | Supported | Typed sword, dagger, spear, hammer items; shaped/shapeless recipes; sprites; localization; packs | Reuses the pinned item and crafting-table recipe forms from earlier item slices | Yes | Pending | Phase 3 code complete |
| Material ingot + matching armor collection (helmet, chestplate, leggings, boots) | Supported | Typed `minecraft:wearable` items, shaped recipes, per-piece inventory sprites, `attachables/*.json`, two shared 64x32 armor-layer body textures, localization, packs | Exact assertions pinned to `resource_pack/attachables/diamond_{helmet,chestplate,leggings,boots}.json` (format_version `1.8.0`, built-in vanilla material/geometry/render-controller identifiers) and `metadata/json_schemas/server/item_components/1.21.90/Wearable.json` | Yes | Pending | Phase 4 code complete |
| Material ingot + matching consumable collection (food, fuel) | Supported | Typed `minecraft:food`/`minecraft:fuel` items, shaped/shapeless recipes, 32×32 food/fuel sprites, localization, packs | Exact assertions pinned to `behavior_pack/items/apple.json` / `beetroot_soup.json` `minecraft:food` and `charcoal`-style `minecraft:fuel` forms | Yes | Pending | Phase 4b code complete |
| Material ingot + storage block collection (ingot + block) | Supported | Typed `minecraft:block` (`destroy_time`/`map_color`/`loot` + `light_dampening`), `loot_tables/blocks/*.json`, `terrain_texture.json` + `blocks.json`, 32×32 block-item + 16×16 terrain tile, shaped/shapeless recipes (9↔1), localization, packs | Exact assertions pinned to `behavior_pack/blocks/diamond_block.json` / `iron_block.json` `minecraft:block` and `resource_pack/terrain_texture.json` / `resource_pack/blocks.json` at `921fafb0` | Yes | Pending | Phase 4c code complete |
| Food, fuel, other wearables, broader item traits | Supported for food/fuel via consumable set; remaining wearables/traits planned | Planned for remaining | Required per emitted shape | Planned | Pending | Later Phase 4 |
| Shapeless, furnace, brewing, smithing transform/trim | Shapeless supported for material ingots | Furnace/brewing/smithing planned | Fire-charge evidence for shapeless only | Yes for shapeless | Pending | Phase 2A |
| Blocks, ores, crops, material families | Supported for storage block; ores/crops/features remaining | Supported for storage block | Required per remaining archetype | Planned for remaining | Pending | Phase 3 |
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
| Material weapon set generation through OpenAI structured intent | Automated |
| Material armor set generation through OpenAI structured intent | Automated |
| Material consumable (food+fuel) set generation through OpenAI structured intent | Automated |
| Material block (ingot+storage block) set generation through OpenAI structured intent | Automated |
| Blockception schema lint | Pending |
| Physical iPhone import and both packs active | Verified for a generated Emerald Test Sword on iPhone 13 Pro / Minecraft 26.40; the complete Craftberry export-to-Minecraft test passed on 2026-08-05 (originally calibrated on iPhone 16e, now migrated to 13 Pro). |
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
| 2026-08-05 | Add material melee weapon sets before new Bedrock component families | Dagger, spear, and hammer variants reuse the already assertion-covered item, recipe, texture, localization, and archive shapes while broadening item-family generation. |
| 2026-08-06 | Add material armor sets as the first family with genuinely new Bedrock surface (`minecraft:wearable` item component plus `attachables/*.json` and shared armor-layer body textures) | Armor was the next family named in the roadmap, and vanilla armor's geometry, material, and render controller are all built-in identifiers, so the pack only has to ship the attachable stub and two 64x32 textures rather than custom geometry — a bounded slice, backed by exact assertions pinned to `resource_pack/attachables/diamond_*.json` and the `1.21.90` `Wearable` component schema in the pinned Mojang samples. |
| 2026-08-09 | Add material consumable sets (food+fuel) as the next item family with two new Bedrock components (`minecraft:food`, `minecraft:fuel`) | Food/fuel completes the `food, fuel` row of the roadmap's general-items slice; both are stable inventory-only item components with no geometry, and the set reuses the ingot shapeless + shaped recipe pipeline while adding 32×32 food/fuel sprites. |
| 2026-08-09 | Add material block sets (ingot + storage block) as the first blocks slice | The smallest bounded whole-family that introduces `minecraft:block` JSON, terrain textures, and `blocks.json` while reusing the shapeless-ingot + shaped-recipe + `item_texture.json` pipeline: one ingot + one placeable cube (`map_color`/`destroy_time`/`loot` self-drop), 3 recipes (1 shapeless ingot, 1 shaped 9→1 block, 1 shapeless 1→9 deconstruct), 32×32 ingot/block-item sprites + 16×16 terrain tile. |
