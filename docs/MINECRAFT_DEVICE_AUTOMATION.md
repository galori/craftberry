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

## Deactivating a pack after a test (cleanup)

Confirmed live on iPhone 16e / Minecraft 26.33:

- From a running world, the pause/menu icon sits at normalized `(0.5325,
  0.035)` (top-right cluster of three HUD icons). Tapping it opens the
  pause menu; **Save & Quit** is at `(0.301, 0.7035)` and returns directly
  to the world list (not the main menu).
- In **Edit World → Behavior Packs**, the Active tab's row layout is
  identical to the Available tab's: each row has a **Remove** control at
  the same fixed column, `x ≈ 0.94`. The first (topmost) row is reliably
  whichever pack was most recently activated — confirmed by activating a
  pack and immediately observing it at rank 1 — so removing rank 1 right
  after your own test activates a pack is safe without needing to read the
  pack's name.
- Removing a pack that has ever been active in a "previously played" world
  raises a **"Hold on!"** confirmation with two buttons: **Copy and
  continue** (green, makes a world backup first) and **Just continue**
  (white, at `(0.5, 0.704)` in this layout). Use **Just continue** for a
  disposable test world.
- **Resource Packs** does *not* insert newly auto-activated dependency
  packs at a predictable rank — confirmed live: an old "Azure Resources"
  and "Mirror Test … Resources" sat at ranks 1–2 while multiple
  "Emerald Test Sword Resources" duplicates (one per prior test run) were
  scattered at ranks 3, 5, and 6. Don't assume rank 1 (or any fixed rank)
  here. Instead, locate the target row by recognized text: take a
  screenshot, run Vision OCR, and only act if the target string appears in
  exactly one `VNRecognizedTextObservation` — its `boundingBox` gives the
  row's normalized center (`1 - (origin.y + height/2)` converts Vision's
  bottom-left-origin box to `XCUICoordinate`'s top-left-origin offset), and
  the Remove column is the same fixed `x` as Behavior Packs. Treat zero or
  multiple matches as "skip, don't guess" — this uniqueness check is scoped
  to whatever is currently scrolled into view, not the whole underlying
  list, so it only becomes reliably effective at removing *this run's*
  pack once any pre-existing duplicates of the same name are cleared once
  by hand.
- Removing a resource pack still depended on by an *active* behavior pack
  shows a different, single-button **"Required dependency"** dialog
  ("This pack is required by another pack that is applied, so it can't be
  removed" / **Go back**) instead of the "Hold on!" confirmation — confirmed
  live when attempting to remove a resource pack whose behavior pack was
  never deactivated. This is Minecraft's own safety net: even if the
  OCR-uniqueness check above picks a stale entry instead of the intended
  one, removal is refused rather than breaking a pack still in use.
- No control was found to fully delete a pack from Minecraft's installed
  library (as opposed to deactivating it for one world) after checking the
  Available tab and the pack row's own controls. Treat this as unsolved,
  not merely unautomated — fully uninstalling remains a manual step.

## Deleting a downloaded file from Files (cleanup)

Confirmed live: a file downloaded via Safari into Files' Downloads location
shows **Remove Download** in its long-press context menu, not the generic
**Delete** — Delete is Files' destructive action for files it owns outright,
while a Downloads entry is a placeholder over the Safari download. Check for
"Remove Download" first; fall back to "Delete" for other file locations.
