# Interactive Minecraft E2E Calibration

## Summary

Create one shared Minecraft step driver with two interactive frontends:

- **Human:** Xcode breakpoints and LLDB commands resembling `binding.irb`.
- **Agent:** a resumable USB-only JSON controller invoked through a shell CLI.
- Keep Craftberry generation/export/import automatic; interactive control begins after Minecraft's post-import cold launch and covers configuration, pack activation, world setup, and crafting.
- Remove the temporary timed observation pauses once interactive checkpoints replace them.

## Implementation Changes

- Extract `MinecraftStepExecutor` from the harness. It executes gestures, keyboard input, commands, OCR, and pixel checks and returns a `MinecraftStepResult` instead of posting XCTest failures itself.
- Keep the normal E2E behavior unchanged: the production harness executes every step, attaches screenshots, and converts unsuccessful results into XCTest failures.
- Introduce phased step metadata with stable run-local IDs such as `config:12` and `crafting:4`, plus the existing human-readable name and action.
- Add an `@inline(never)` before-step and after-step checkpoint with a debugger-visible `MinecraftDebuggerConsole`.
- The debugger console exposes `runCurrentStep`, `skipCurrentStep`, `tap`, `drag`, `swipeUp`, `keyboardText`, `numericKeyboardText`, `chatCommand`, `wait`, `recognizedText`, and `screenshot`. Running a step manually marks it executed so continuing does not repeat it.
- Remove `MINECRAFT_E2E_OBSERVE_*` handling and the temporary 60/45-second crafting pauses.

## Agent Controller

- Add dedicated calibration UI tests for emerald, redstone tools, weapons, and armor. Each performs automatic Craftberry export/import, cold-launches Minecraft, then waits indefinitely for controller commands.
- Run a test-only `Network.framework` TCP listener on device port `8765`; use installed `iproxy` to expose it only as `127.0.0.1:8765` on the Mac.
- Use one newline-delimited JSON request per connection. Responses include success/error, scenario, phase, cursor, completed/current/next step, execution result, and optional screenshot PNG/OCR.
- Add `scripts/minecraft-calibrate.sh` with:
  - `start <scenario> [--break-at <id-or-name>]`
  - `status`, `list-steps`, `observe [--ocr]`
  - `step`, `run-until <id-or-name>`, `mark-complete`, `select-step <id-or-name>`
  - `tap`, `drag`, `swipe-up`, `keyboard-text`, `numeric-keyboard-text`, `chat-command`, `wait`
  - `stop [--keep-state]`
- `run-until` stops before its target and stops immediately on failure. Failed planned steps do not advance the cursor. Arbitrary actions never advance it.
- `select-step` changes only the cursor and explicitly does not restore Minecraft UI state.
- The script runs `xcodebuild` and `iproxy` as tracked background processes, supports reconnecting across agent turns, refuses concurrent sessions, and records logs, command transcripts, result bundles, and decoded screenshots under `.build/minecraft-calibration/`.
- Normal `stop` terminates Minecraft and runs existing AFC cleanup. `--keep-state` leaves Minecraft, packs, and the world untouched.
- Malformed commands, stale sessions, port conflicts, device disconnects, and unexpected XCTest exits return actionable JSON and preserve logs.

## Documentation and Tests

- Document the Xcode breakpoint workflow, LLDB examples, agent CLI lifecycle, pause/human-handoff/resume flow, cleanup behavior, prerequisites, and troubleshooting in the Minecraft automation guide and README.
- Add failing tests first for protocol coding, cursor advancement, failure retention, `run-until`, arbitrary actions, mark-complete, step selection, reconnect-safe state, and debugger duplicate-execution prevention.
- Run focused `MinecraftE2ESupportTests`, shell syntax checks, `swift test`, then the full simulator XCTest suite.
- Validate on the physical iPhone:
  1. Start an emerald calibration session.
  2. Pause at the first Minecraft step.
  3. Obtain screenshot and OCR through the CLI.
  4. `run-until` the world-list step and verify the resulting observation.
  5. Leave the session idle, confirm physical interaction remains possible, then resume.
  6. Stop and confirm automatic AFC cleanup.
  7. Perform a short human-assisted Xcode/LLDB checkpoint smoke test.
  8. Run the normal emerald E2E once to verify the noninteractive path.
- If physical-device diagnosis stops converging, pause and ask the user to inspect or interact instead of repeating blind device runs.
- Commit and push the cohesive workflow directly to `main` after validation; the push will also publish the already-committed `750e2c6` baseline currently ahead of `origin/main`.

## Assumptions

- One calibration session and one physical iPhone are supported at a time.
- The fixed device port is acceptable because the host side binds only to localhost and the listener exists only during the calibration UI test.
- No API key is required because the existing deterministic UI-testing fixtures remain in use.
- No `ExamplePromptLibrary` changes are needed because this adds test tooling rather than a player-facing generation capability; the final handoff will still provide three existing scenario prompts for manual verification.

## Progress Tracking

Last updated: 2026-08-07.

| Item | Status | Notes |
| --- | --- | --- |
| `MinecraftStepExecutor` extraction | Done | `CraftberryUITests/Support/MinecraftStepExecutor.swift`. Returns `MinecraftStepResult` instead of asserting; harness converts failures to `XCTFail`. Commit `f414dd4`. |
| Phased step metadata (`config:12`, `crafting:4`) | Done | `MinecraftPhasedStep` + `Array<MinecraftStep>.phased(as:)` in the same file. Commit `f414dd4`. |
| `@inline(never)` before/after-step checkpoints + `MinecraftDebuggerConsole` | Done | `CraftberryUITests/Support/MinecraftDebuggerConsole.swift`. Exposes `runCurrentStep`, `skipCurrentStep`, `tap`, `drag`, `swipeUp`, `keyboardText`, `numericKeyboardText`, `chatCommand`, `wait`, `recognizedText`, `screenshot`. Commit `78a41c4`. |
| Xcode breakpoint / LLDB workflow docs | Done | New section in `docs/MINECRAFT_DEVICE_AUTOMATION.md` ("Interactive calibration: the LLDB debugger console"). Commit `78a41c4`. |
| Remove `MINECRAFT_E2E_OBSERVE_*` handling | Not started | Still present in `MinecraftE2EHarness.swift` (`observeIfRequested`, the two env keys). Deliberately deferred — removing it now, before the agent controller replaces it, would leave no interactive-checkpoint equivalent for automated/CI-style runs. |
| Remove the temporary 60/45s crafting pauses | Not started | Still present in `MinecraftCraftingPlanCompiler.swift` (`observeBeforeFinalTake` / `observeAfterFinalTake`). Same reasoning as above. |
| Agent Controller: calibration UI tests (emerald/redstone tools/weapons/armor) that wait indefinitely for controller commands | Not started | |
| Agent Controller: on-device `Network.framework` TCP listener (port 8765) + `iproxy` exposure | Not started | |
| Agent Controller: newline-delimited JSON protocol | Not started | |
| Agent Controller: `scripts/minecraft-calibrate.sh` CLI (`start`, `status`, `list-steps`, `observe`, `step`, `run-until`, `mark-complete`, `select-step`, `tap`/`drag`/etc., `stop`) | Not started | |
| Agent Controller: background-process tracking, reconnect-safe state, concurrent-session refusal, logs under `.build/minecraft-calibration/` | Not started | |
| Agent CLI lifecycle docs (README + automation guide) | Not started | Human/LLDB side is documented; agent CLI side is not, because it doesn't exist yet. |
| Failing-tests-first: protocol coding, `run-until`, arbitrary actions, mark-complete, step selection, reconnect-safe state | Not started | Depends on the CLI/protocol above. Debugger duplicate-execution-prevention tests *are* done (see `MinecraftE2ESupportTests`), since that piece landed. |
| Full simulator XCTest suite run (as part of validation) | Not started | Individual builds/tests have been run per increment (`swift test`, targeted `xcodebuild test`, `build-for-testing` for the full UI target), but not the full validation pass this spec describes. |
| Physical-iPhone validation checklist (8 steps under "Documentation and Tests") | Not started | Requires a human at the device; two manual smoke tests happened informally in this session (running an emerald test from the Test Navigator, discussing Test Navigator spinner behavior) but not the structured checklist. |
| Commit and push to `main` | Partially done, deliberately not pushed | Two commits made locally (`f414dd4`, `78a41c4`), each after its own increment rather than one push at the end. Not pushed to `origin/main` — that's being held for explicit confirmation regardless of what this file says, since a push is a shared-state action; ask before pushing. |

**Suggested next increment:** the Agent Controller — on-device TCP/JSON listener plus `scripts/minecraft-calibrate.sh`. That's what would let an agent (not just a human at LLDB) drive a session turn-by-turn.
