# Minecraft Device Automation

## Purpose

This guide describes how Craftberry integration tests interact with Minecraft
Bedrock on the same physical iPhone. Minecraft uses a custom-rendered Ore UI
that exposes no useful accessibility elements, so its UI requires calibrated
device-level coordinates plus screenshot assertions.

## Control transports

### USB + XCUITest

Use for genuine iPhone touch input:

- Quit iPhone Mirroring.
- Unlock the iPhone and connect it by USB.
- Keep Developer Mode enabled and accept passcode/trust prompts.
- Run XCTest through `xcodebuild` and the existing `CraftberryUITests` target.
- Use `XCUICoordinate.tap()`, press, drag, and swipe for Minecraft.
- Retain before/after screenshots and assert the resulting state with OCR or
  image comparison.

### iPhone Mirroring

Use only for wireless visual observation and keyboard navigation:

- Mirroring requires the iPhone to remain locked.
- Mac clicks arrive as indirect pointer input.
- Minecraft Ore UI ignores those pointer events.
- Tab, arrow keys, and Return work for some Minecraft screens.
- Mirroring and the USB automation session must run as separate phases.

Do not introduce Appium until XCTest lacks a required capability. Appium's
XCUITest driver still uses WebDriverAgent/XCTest gesture synthesis and adds
another runner and server to maintain.

## Proven coordinate-touch baseline

Run:

```sh
scripts/minecraft-coordinate-touch.sh
```

The runner:

1. Finds the connected physical iPhone, including waking a paired CoreDevice
   tunnel that has not yet changed to `connected`.
2. Cold-launches `com.mojang.minecraftpe`.
3. Waits eight seconds for Minecraft's rendered main menu.
4. Taps Play at normalized application coordinate `(0.500, 0.443)`.
5. Saves before/after screenshots in a timestamped `.xcresult`.
6. Exports the attachments.
7. Uses `scripts/ocr.swift` to require `My World` on the world-list screenshot.

This was verified on an iPhone 16e running iOS 26.6 and Minecraft 26.33.
Evidence is written under `.build/minecraft-coordinate-touch/`.

## Extending Minecraft flows

For each new interaction:

1. Start from a deterministic screen. Prefer a cold launch and a known menu
   over assuming Minecraft preserved its previous state.
2. Capture a screenshot before the gesture.
3. Express coordinates as normalized offsets within `XCUIApplication`, not
   Mac window pixels or device-resolution pixels.
4. Perform exactly one new gesture while calibrating.
5. Capture the result and export the `.xcresult` attachments.
6. Assert visible outcome text with Vision OCR when possible. Use an image
   comparison only when no stable text exists.
7. Add waits around rendered state transitions; `runningForeground` only
   means the process is foregrounded, not that Ore UI finished loading.
8. Re-run the complete flow twice before treating coordinates as calibrated.

Keep coordinates named after semantic targets:

```swift
private let mainMenuPlayButton = CGVector(dx: 0.500, dy: 0.443)

minecraft
    .coordinate(withNormalizedOffset: mainMenuPlayButton)
    .tap()
```

## Orientation calibration

Minecraft reports `Landscape Right`, but XCTest screenshots may be exported as
portrait pixel buffers containing rotated game content. Do not copy coordinates
directly from an exported PNG without accounting for that rotation.

During initial calibration, `(0.500, 0.558)` visibly opened Settings.
Correcting the landscape-normalized vertical coordinate to `0.443` tapped Play.
Use observed hit results to refine coordinates after Minecraft UI updates.

## Known failure modes

- `Timed out while enabling automation mode`: the iPhone is locked or waiting
  for its passcode. Enter the passcode, wait for the wired tunnel, and rerun.
- `No connected physical iPhones found`: CoreDevice may briefly report the
  unlocked wired phone as only paired. The coordinate runner performs a detail
  query and retries this transition.
- Tap occurs during loading: `XCUIApplication.launch()` terminates and
  cold-launches Minecraft. Wait for the rendered target before tapping.
- Test passes but UI did not change: gesture synthesis alone is not an
  assertion. Require OCR or image evidence from the post-gesture screenshot.
- Coordinates open an adjacent control: verify orientation mapping and
  recalibrate from the actual before/after screenshots.

## Building end-to-end feature acceptance

Keep artifact generation and Minecraft acceptance conceptually separate:

1. Exercise Craftberry with deterministic fake generation or build a fixture.
2. Import the `.mcaddon` through the existing Safari/Files XCUITest flow.
3. Keep the phone unlocked and under USB XCTest control.
4. Continue in Minecraft using coordinate gestures.
5. Verify pack activation, world load, inventory presence, rendering, crafting,
   combat, or durability with the smallest stable combination of OCR and image
   assertions.

Mirroring remains an optional observation or keyboard-control phase. It is not
the touch transport for Minecraft.

A successful coordinate-navigation test proves the automation transport works;
it does not by itself mark a Bedrock feature as device-verified. Update
`CAPABILITIES.md` only after the generated artifact itself passes the relevant
in-game acceptance checks.

## Deleting test worlds and installed packs after a test (cleanup)

Confirmed live on iPhone 16e / Minecraft 26.33:

- Prefer direct AFC cleanup over Minecraft's Storage UI.
- The `craftberry test` world is **reused** across runs. The first E2E run
  creates it (Creative + Cheats + seed `12345678`) and subsequent runs skip
  creation and reuse the existing world. Inside the run the harness also
  clears the player inventory (`/clear @s`) and dropped items (`/kill
  @e[type=item]`) so the hotbar starts empty even though the world persists.
- After every E2E or calibration run the host script cleans **only the packs
  and their world references**: `scripts/minecraft-cleanup.sh clean --yes`
  resets `world_behavior_packs.json` / `world_resource_packs.json` to `[]` and
  removes every `behavior_packs/` / `resource_packs/` folder whose manifest
  description is exactly `Generated by Craftberry`. The `craftberry test`
  world directory is left in place. `--keep-world` is an explicit alias for
  this default.
- Pass `--delete-world` only for manual recovery or a forced fresh world:
  `scripts/minecraft-cleanup.sh clean --delete-world --yes` or
  `scripts/ios-device.sh minecraft-e2e redstone --fresh-world` /
  `scripts/minecraft-calibrate.sh stop --delete-world`. The runner maps
  `--fresh-world` to the same `--delete-world` path (terminating Minecraft
  first). `scripts/ios-device.sh minecraft-e2e-all [--fresh-world]` loops all
  four scenarios with a single world and pack-only cleanup between each.
- `scripts/ios-device.sh` and `scripts/minecraft-calibrate.sh` now probe AFC
  (`minecraft-cleanup.sh status`) **before** `xcodebuild` to set
  `CRAFTBERRY_E2E_REUSE_WORLD` / `MINECRAFT_CALIBRATION_REUSE_WORLD`. Inside
  `MinecraftE2EHarness` the world list (`Open the world list` + 8s wait) always
  runs, then creation is skipped when that env flag is `1` or when OCR sees
  `craftberry test` on the world list screen.
- Minecraft must be fully quit before AFC cleanup reads its Documents tree.
  `MinecraftDeviceE2EUITests` terminates Minecraft in teardown, and
  `scripts/ios-device.sh minecraft-e2e [redstone|emerald]` runs pack-only
  cleanup after `xcodebuild test` returns.
- The cleanup script never touches a pack without the exact Craftberry marker,
  and never deletes the world directory unless `clean` is run with both
  `--delete-world` and `--yes`. Set `CRAFTBERRY_CLEANUP_WORLD_NAME` to
  override that target.
- Use `scripts/minecraft-cleanup.sh status` before manual cleanup when
  diagnosing a device. It is read-only and reports the world directory,
  installed Craftberry-generated packs, and any active references from the
  configured cleanup world.

## Interactive calibration: the LLDB debugger console

`MinecraftDeviceE2EUITests` and `MinecraftE2EHarness` execute every step
through `MinecraftStepExecutor`, which runs gestures/keyboard input/chat
commands/OCR/pixel checks against Minecraft and returns a
`MinecraftStepResult` instead of failing the test itself. Around each step,
`MinecraftE2EHarness` calls `MinecraftDebuggerConsole.beforeStep`/`afterStep`,
which hit `@inline(never)` checkpoint methods — this is this harness's
`binding.irb`: a place to stop mid-run and drive Minecraft from the debugger
rather than only diagnosing from a completed run's screenshots afterward.

### Breaking into a run

1. Run the target scenario through Xcode (or `xcodebuild test`) with the
   iPhone connected over USB, same as any other `MinecraftDeviceE2EUITests`
   run.
2. Set an Xcode breakpoint on `MinecraftDebuggerConsole.beforeStepCheckpoint`
   (before a step runs) or `.afterStepCheckpoint` (after it ran, whether
   automatically or manually). Both are private methods, so add the
   breakpoint by symbol name (`Debug > Breakpoints > Symbolic Breakpoint...`)
   rather than clicking a gutter.
3. When the breakpoint hits, the run is paused mid-test with Minecraft in
   whatever state it was just in. Use the LLDB console (Xcode's Debug Area)
   to inspect and act.

### Commands, from LLDB's `expr` prompt

`MinecraftDebuggerConsole.current` holds the console for the run currently
paused at a checkpoint:

```
(lldb) expr MinecraftDebuggerConsole.current?.currentStep
(lldb) expr MinecraftDebuggerConsole.current?.recognizedText()
(lldb) expr MinecraftDebuggerConsole.current?.screenshot()
(lldb) expr MinecraftDebuggerConsole.current?.tap(0.5, 0.443)
(lldb) expr MinecraftDebuggerConsole.current?.drag(0.5, 0.8, 0.5, 0.3)
(lldb) expr MinecraftDebuggerConsole.current?.swipeUp()
(lldb) expr MinecraftDebuggerConsole.current?.keyboardText("emerald")
(lldb) expr MinecraftDebuggerConsole.current?.numericKeyboardText("100")
(lldb) expr MinecraftDebuggerConsole.current?.chatCommand("/tp @s 1 2 3")
(lldb) expr MinecraftDebuggerConsole.current?.wait(2)
(lldb) expr MinecraftDebuggerConsole.current?.runCurrentStep()
(lldb) expr MinecraftDebuggerConsole.current?.skipCurrentStep()
(lldb) continue
```

- `tap`/`drag`/`swipeUp`/`keyboardText`/`numericKeyboardText`/`chatCommand`
  are ad hoc: they run through the same `MinecraftStepExecutor` as planned
  steps, but never mark `currentStep` as executed — use them to explore or
  nudge past a stuck screen without disturbing the plan.
- `runCurrentStep()` runs the step the harness is paused on. Once run, `continue`
  will not run it again — `beforeStep` sees `isCurrentStepExecuted` and skips
  straight to the next step.
- `skipCurrentStep()` marks the current step done without running it (useful
  when you've already gotten Minecraft into the step's target state by hand).
- `screenshot()` attaches to the Xcode test report (visible after the run
  ends or via the live Test navigator) since the on-device process has no
  direct path back to files on the Mac.

### When to reach for this vs. the plain XCTest run

Use the debugger console when calibrating new steps or diagnosing a step that
fails inconsistently — anywhere you'd otherwise be guessing from a completed
run's attached screenshots. For scenarios that are already calibrated, run
the plain `xcodebuild test` path with no breakpoints; the harness behaves
identically either way.

## Interactive calibration: the agent JSON controller

The same plan that backs the LLDB console is also exposed to an agent on the
Mac through a resumable USB-only JSON controller. It shares the automatic
Craftberry generation/export/import and post-import cold launch, then waits
indefinitely for controller commands instead of auto-running the steps.

### Architecture

- `MinecraftCalibrationUITests` has one test per scenario (emerald, redstone
  tools/weapons/armor). Each performs the deterministic Craftberry export/import,
  cold-launches Minecraft, then starts a `Network.framework` `NWListener` on
  device port `8765`.
- `scripts/minecraft-calibrate.sh` exposes that port on the Mac as
  `127.0.0.1:8765` via `iproxy 8765:8765` (`-u <UDID>` when `DEVICE_ID` is set)
  and speaks one newline-delimited JSON request per TCP connection.
- Every response echoes the run's state: `success`/`error`, `scenario`,
  `phase`, `cursor` (e.g. `config:12`), `completedCount`/`totalCount`,
  `currentStep`/`nextStep`, `lastResult`, and for bulk queries `steps`.
  `observe` additionally returns a base64 PNG (`screenshotBase64`) and, with
  `--ocr`, Vision OCR text (`recognizedText`).
- `MinecraftCalibrationController` owns the cursor. It advances only on
  successful `step`/`run-until`; failed planned steps retain the cursor so the
  operator can retry or inspect. `select-step` moves only the cursor and
  explicitly does not restore Minecraft UI state. Arbitrary actions
  (`tap`/`drag`/`swipe-up`/`keyboard-text`/`numeric-keyboard-text`/`chat-command`/`wait`)
  never advance the cursor, even on success.

### CLI lifecycle

```sh
# Start a session (emerald, redstone, weapon, or armor)
scripts/minecraft-calibrate.sh start emerald --break-at config:12
scripts/minecraft-calibrate.sh start redstone

# Inspect the run
scripts/minecraft-calibrate.sh status
scripts/minecraft-calibrate.sh list-steps
scripts/minecraft-calibrate.sh observe --ocr   # screenshot + OCR, saved under .build/minecraft-calibration/screenshots/

# Drive the plan
scripts/minecraft-calibrate.sh step
scripts/minecraft-calibrate.sh run-until crafting:4    # stops before crafting:4, stops immediately on failure
scripts/minecraft-calibrate.sh mark-complete            # skip current step without running it
scripts/minecraft-calibrate.sh select-step config:3     # move cursor only

# Ad hoc probing (never advances cursor)
scripts/minecraft-calibrate.sh tap 0.5 0.443
scripts/minecraft-calibrate.sh drag 0.5 0.8 0.5 0.3
scripts/minecraft-calibrate.sh swipe-up
scripts/minecraft-calibrate.sh keyboard-text emerald
scripts/minecraft-calibrate.sh numeric-keyboard-text 12345678
scripts/minecraft-calibrate.sh chat-command "/tp @s 100 80 95"
scripts/minecraft-calibrate.sh wait 2

# End the session
scripts/minecraft-calibrate.sh stop              # terminates Minecraft + runs AFC cleanup
scripts/minecraft-calibrate.sh stop --keep-state # leaves Minecraft, packs, and world untouched
```

`run-until` stops before its target and does not execute it; use `step`
afterward to run the target itself. `select-step` takes either a stable id
(`config:12`, `crafting:4`) or a human-readable step name.

### Session tracking, reconnect, and cleanup

- The script runs `xcodebuild` and `iproxy` as tracked background processes and
  records `session.json`, `xcodebuild.log`, `iproxy.log`, a command
  `transcript.log`, per-command result bundles, and decoded screenshots under
  `.build/minecraft-calibration/`.
- A second `start` while a session is active is refused with an actionable
  error and the existing session's `session.json` is printed. The same
  `stop`/`status`/`observe` commands work across agent turns (i.e. after the
  `start` shell has exited) because they reconnect to `127.0.0.1:8765`.
- `stop` (default) terminates Minecraft on the device and runs
  `scripts/minecraft-cleanup.sh clean --delete-world --yes` after the XCTest
  teardown has quit Minecraft, so AFC can read the Documents tree. With
  `--keep-state` it leaves Minecraft, the installed packs, and the world in
  place for manual inspection.
- Malformed JSON, an unknown command, a stale session (xcodebuild already
  exited), a port conflict on `8765`, a device disconnect, or an unexpected
  XCTest exit each return a `{"success":false,"error":...}` JSON and preserve
  logs. A stale `session.json` whose pids are no longer alive is treated as
  stale and allows a new `start`.

### Pause / human handoff / resume

The controller does not impose timed pauses. To hand off to a human mid-run:

1. Leave the session idle. Physical interaction on the device remains possible
   while the controller is waiting — the listener is passive, not a blocking
   modal.
2. Let the human inspect or poke Minecraft directly on the device.
3. Resume from the agent via `status`, `observe`, `step`, or `run-until`
   without restarting the session.

To resume an agent session after a human turn that manually advanced Minecraft,
use `mark-complete` (if the human already achieved the current step's target
state) or `select-step` to re-align the cursor; `select-step` will not attempt
to undo the human's work.

### Prerequisites and troubleshooting

- Same prerequisites as the LLDB console: unlocked physical iPhone over USB,
  Developer Mode, Minecraft installed, valid signing, `jq`/`python3`/`iproxy`
  on PATH.
- One calibration session and one physical iPhone at a time. The fixed device
  port `8765` is acceptable because the host side binds only to `127.0.0.1`
  and the listener exists only during the calibration UI test.
- No API key is required; the calibration tests use the deterministic
  `--ui-testing` fixtures, same as the plain E2E tests.
- If `status` reports `could not reach calibration controller`, check
  `.build/minecraft-calibration/xcodebuild.log` and `iproxy.log`. A common
  cause is that Craftberry export/import is still running — the controller
  only listens after the post-import cold launch.
- Keep rotation lock on; the same orientation note as the LLDB console
  applies.
- If `start` reports `127.0.0.1:8765 is already in use`, stop the existing
  session or free the port before starting another.

## Deleting a downloaded file from Files (cleanup)

Confirmed live: a file downloaded via Safari into Files' Downloads location
shows **Remove Download** in its long-press context menu, not the generic
**Delete** — Delete is Files' destructive action for files it owns outright,
while a Downloads entry is a placeholder over the Safari download. Check for
"Remove Download" first; fall back to "Delete" for other file locations.
