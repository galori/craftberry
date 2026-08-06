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

- Prefer direct AFC cleanup over Minecraft's Storage UI. The full E2E runner
  uses `scripts/minecraft-cleanup.sh clean --delete-world --yes` after the
  device XCTest exits.
- Minecraft must be fully quit before AFC cleanup reads its Documents tree.
  `MinecraftDeviceE2EUITests` terminates Minecraft in teardown, and
  `scripts/ios-device.sh minecraft-e2e [redstone|emerald]` runs cleanup after
  `xcodebuild test` returns.
- The cleanup script deletes only behavior/resource packs whose manifest
  description is exactly `Generated by Craftberry`, then deletes the world
  whose `levelname.txt` is `craftberry test` when `--delete-world` is
  supplied. Set `CRAFTBERRY_CLEANUP_WORLD_NAME` to override that target.
- Use `scripts/minecraft-cleanup.sh status` before manual cleanup when
  diagnosing a device. It is read-only and reports the world directory,
  installed Craftberry-generated packs, and any active references from the
  configured cleanup world.

## Deleting a downloaded file from Files (cleanup)

Confirmed live: a file downloaded via Safari into Files' Downloads location
shows **Remove Download** in its long-press context menu, not the generic
**Delete** — Delete is Files' destructive action for files it owns outright,
while a Downloads entry is a placeholder over the Safari download. Check for
"Remove Download" first; fall back to "Delete" for other file locations.
