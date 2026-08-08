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
