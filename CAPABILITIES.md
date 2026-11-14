# Bedrock Capability Matrix

Status as of 2026-11-08. “Automated” means deterministic local XCTest coverage. “Device” requires an exported artifact imported into the exact Minecraft release on a physical iPhone with a clean Content Log.

Project roadmap, milestone status, and decisions are maintained in Orca at `~/workspace/repo-notes/projects/craftberry/`. This file remains the repository-facing capability and verification reference.

## Active profile

| Profile | Mojang sample source | Minimum engine | Compiler | Automated | Device |
|---|---|---:|---|---|---|
| `bedrock-stable-1.26.30` | `bedrock-samples` `1.26.30.5`, commit `921fafb05c93abeae56c2f2868cd8f942bdbcc0f` | 1.26.30 | Active | Passing locally | Pending |

The profile currently carries the format versions and the small vanilla item catalog required by the foundation slice. Catalog generation from the pinned samples, selective Blockception schema validation covers structure features and feature rules; broader schema coverage and exception tracking remain planned before Phase 2 is accepted.

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
| Material ingot + furnace-smelted sword collection (ingot + sword) | Supported | Typed `minecraft:recipe_furnace` (`tags: ["furnace"]`, string `input` string `output`, `unlock`), shaped sword recipe, 32×32 ingot/sword sprites, localization, packs | Exact assertions pinned to `behavior_pack/recipes/furnace_beef.json` / `furnace_iron_ore.json` `minecraft:recipe_furnace` at `921fafb0` | Yes | Pending | Phase 4d code complete |
| Material ingot + brewing-stand elixir collection (ingot + elixir) | Supported | Typed `minecraft:recipe_brewing_mix` + `minecraft:recipe_brewing_container` (`tags: ["brewing_stand"]`, string `input`/`reagent`/`output`), shapeless ingot recipe, 32×32 ingot/elixir sprites, localization, packs | Exact assertions pinned to `behavior_pack/recipes/brew_awkward_blaze_powder.json` `minecraft:recipe_brewing_mix` and `behavior_pack/recipes/brew_potion_sulphur.json` `minecraft:recipe_brewing_container` at `921fafb0` | Yes | Pending | Phase 4e code complete |
| Material ingot + ore block collection (ingot + ore) | Supported | Typed `minecraft:block` (`destroy_time`/`map_color`/`loot` → ingot + `light_dampening`), `loot_tables/blocks/*.json` → ingot, `terrain_texture.json` + `blocks.json`, 32×32 ore-item + 16×16 ore terrain tile, shapeless ingot + shaped 9→1 ore, localization, packs | Exact assertions pinned to `minecraft:block` + `terrain_texture.json`/`blocks.json` and loot `name: craftberry:*_ingot` at `921fafb0` (ore loot drops ingot, not self) | Yes | Pending | Phase 4f code complete |
| Material seed + crop block + produce collection (seed + crop + produce) | Supported | Typed `minecraft:block` with `states: {"craftberry:growth": {"values": {"min":0,"max":7}}}` + 8 `permutations` (`query.block_state('craftberry:growth') == N`), `loot_tables/blocks/*.json` → produce, `terrain_texture.json` + `blocks.json`, 32×32 seed/produce + 16×16 crop terrain tile, shapeless 4× seed, localization, packs | Exact assertions pinned to `metadata/json_schemas/server/block/1.21.110/States.json` + `Block Permutations.json` at `921fafb0` + vanilla crop states/permutations pattern | Yes | Pending | Phase 4g code complete |
| Material sword enchanting | Supported for material sword sets | `minecraft:enchantable` sword slot, value 10 | Pinned Mojang `metadata/json_schemas/server/item_components/1.20.50/Enchantable.json` at `921fafb0` | Yes | Pending | Enchanting-table behavior requires device verification |
| Food, fuel, other wearables, broader item traits | Supported for food/fuel via consumable set; remaining wearables/traits planned | Planned for remaining | Required per emitted shape | Planned | Pending | Later Phase 4 |
| Shapeless, furnace, brewing, smithing transform/trim | Shapeless supported for material ingots; furnace supported via furnace set; brewing supported via brewing set | Brewing: `minecraft:recipe_brewing_mix`/`container` via brewing set; smithing planned | Fire-charge evidence for shapeless; furnace_beef/iron_ore and brew_awkward_blaze_powder/brew_potion_sulphur evidence at `921fafb0` | Yes for shapeless + furnace + brewing | Pending | Phase 2A / 4d / 4e |
| Blocks, ores, crops, material families | Supported for storage block, ore, and crop; features remaining | Supported for storage block, ore (`loot` → ingot), and crop (`states`/`permutations`) | Required per remaining archetype (features) | Planned for features | Pending for features | Phase 3 (ore/crop code complete) |
| Entities, projectiles, spawning, loot, trades | Passive and ground hostile player-targeting creatures supported; tameable/rideable/projectile/boss remaining | Typed `minecraft:attack`, `minecraft:behavior.nearest_attackable_target`, `minecraft:behavior.melee_box_attack`, monster spawn rules, shared spawn-egg/loot/resource wiring | Hostile AI is pinned to Mojang `behavior_pack/entities/zombie.json` and hostile spawn conditions to `behavior_pack/spawn_rules/spider.json` at `921fafb0`; passive shape remains pinned to chicken | Yes for passive and hostile | Pending | Phase 4 hostile slice implemented; device verification pending |
| Material ingot + storage block + 3x3 hut structure collection (ingot + block + hut) | Supported | Typed `minecraft:structure_template_feature` + `minecraft:feature_rules` + deterministic `.mcstructure` (3x3 hut, doorway, reusing block), `structures/*.mcstructure`, `features/*_feature.json`, `feature_rules/*_rule.json` | Exact assertions pinned to `minecraft:structure_template_feature` `structure_name`/`constraints`/`adjustment_radius` and `minecraft:feature_rules` `places_feature`/`placement_pass`/`minecraft:biome_filter` at `921fafb0` + deterministic NBT | Yes | Pending | Phase 5 (bounded hut) |
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
| Material furnace (furnace-smelted ingot + sword) set generation through OpenAI structured intent | Automated |
| Material brewing (brewing-stand elixir) set generation through OpenAI structured intent | Automated |
| Material ore (ingot+ore) set generation through OpenAI structured intent | Automated |
| Material crop (seed+crop+produce) set generation through OpenAI structured intent | Automated |
| Material structure (ingot+block+hut) set generation through OpenAI structured intent | Automated |
| Material hostile entity set generation through OpenAI structured intent | Automated |
| Blockception schema lint | Advisory CI checks generated structure features and feature rules; broader coverage pending |
| Physical iPhone import and both packs active | Verified for a generated Emerald Test Sword on iPhone 13 Pro / Minecraft 26.40; the complete Craftberry export-to-Minecraft test passed on 2026-08-05 (originally calibrated on iPhone 16e, now migrated to 13 Pro). |
| Creative crafting, localized name, and in-hand selection | Verified for Emerald Test Sword by the same physical-device test. |
| Clean Content Log; Survival crafting, appearance, combat, durability | Pending |
