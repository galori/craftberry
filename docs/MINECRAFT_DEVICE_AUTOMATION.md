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

- From a running world, the pause/menu icon sits at normalized `(0.5325,
  0.035)`. **Save & Quit** at `(0.301, 0.7035)` returns to the world list.
  Back out to the main menu, open **Settings**, scroll its sidebar, and open
  **Storage**.
- Storage can permanently delete worlds, Resource Packs, and Behavior Packs.
  Expand each category with its far-right disclosure arrow; tapping the
  header center merely selects it and is not a reliable expand action.
- Locate destructive targets by an explicit test-only OCR substring. A unique
  world uses `craftberry test`; generated pack cleanup uses
  `Emerald Test Sword Res` and `Emerald Test Sword Beh`. Never delete an
  unlabeled row or guess when OCR cannot find the intended target.
- Selecting a row reveals a centered action bar whose trash column is stable
  at `x ≈ 0.468`, but its Y position changes with scrolling and Storage's
  post-deletion reflow. Do not derive trash Y from the selected row with a
  fixed offset. `StorageTrashControlLocator` detects the light trash tile
  bracketed by dark action-bar cells in the post-selection screenshot.
- Tapping trash opens **Delete 1 item permanently?**; **Delete** is at
  `(0.5, 0.635)` in the calibrated landscape layout. After confirmation,
  require the matching visible OCR-row count to decrease before recording a
  successful deletion or continuing a delete-all loop.
- Deleting the world first removes active-pack references. Resource Packs can
  then be deleted before Behavior Packs without triggering the required-
  dependency guard. Each deletion can move the following category below the
  fold, so scroll again after every category reflow.
- Cleanup is teardown hygiene, not the acceptance signal. Unexpected Storage
  state is logged with retained screenshots and must not mask a successful
  crafting assertion or replace its original failure.

## Deleting a downloaded file from Files (cleanup)

Confirmed live: a file downloaded via Safari into Files' Downloads location
shows **Remove Download** in its long-press context menu, not the generic
**Delete** — Delete is Files' destructive action for files it owns outright,
while a Downloads entry is a placeholder over the Safari download. Check for
"Remove Download" first; fall back to "Delete" for other file locations.
