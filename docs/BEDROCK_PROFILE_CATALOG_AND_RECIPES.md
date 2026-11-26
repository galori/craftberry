# Bedrock profile catalog and recipes

The current profile is pinned to [Mojang/bedrock-samples v1.26.30.5 at `921fafb05c93abeae56c2f2868cd8f942bdbcc0f`](https://github.com/Mojang/bedrock-samples/tree/921fafb05c93abeae56c2f2868cd8f942bdbcc0f). The app supports an explicit subset from `Config/vanilla-catalog-allowlist.json`; it does not accept every vanilla identifier.

Run `scripts/refresh-vanilla-catalog.sh` to regenerate `GeneratedVanillaItemCatalog.swift` from the exact sample commit. The command downloads only `metadata/vanilladata_modules` and `behavior_pack/recipes` into ignored `.scratch/`, validates every direct item ID, brewing selector, recipe form, and item tag, then writes the Swift catalog. Pass `--check` to verify the checked-in output without changing it.

## Supported vanilla identifiers

| Catalog group | Explicit subset |
| --- | --- |
| Material inputs | Amethyst shard, blaze rod, diamond, emerald, gold ingot, iron ingot, lapis lazuli, netherite ingot, quartz, redstone |
| Other recipe/fixture items | Egg, feather, stick, wheat, wheat seeds |
| Smithing | Netherite upgrade and Ward trim templates; diamond sword base; `minecraft:trimmable_armors` item tag |
| Brewing inputs | Potion, splash potion, lingering potion; awkward, mundane, thick, and water potion-type selectors |
| Brewing reagents | Blaze powder, dragon breath, ghast tear, gunpowder, nether wart |

The potion-type selectors are Bedrock recipe values rather than ordinary item identifiers. The generator checks each against the pinned brewing recipe files. The trim tag is checked against `smithing_armor_trim.json`.

## Stable recipe forms in the typed compiler

The current intermediate representation and compiler support these seven recipe document types. `GeneratedVanillaItemCatalogTests` checks that the typed factories cover this set, while the catalog generator checks each form against its pinned Mojang sample.

| Recipe form | Mojang sample | Station acceptance |
| --- | --- | --- |
| `minecraft:recipe_shaped` | `behavior_pack/recipes/diamond_sword.json` | Crafting-table recipes are exercised by the existing redstone and emerald scenarios. |
| `minecraft:recipe_shapeless` | `behavior_pack/recipes/mushroom_stew.json` | Crafting-table recipes are exercised by the existing material scenarios. |
| `minecraft:recipe_furnace` | `behavior_pack/recipes/furnace_beef.json` | Furnace input-to-output behavior is pending focused device acceptance. |
| `minecraft:recipe_smithing_transform` | `behavior_pack/recipes/smithing_netherite_sword.json` | Sword upgrade is pending; generated transform JSON omits `template` to match this sample. |
| `minecraft:recipe_smithing_trim` | `behavior_pack/recipes/smithing_armor_trim.json` | Visible armor trim is pending focused device acceptance. |
| `minecraft:recipe_brewing_mix` | `behavior_pack/recipes/brew_awkward_blaze_powder.json` | Brewing-stand mix behavior is pending focused device acceptance. |
| `minecraft:recipe_brewing_container` | `behavior_pack/recipes/brew_potion_sulphur.json` | Container conversion is pending focused device acceptance. |

Other vanilla recipe forms are intentionally outside this profile until they have their own typed fixture and station acceptance.

## Advisory schema coverage

The advisory Blockception schemas validate generated items, recipes, blocks, entities, loot tables, spawn rules, features, and feature rules. `Tools/SchemaFixture` combines projects so one fresh artifact exercises all eight families, and the linter fails if any family is absent. Binary `.mcstructure` data and resource-pack metadata are not JSON families covered by these schemas.

The pinned advisory schema has two checked exceptions in `schemas/blockception/exceptions.json`: its 2025 schema omits the smithing-trim form present in the pinned Mojang sample, and a missing `type: object` on its tag branch makes valid transform ingredient strings fail `oneOf`. The linter matches the exact paths and error kinds and requires the expected occurrence counts. Mojang samples and the Minecraft engine remain the compatibility sources of truth.

## Focused device re-verification still required

| Compiler change | Required scenario | Coverage gap to close |
| --- | --- | --- |
| Block `menu_category` encoding | `block` | Re-run the existing block craft scenario and confirm the pack loads and the custom block is available. |
| Entity event encoding and hostile activation | `entity` | Re-run the existing hostile spawn-and-damage scenario. |
| Passive spawn, birth, and age-up events | Add a passive-entity check to `entity` or a new focused scenario | The current `entity` scenario only generates a hostile creature; it does not verify passive birth or growth. |
| Smithing-transform field shape | Extend `smithing` | The current scenario crafts only the intermediate ingot. It must apply a netherite upgrade to a diamond sword at a smithing table and verify the result. |

Keep these cases pending until their actual in-game assertions pass. Exact generated JSON and the advisory schemas do not substitute for those checks.
