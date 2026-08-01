# Craftberry iOS POC

## Summary

Build a native SwiftUI iPhone app that turns one prompt into one playable Bedrock custom sword. V1 supports only: name, one of 16 sword colors, attack bonus, durability, and a standard sword recipe using one supported vanilla ingredient.

```text
Prompt → structured SwordSpec → local validation → local pixel-art renderer
→ Behavior Pack + Resource Pack → two .mcpack files → .mcaddon → iOS share sheet
```

The model never writes Bedrock JSON. The app’s deterministic compiler owns every Bedrock file, identifier, UUID, texture, manifest, recipe, and archive.

## Architecture and interfaces

- Target iOS 17+ using SwiftUI, Observation, `URLSession`, CoreGraphics/ImageIO, XCTest, and ZIPFoundation. Avoid additional architecture frameworks and persistence for v1.
- Organize the app into `Domain` (IR and validation), `Services/AI` (provider protocol and OpenAI client), `Services/Bedrock` (texture renderer, compiler, packager), and the Create/Result/Export feature UI.
- Use OpenAI’s Responses API with structured JSON output, `gpt-5.6-terra`, and low reasoning effort. Keep the client behind an `LLMClient` protocol so a future backend proxy changes only that adapter. OpenAI currently positions Terra as the intelligence/cost balance. [OpenAI model guidance](https://developers.openai.com/api/docs/models)
- Define the strict LLM contract as:

  ```text
  SwordGeneration
    schemaVersion: 1
    outcome: ready | unsupported
    message: String
    sword (ready only):
      displayName: String
      color: red|orange|yellow|lime|green|cyan|blue|purple|magenta|pink|white|gray|black|brown|gold|silver
      attackBonus: Int (1...30)
      durability: Int (50...2000)
      craftingIngredient: diamond|emerald|iron_ingot|gold_ingot|netherite_ingot|amethyst_shard|blaze_rod|redstone|lapis_lazuli|quartz
  ```

  Defaults for omitted details are blue, `+10` attack bonus, `500` durability, and diamond. Unsupported requests return an explanatory result with a supported example instead of a partial add-on.

- Generate the Bedrock identifier locally as `craftberry:<sanitized-name>_<random-suffix>`; generate all four pack/module UUIDs locally. Do not trust model-provided identifiers or JSON.
- Compile a manifest-v2 behavior pack and companion resource pack, with the behavior pack declaring the resource-pack dependency. Emit the custom item, fixed two-ingredient-plus-stick sword recipe, item-texture map, 32×32 original pixel-art PNG, and matching pack icon. Use a pinned, device-tested Bedrock 1.21.80+ content profile; isolate version-specific JSON in the compiler for later upgrades.
- Zip each pack as a root-level `.mcpack`, then zip both into a `.mcaddon`. This matches Bedrock’s composite add-on format. [Minecraft file extensions](https://learn.microsoft.com/en-us/minecraft/creator/documents/minecraftfileextensions?view=minecraft-bedrock-stable)

## MVP experience

- Present a single polished creation screen: prompt field, example chips, Generate button, loading/error state, and a result card showing the rendered sword, color, attack bonus, durability, and recipe.
- The result card offers Regenerate and Create Add-On. After packaging, offer “Open in Minecraft” using a `UIActivityViewController`, plus a save-to-Files fallback and clear import instructions. Apple’s share sheet is the supported system handoff for sharing file copies to another app. [Apple sharing documentation](https://developer.apple.com/documentation/uikit/collaborating-and-sharing-copies-of-your-data)
- After import, explain that the player must enable the behavior pack in a world; Bedrock activates its linked resource pack, then the sword can be crafted or obtained with the displayed `/give` command. Bedrock’s own item guidance follows this pack-and-world activation flow. [Minecraft Item Wizard guide](https://learn.microsoft.com/en-us/minecraft/creator/documents/minecraftitemwizard?view=minecraft-bedrock-stable)
- Do not include a world template, accounts, history/gallery, arbitrary recipes, image generation, custom models, scripts, or Minecraft assets/logos in v1.

## Phased delivery

1. Prove the device integration: scaffold the app, compile a fixed “Azure Sword,” render its texture, package it, and import it into Minecraft on a physical iPhone.
2. Add the structured LLM request, schema decoding, validation, unsupported-request handling, and the prompt-to-preview UI.
3. Add the export guide, graceful network/key/archive errors, accessible polish, automated tests, and real-device regression coverage.

## Test plan and assumptions

- Unit-test IR decoding/defaults, identifier sanitization, validation rejection, pixel PNG dimensions, emitted JSON, unique UUID/dependency wiring, expected ZIP entries, and nested `.mcpack`/`.mcaddon` structure.
- Add UI smoke tests for ready, unsupported, network-error, and packaging-error states. Maintain prompt fixtures for the supplied blue-diamond-sword example and ambiguous/unsupported requests.
- Manually verify on a physical iPhone running the target Minecraft release: import succeeds, the pack appears in world settings, enabling the behavior pack activates resources, the sword appears or can be given, crafts from two selected ingredients plus a stick, displays its texture, damages entities, and loses durability in Survival.
- Per your choice, the first build embeds a development-only API key through an ignored Debug Xcode configuration and is for your personal device only. It must never be archived, TestFlighted, or distributed; OpenAI explicitly advises against shipping a key in a mobile client. Replace this adapter with a server-side proxy before any sharing or release. [OpenAI API key safety](https://help.openai.com/en/articles/5112595-best-practices-for-api-key-safety)
- iOS cannot write inside Minecraft’s sandbox or auto-enable packs in a world; sharing/importing the add-on and guiding the final in-game activation is the reliable MVP path. [Minecraft iOS installation guidance](https://learn.microsoft.com/en-us/minecraft/creator/documents/gettingstarted?view=minecraft-bedrock-stable)
