# Craftberry Development Guide

## Workflow

### Required after every change

- Use test-driven development when feasible: add or update a failing test that captures the intended behavior before implementing it, then make it pass. If TDD is not feasible, explain why in the final handoff or PR notes.
- Run the smallest relevant checks while iterating, then run the full unit-test suite before considering a cohesive change complete.
- Keep ordinary validation local and side-effect-free. Builds and tests may write ignored derived data or temporary files, but must not modify Minecraft, iOS device data, Xcode user settings, or external services unless the task explicitly requires it.
- Preserve unrelated or pre-existing worktree changes.
- For this temporary POC workflow, commit and push each cohesive change directly to `main` after its full validation suite passes. Replace this rule with the branch-and-PR flow before the project is shared beyond this local development workflow.
- In the final handoff for every completed increment, give three concrete prompt examples that exercise newly added capabilities, so the user knows what to test manually. State any required local setup (such as a Debug API key) and clearly separate device acceptance that remains pending.

### Pull request flow

- Branch from the default branch unless the work explicitly depends on unmerged changes.
- Use a concise PR title and description that state the user-visible change and validation performed.
- Keep secrets, signed artifacts, device logs containing personal data, and generated Bedrock archives out of commits.

## Project Structure

- `Craftberry/` — native iOS app sources, organized by app shell, feature, domain, AI service, and Bedrock packaging responsibility.
- `CraftberryTests/` — deterministic unit tests for the IR, compiler, pixel renderer, archive layout, and service adapters.
- `CraftberryUITests/` — focused user-flow smoke tests for prompt, result, and error states.
- `Config/` — tracked configuration examples only; real local secrets are ignored.
- `ROADMAP.md` — active add-on architecture, constraints, and incremental delivery plan.
- `CAPABILITIES.md` — support and verification matrix for each pinned Bedrock profile.
- `PLAN.md` — historical custom-sword POC plan.

Update this section when the actual Xcode project layout is introduced or materially changed.

## Principles

- **The LLM produces intent, not game files.** Treat the structured intermediate representation as the sole AI boundary; Swift code owns validation and every Bedrock JSON, PNG, UUID, and archive entry.
- **Keep the Bedrock content profile explicit.** Isolate version-specific paths and schemas in the compiler, generate fresh pack identifiers, and test generated archives against the selected Minecraft release on a physical device.
- **Packaging must be deterministic.** Archive contents, manifest dependencies, and generated identifiers should be inspectable and covered by tests. Never silently emit an invalid or partial add-on.
- **Treat the add-on as the product.** The app builds and exports a valid `.mcaddon`; it does not write into Minecraft's sandbox, activate a pack in a world, or depend on Minecraft being installed. Keep device-transfer validation separate from artifact generation.
- **No distributable client secrets.** A direct API key is allowed only in an ignored Debug-only local configuration for this personal POC. Replace it with a backend before TestFlight, sharing, or release.
- **Prefer native, small dependencies.** Use SwiftUI and Apple frameworks first. Add a package only when it removes meaningful complexity and has a focused responsibility.
- **Accessibility is a feature.** Maintain Dynamic Type, VoiceOver labels, sufficient contrast, and useful loading/error states in every user flow.
- **No unlicensed Minecraft assets.** Use original generated pixel art and plain compatibility text; do not copy Mojang logos, textures, or UI assets.

## Bedrock JSON Validity

Bedrock's actual engine validation is stricter than the official docs, stricter than most third-party guides, and it changes across releases (e.g. recipe `unlock` requirements arrived in 1.20.30). A real custom-sword bug (blank icon, nothing shown in hand, recipe wouldn't complete) survived a hand-rolled PNG encoder audit, a ZIP archive audit, and three rounds of guessing at `minecraft:icon` JSON shape — all before the actual cause was found. It turned out to be two unrelated, engine-enforced rules that no amount of re-reading our own JSON would have surfaced:

- `minecraft:item.description.menu_category.group` must be namespace-prefixed (`"minecraft:itemGroup.name.sword"`, not `"itemGroup.name.sword"`). A parse failure here silently drops other components too — it surfaced as an unrelated "missing icon" error even though the icon JSON itself was already correct. One bad field can cascade into misleading errors elsewhere in the same file.
- `minecraft:recipe_shaped` (and other recipe types) require an `unlock` array as of 1.20.30+. Without it the whole recipe is silently rejected, not just hidden from the recipe book.

### Validating new JSON as features grow

- Don't trust memory, docs pages, or article summaries for exact Bedrock schema requirements — cross-check new fields against real files in [Mojang/bedrock-samples](https://github.com/Mojang/bedrock-samples) (`behavior_pack/items`, `behavior_pack/recipes`, `resource_pack/textures/item_texture.json`, etc.) before writing the Swift that emits them. That repo reflects what the current engine actually accepts; a doc page can lag behind it.
- Every new component or JSON shape the compiler emits needs a concrete assertion in `BedrockCompilerTests` pinned to the same value/structure a working vanilla or previously device-verified file uses — not just "is this valid JSON."
- When adding a new addon kind (not just a new sword variant), diff its emitted files against the closest vanilla equivalent before calling it done — new item/block/entity kinds pull in new components, each with their own hidden validation rules.

### Troubleshooting checklist when generated content "looks right" but fails in-game

1. Turn on the Content Log first (Settings → Creator → Content Log) — before importing anything, not after something's already suspected broken. It reports the exact file, field path, and reason for every parse failure on load.
2. Build the test artifact with a brand-new display name each time (the compiler already generates a random suffix and fresh UUIDs per build). This keeps it unambiguous which pack you're looking at in-game and avoids ever needing to hunt for how to delete a previously imported pack from the device.
3. Import the artifact, activate both packs for the world, load in, and read the Content Log literally — treat its reported file/field path as ground truth over any theory formed from re-reading the emitted JSON alone.
4. Independently rule out the encoding layer before chasing schema theories: confirm the PNG decodes (`sips`, Preview, or PIL) and the ZIP extracts (`unzip`) cleanly. That separates "the file is corrupt" from "the schema is wrong" and avoids re-guessing JSON key names blind.
5. A raw/untranslated tooltip key (`item.namespace:name.name` shown instead of a real display name) specifically points at a resource-pack loading/parsing failure (`item_texture.json`, `texts/languages.json`, or the `.lang` file) — not just a missing translation entry.

## Testing

- Use XCTest as the default test framework; run focused tests while iterating and the full test target before handoff.
- Unit-test all IR validation and defaults, identifier sanitization, manifest dependency wiring, generated JSON, texture dimensions, and both `.mcpack` and `.mcaddon` archive entries.
- Use fixtures and fake `LLMClient` implementations for deterministic app and UI tests. Keep live API tests opt-in and never require a real key for the normal suite.
- Test generic iOS share behavior on a physical device when changing export code. When the Bedrock compiler or packaging layout changes, separately validate an exported artifact in Minecraft on a physical iPhone; this is compatibility coverage, not an app handoff flow.
- Keep generated test archives in temporary directories and clean them up after each test.

### Reaching each UI state manually

`CreationViewModel.State` is `editing → generating → (unsupported | ready) → building → built`, with `failed` reachable from several points. Deterministic fake-client and compiler tests cover these states in `CreationViewModelTests`; a separate `CraftberryUITests` target does not exist yet. Running the app for real:

- `.failed` is reachable with zero setup — tap Generate with an empty or whitespace-only prompt; `generate()` short-circuits before any network call.
- `.generating` / `.ready` / `.unsupported` / `.building` / `.built` all require a live OpenAI call, which needs a real key in the untracked `Config/Secrets.xcconfig` (copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` and set `OPENAI_API_KEY`; `Config/Debug.xcconfig` includes it automatically). Without a key, `generate()` fails immediately with a `missingAPIKey` error instead of reaching those states.
- `CreationViewModel.init` accepts an optional `LLMClient`, compiler, and artifact-directory provider. Keep using those seams for deterministic tests or a future manual Debug override instead of hitting the network or Documents directory.

## Local Commands

Once the Xcode project exists, prefer these commands from the repository root (replace the placeholder scheme and simulator as the project is created):

```sh
xcodebuild -list
xcodebuild -scheme Craftberry -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
xcodebuild -scheme Craftberry -destination 'generic/platform=iOS' build
```

Do not run a signed archive, upload, TestFlight distribution, or device installation unless the user explicitly asks.
