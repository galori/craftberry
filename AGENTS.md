# Craftberry Development Guide

## Communication — Keep It Concise and High-Level

> **This is the top style rule for every user-facing message. Be brief, high-level, and outcome-focused.**

- **Lead with the outcome, not the implementation.** One or two short paragraphs is the default. State what was done / what was found and what remains, not how it was built.
- **Do not dump code-level detail.** Avoid listing changed files, absolute paths, line numbers, commit hashes, struct/field names, JSON snippets, or per-file bullet inventories unless the user explicitly asks for that depth. The user wants the *point*, not the diff.
- **When asked to run a check (e.g. "run the e2e test"), report it like a status update:** what you ran, how far it got, what couldn't be verified and why, and a concrete next step — not a full implementation log.

  **Too detailed (don't do this):** A multi-bullet inventory of every file touched, every type/field added, every commit hash, and full JSON/OCR excerpts that buries the result.

  **Preferred (do this):**
  > Done running the E2E test for the new armor/consumable slice. It got as far as crafting the ingot and food (OCR-verified, no Content Log errors) but timed out during inventory cleanup before it could verify the fuel recipe — the harness hit its 360s limit, not a pack rejection. Next step: re-run `scripts/ios-device.sh minecraft-e2e consumable --fresh-world` on the calibrated device, or bump the harness timeout.

- **Ask simply, then stop.** When you need input or a decision, ask in one concise sentence and wait. Don't add background unless asked.
- **Details are on demand.** Keep deeper specifics in the code/commits/tests themselves. Only expand to file-level or code-level detail when the user says they want it.

## When live-device iteration is slow, ask the human instead of grinding

If you're troubleshooting something on the physical device where each iteration (edit → build → run → screenshot → inspect) takes minutes, and the underlying problem is one a human could diagnose in seconds by just looking at or poking the device directly (e.g. "why isn't this block visible," "why did this UI end up in this state," "is the world in the state I think it's in") — **stop and ask the user to check directly** rather than continuing to guess-and-iterate. This is especially true once you've already spent several rounds without converging. A live human with eyes on the actual screen is strictly faster than another blind probe-and-screenshot cycle. This was learned the hard way: an hour was spent iterating on `/tp`+`/setblock` coordinates for a crafting table that was never visible on screen, when the actual cause (teleporting into open air, then falling before the screenshot) was found by the user in a couple of minutes of direct, hands-on troubleshooting.

## Workflow

### Fast feedback and Minecraft acceptance

The phone suite found real Bedrock failures that passed local tests, so keep device acceptance for behavior that can only be proven in Minecraft. The old workflow ran all fourteen long device scenarios on every pull request. That serial work delayed useful feedback and repeated setup for features that did not change. Use short, targeted checks while iterating, and save the full sweep for scheduled or milestone runs.

- During implementation, run the smallest relevant Swift test or compiler check. Do not run a phone test for documentation-only changes or changes that cannot affect the generated pack, export path, import flow, or gameplay.
- Before merge, run the focused `scripts/ios-device.sh minecraft-e2e <scenario>` for a new or changed Minecraft behavior, compiler shape, or export/import path. Pick the scenario that exercises the changed behavior. If several changes share a scenario, run that scenario once after the changes are ready.
- The agent may group related, low-risk changes into a milestone device run when existing passing scenarios already cover the unchanged behavior. Record the scenarios and reason. Keep each new capability marked as awaiting Minecraft verification until a device scenario exercises its actual in-game behavior and passes.
- Run `scripts/ios-device.sh minecraft-e2e-all` for a roadmap milestone, a broad compiler or packaging change that affects many content families, a Minecraft/profile upgrade, or a release. GitHub Actions also runs this full suite nightly. Run it sooner when the focused result or change scope shows that a wider check is needed.
- A scenario must test the behavior it claims to cover. Importing a pack or crafting an intermediate ingot does not prove brewing, fuel use, armor equipment, crop growth, block drops, entity behavior, or structure placement. Add calibrated in-game actions and visible assertions for new behavior. Do not mark device acceptance complete from generated JSON, a successful build, a skipped test, or a timed-out run.
- `minecraft-e2e redstone` checks the regular `.mcaddon` import and pack activation path. Other feature scenarios use a prepared `.mcworld` with the generated packs already active; they check the feature while avoiding repeated pack-activation menus. This keeps normal import coverage while shortening mechanic checks.
- Keep generated packs and test worlds clean after every run. Prepared-world checks delete only the exact named Craftberry test world. Do not delete a user's world with a partial-name match.
- `scripts/ios-device.sh` has no internal wrapper timeout. Give any outer command enough time for one selected scenario to finish, and inspect its `.xcresult` when it fails.
- If the phone is unavailable, locked, or disconnected, ask the user to restore access. Resume the selected test when the phone is available. Do not replace a required device check with a user handoff.
- A passing focused check marks only the behavior it exercised. A full suite result applies only to the code revision and Minecraft version recorded with that run.

### Minecraft Dedicated Server checks

Consider Bedrock Dedicated Server as an extra, faster engine-load check only after a small proof shows that it catches faults the Swift checks miss. It can load a prepared world and report content errors in its log. It does not show the client UI, rendering, item appearance, touch behavior, crafting-screen flow, or other client-only behavior. Keep the physical iPhone checks for those outcomes.

- Use a server build that matches the active Bedrock profile. The official server currently runs on Windows and Ubuntu Linux, so it needs a compatible Linux CI runner or a separate test host.
- Start with a known-good pack and intentionally broken packs. Require the known-good pack to load and the broken cases to fail before treating the server run as a useful gate.
- Capture the server content log and fail on relevant load errors. Verify pack installation and world pack references as well as process startup.
- Keep GameTest outside the stable acceptance gate unless the active profile can run it without experimental APIs and repeated trials prove it stable.
- Treat the server check as an added engine signal. It does not replace the focused phone scenario or the milestone full sweep.

### Branching — one worktree per task (required)

- Always create each task on its own git worktree under `./worktrees/<slug>` on a dedicated branch. Do not work directly in the repository root for branch or pull-request work. From the repository root: `git worktree add worktrees/<slug> -b <branch>` and do all edits inside that worktree.
- `worktrees/` is ignored globally (do not commit worktree contents from the root). Keep unrelated or pre-existing worktree changes out of the commit.
- Expect to request or escalate permissions whenever the workflow requires actions outside the current worktree or sandboxed write area (creating/deleting worktrees, updating `main`, interacting with GitHub via `gh`). Do not skip those steps because they require approval.
- Multiple independent tasks may run in parallel only when the model judges that their branches, worktrees, and PR lifecycles can remain safely isolated. Do not stack PRs — branch every change off `main` and target `main`; never open a PR whose base is another feature branch.

### Pull request flow (required)

- Never commit directly on `main`. Always branch from `main` unless the work explicitly depends on unmerged changes.
- After the change is complete and verified locally, commit, push the branch, open a PR against `main`, and enable auto-merge: `gh pr create --title "..." --body "..." && gh pr merge --auto --squash` (use the repo's default merge method). Do not wait for checks or merge manually — auto-merge completes the merge once required checks are green.
- Use a concise PR title and one-paragraph body stating the user-visible change and validation performed.
- Keep secrets, signed artifacts, device logs containing personal data, and generated Bedrock archives out of commits.

### Completion — PR must be green and merged

- A task is not complete until its PR is green and merged into `main`. Green means all required GitHub Actions checks (unit tests and lint — E2E device tests are excluded from CI and verified locally) pass and the PR has been auto-merged.
- After the PR merges, update the local `main` and clean up — but **never delete the worktree you are currently inside**. Removing the worktree that contains your session's `pwd` invalidates the workspace root (`workspace root is invalid: No such file or directory`) and breaks every subsequent tool call, requiring manual `mkdir -p` recovery. Safe order:
  1. `git worktree list` and `pwd` / `git rev-parse --show-toplevel` — confirm which worktree you are in before touching anything.
  2. `cd` to the main worktree first (e.g. `cd /Users/gall/workspace/craftberry`), then update `main` there: `git fetch origin && git checkout main && git pull --ff-only`. Alternatively, run every git command with `git -C /Users/gall/workspace/craftberry ...` so the main worktree is the target.
  3. Only then, **from the main worktree**, delete the task's worktree (`git -C /Users/gall/workspace/craftberry worktree remove worktrees/<slug>` or `git worktree remove <absolute-path-to-worktree>`) and prune the branch (`git branch -d <branch>`). Do not run `git worktree remove` targeting the worktree that contains your current `pwd`; if you need `--force`, you are likely still inside it — `cd` out first.
  4. `git worktree list` again to confirm removal before starting the next task.
  - If your session is still rooted in the task worktree, do not remove it — create the next task's worktree first or switch sessions, and **ask before deleting any worktree you are currently inside**.
- E2E device acceptance remains required for behavior tracked in the Craftberry Orca roadmap at `~/workspace/repo-notes/projects/craftberry/`. It does not replace green CI checks.

### Required after every change

- Use test-driven development when feasible: add or update a failing test that captures the intended behavior before implementing it, then make it pass. If TDD is not feasible, explain why in the final handoff or PR notes.
- Run the smallest relevant checks while iterating, then run the full unit-test suite before considering a cohesive change complete: `swift test` or `xcodebuild -scheme Craftberry -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:CraftberryTests test`.
- Run the linter before committing: `scripts/lint.sh` (or `swiftlint lint --strict` if installed). The pre-commit hook runs the same check on staged files — install it with `git config core.hooksPath .githooks` or `scripts/setup-hooks.sh`.
- Follow the test scope in “Fast feedback and Minecraft acceptance” above. Run the selected focused device scenario before merging Minecraft behavior changes, and use a milestone run when related scenarios can prove a grouped set of changes. Do not run the full thirteen-scenario suite after every edit.
- Keep ordinary validation local and side-effect-free. Builds and tests may write ignored derived data or temporary files, but must not modify Minecraft, iOS device data, Xcode user settings, or external services unless the task explicitly requires it.
- Preserve unrelated or pre-existing worktree changes.
- Every time a new capability ships (a new content family, item kind, trait, or supported vanilla material), add a handful of new example prompts for it to `ExamplePromptLibrary` in `Craftberry/App/ExamplePromptLibrary.swift`. The welcome screen samples three of these at random and the user can shuffle for three more, so the collection is how players discover what the app can now build. Prompts must stay inside the active capability profile — supported materials only, attack 1–30, durability 50–2,000, names of 32 characters or fewer — so tapping one never lands in `.unsupported`. `ExamplePromptLibraryTests` enforces the collection's size, per-kind coverage, and that every supported material in `GeneratedVanillaItemCatalog` appears in at least one prompt; extending the catalog will fail those tests until prompts are added.
- In the final handoff for every completed increment, give three concrete prompt examples that exercise newly added capabilities, so the user knows what to test manually. State any required local setup (such as a Debug API key) and clearly separate device acceptance that remains pending.
- Write all temporary files to `.scratch/` (not `/tmp` or `$TMPDIR`). `/tmp` is cleared on reboot and loses handoffs — `.scratch/` is the durable, ignored workspace scratch space.

## Project Structure

- `Craftberry/` — native iOS app sources, organized by app shell, feature, domain, AI service, and Bedrock packaging responsibility.
- `CraftberryTests/` — deterministic unit tests for the IR, compiler, pixel renderer, archive layout, and service adapters.
- `CraftberryUITests/` — focused user-flow smoke tests for prompt, result, and error states; also holds `MinecraftHandoffUITests`, which drives Safari (not Craftberry) for standalone Minecraft-import validation.
- `Tools/MinecraftFixture/` — a `swift run`-able CraftberryCore consumer that compiles a fresh fixture `.mcaddon` on the Mac for `scripts/minecraft-import.sh`, without needing a device.
- `Config/` — tracked configuration examples only; real local secrets are ignored.
- `ROADMAP.md` — pointer to the canonical Orca project roadmap and handoffs.
- `~/workspace/repo-notes/projects/craftberry/` — Orca project status, roadmap, decisions, and active work plans.
- `CAPABILITIES.md` — repository-facing support and verification matrix for the pinned Bedrock profile.
- `PLAN.md` and `PHASE2_MATERIAL_SWORD_SET.md` — pointers to historical Orca plans.
- `REMOTE_DEBUG.md` and `REFACTORING_OPPORTUNITIES.md` — pointers to Orca implementation history and the current engineering backlog.
- `docs/MINECRAFT_DEVICE_AUTOMATION.md` — current device-automation and acceptance procedure.
- `.scratch/` — ignored local scratch space for temporary handoffs, investigation notes, and repro artifacts. Contents never committed and survive reboots (unlike `/tmp`). Use it for anything that would otherwise go to `/tmp`.

Update this section when the actual Xcode project layout is introduced or materially changed.

## Principles

- **The LLM produces intent, not game files.** Treat the structured intermediate representation as the sole AI boundary; Swift code owns validation and every Bedrock JSON, PNG, UUID, and archive entry.
- **Keep the Bedrock content profile explicit.** Isolate version-specific paths and schemas in the compiler, generate fresh pack identifiers, and test generated archives against the selected Minecraft release on a physical device.
- **Packaging must be deterministic.** Archive contents, manifest dependencies, and generated identifiers should be inspectable and covered by tests. Never silently emit an invalid or partial add-on.
- **Treat the add-on as the product.** The app builds and exports a valid `.mcaddon`; it does not write into Minecraft's sandbox, activate a pack in a world, or depend on Minecraft being installed. Keep device-transfer validation separate from artifact generation. This is a statement about the app, not about tooling: `scripts/minecraft-import.sh` and `scripts/minecraft-mirror-drive.sh` (see README's "Minecraft validation" section) automate that device-transfer validation externally, entirely outside the app and its own test targets.
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

## Continuous Integration

- Every PR runs GitHub Actions (see `.github/workflows/ci.yml` and `lint.yml`): unit tests via `swift test` (which runs `CraftberryTests` only) and SwiftLint. Both must be green before auto-merge. Device tests run on the focused or milestone schedule above.
- Branch protection requires these checks on `main`; the pre-commit hook (`scripts/lint.sh` via `.githooks/pre-commit`) runs the same lint locally before push.

## Testing

- Use XCTest as the default test framework; run focused tests while iterating and the full test target before handoff. In CI, only `CraftberryTests` runs — `CraftberryUITests` / `MinecraftDeviceE2EUITests` are device-only and excluded from PR checks.
- For Minecraft Ore UI automation, follow `docs/MINECRAFT_DEVICE_AUTOMATION.md`: use normalized USB/XCTest coordinates and require screenshot/OCR evidence; never use Mirroring pointer clicks or treat successful gesture synthesis alone as acceptance. Optional Bedrock banners can shift controls, so layout-variant taps must be followed by exact OCR of the intended screen/item before the flow continues; record new engine/UI constraints in README's compatibility-learnings list and keep this procedure current.
- Unit-test all IR validation and defaults, identifier sanitization, manifest dependency wiring, generated JSON, texture dimensions, and both `.mcpack` and `.mcaddon` archive entries.
- Use fixtures and fake `LLMClient` implementations for deterministic app and UI tests. Keep live API tests opt-in and never require a real key for the normal suite.
- Test generic iOS share behavior on a physical device when changing export code. When the Bedrock compiler or packaging layout changes, separately validate an exported artifact in Minecraft on the dedicated iPhone 13 Pro; this is compatibility coverage, not an app handoff flow. The previous iPhone 16e (37875F01…) is retired — do not report it as missing/disconnected or require it to be connected; treat the 13 Pro as the sole calibrated device.
- `scripts/minecraft-import.sh` and `scripts/minecraft-mirror-drive.sh` automate that separate Minecraft-side validation (import via Safari, activation and in-game verification via iPhone Mirroring + OCR) — see README's "Minecraft validation" section for the two-leg design and why they can't run concurrently. As of 2026-08-02, leg 1 (`minecraft-import.sh`) is verified end-to-end on the dedicated iPhone 13 Pro: every `MinecraftHandoffUITests` identifier was calibrated against live accessibility-tree dumps (not guessed), and it reliably imports a fresh fixture into Minecraft (confirmed via `.wait(for: .runningForeground)`) across repeated real-device runs. One residual flake — Safari's address bar intermittently loses keyboard focus right after tapping, a widely-reported XCUITest/Safari issue that several different in-test mitigations couldn't fully eliminate — is absorbed by retrying the whole `xcodebuild test` invocation up to 3 times in the script rather than the test itself. Suspected (not yet confirmed) root cause: physically rotating the device mid-run re-lays out Safari and can drop focus at exactly that moment; `minecraft-import.sh` now prints a reminder to keep rotation lock on, since there's no CLI/XCUITest API to verify or enforce it. Leg 2 (`minecraft-mirror-drive.sh`) is calibrated against the same iPhone and creative world: Minecraft's custom Ore UI ignores mirrored pointer events, so the runner uses Tab/arrow-key focus navigation and Return instead. It verified behavior/resource-pack activation, world load, a correctly rendered custom sword, and an OCR match on the fixture's pack ID in the load-time Content Log. Direct creative-inventory localization lookup remains pending because its grid did not accept keyboard focus navigation. The full Craftberry export-to-Minecraft acceptance suite is now `MinecraftDeviceE2EUITests`; run `scripts/ios-device.sh minecraft-e2e [redstone|emerald]` for the physical-device scenarios.
- Keep generated test archives in temporary directories and clean them up after each test.

### Reaching each UI state manually

`CreationViewModel.State` is `editing → generating → (unsupported | ready) → building → built`, with `failed` reachable from several points. Deterministic fake-client and compiler tests cover these states in `CreationViewModelTests`; `CraftberryUITests` covers the physical-device smoke flow through the iOS share sheet. Running the app for real:

- `.failed` is reachable with zero setup — tap Generate with an empty or whitespace-only prompt; `generate()` short-circuits before any network call.
- `.generating` / `.ready` / `.unsupported` / `.building` / `.built` all require a live OpenAI call, which needs a real key in the untracked `Config/Secrets.xcconfig` (copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` and set `OPENAI_API_KEY`; `Config/Debug.xcconfig` includes it automatically). Without a key, `generate()` fails immediately with a `missingAPIKey` error instead of reaching those states.
- `CreationViewModel.init` accepts an optional `LLMClient`, compiler, and artifact-directory provider. Keep using those seams for deterministic tests instead of hitting the network or Documents directory.
- The internal `--ui-testing` launch argument is Debug-only and reserved for XCTest. It injects deterministic generation and a temporary artifact directory; Release builds must not enable fake behavior.

## Local Commands

```sh
xcodebuild -list
swift test                                          # unit tests only (CI uses this; excludes E2E/UI)
xcodebuild -scheme Craftberry -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:CraftberryTests test
xcodebuild -scheme Craftberry -destination 'generic/platform=iOS' build
scripts/lint.sh                                     # SwiftLint (requires `brew install swiftlint`)
scripts/setup-hooks.sh                              # install pre-commit hook -> .githooks
scripts/ios-device.sh list
scripts/ios-device.sh test
```

Do not run a signed archive, upload, TestFlight distribution, or device installation unless the user explicitly asks.
