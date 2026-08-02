# Phase 2A decision record: custom material ingot + sword

## Shipped semantic scope

One prompt may produce a named ingot and its matching sword. Existing single-sword prompts remain supported. The AI supplies structured intent only; Swift assigns IDs, UUIDs, Bedrock documents, textures, and archives.

- Defaults: Azure, blue, diamond ×4, attack 10, durability 500.
- Ingot: `<material> Ingot`, stack size 64, items category, no combat or durability traits.
- Sword: `<material> Sword` (or an optional supplied name), normal sword equipment traits.
- Ingot recipe: shapeless `crafting_table`, 1–9 copies of one allowed source, one ingot result, source unlock.
- Sword recipe: `[' I ', ' I ', ' S ']`, two generated ingots and `minecraft:stick`, one sword result, ingot unlock.

Allowed sources are amethyst shard, blaze rod, diamond, emerald, gold ingot, iron ingot, lapis lazuli, netherite ingot, quartz, and redstone. The generated catalog is pinned to Mojang `bedrock-samples` v1.26.30.5 commit `921fafb05c93abeae56c2f2868cd8f942bdbcc0f`.

## Evidence and validation

The shapeless form follows Mojang's pinned `behavior_pack/recipes/fire_charge.json`; the item form follows `behavior_pack/items/diamond_spear.json`. XCTest covers semantic construction, v1-to-v2 migration, shapeless limits, cross-recipe graph validation, document emission, archive entries, localization, PNG dimensions, and deterministic archive generation.

Schema lint remains advisory and is intentionally out of the iOS app. `.lang`, PNG decoding, and archive extraction are separately checked. Device acceptance is pending an import on Minecraft 1.26.30 with both packs active, a clean Content Log, and Survival crafting/appearance/combat/durability/unlock checks.

## Deferred and reconsideration triggers

Tools beyond swords, armor, food/fuel, repair/enchantment traits, projectiles, records, placers, furnace/brewing/smithing recipes, blocks/ores/crops, entities, structures, scripting, arbitrary vanilla inputs, custom models, multiple material sets, editing, and user-selected stations remain deferred. Reconsider each only after its closest vanilla sample is pinned, compiler output is assertion-covered, and physical-device acceptance is complete.
