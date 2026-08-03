# Craftberry

Craftberry is an iOS proof of concept for turning a natural-language prompt into a typed, locally validated Minecraft Bedrock add-on project and compiling it into a deterministic `.mcaddon`. The currently shipped vertical slice remains one custom sword; unsupported add-on families fail clearly.

```text
Prompt → typed AddOnProject → local validation and asset generation
→ pinned Bedrock compiler → compilation report → .mcaddon export
```

The model produces semantic intent only. Swift owns identifiers, UUIDs, Bedrock JSON, textures, localization, archive paths, validation, and packaging.

## Run locally

1. Install full Xcode, then open `Craftberry.xcodeproj`.
2. Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` and set `OPENAI_API_KEY` for a Debug-only personal build. This key is compiled into the app: never commit, archive, TestFlight, or distribute it.
3. Select an iOS Simulator and run the `Craftberry` scheme; no development team or Minecraft installation is needed for the initial workflow.
4. Generate the supported sword project and tap **Build .mcaddon**. Export the artifact through the share sheet or save it to Files. Transfer it to a physical iPhone later for Minecraft validation.

## Validate

```sh
xcodebuild -scheme Craftberry -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
xcodebuild -scheme Craftberry -destination 'generic/platform=iOS' build
```

## Physical iPhone workflow

Prerequisites: a paired, trusted, unlocked iPhone with Developer Mode enabled, full Xcode command line tools, `jq`, and the existing development team signing setup. Device workflow output stays under `.build/ios-device`.

```sh
scripts/ios-device.sh list
scripts/ios-device.sh run
scripts/ios-device.sh test
DEVICE_ID=<xcode-device-id> scripts/ios-device.sh test
```

`run` builds a normal Debug app, installs it, and launches it on the selected iPhone. Live generation still needs `Config/Secrets.xcconfig` with `OPENAI_API_KEY`.

`test` runs the deterministic UI smoke test with the internal Debug-only `--ui-testing` launch mode. It does not need an API key, retains a timestamped `.xcresult`, and stops at the iOS share sheet. Importing the exported `.mcaddon` into Minecraft and validating gameplay remains a separate manual device acceptance step.

## Minecraft validation (standalone, not part of Craftberry's own tests)

Two more scripts drive that Minecraft-side validation without exercising Craftberry itself, on the theory that they exercise two fundamentally different control surfaces and so have to run as separate legs:

1. **`scripts/minecraft-import.sh`** — generates a fresh fixture `.mcaddon` on the Mac (via the `MinecraftFixture` Swift package executable; no device involved), serves it over a local HTTP server, and drives **Safari** (not Craftberry) via a new `MinecraftHandoffUITests` XCUITest target to download it and hand it off to Minecraft's "Open in Minecraft" import. Safari is standard UIKit, so this leg uses the same accessibility-identifier-driven XCUITest approach as `scripts/ios-device.sh`. `xcodebuild`'s `TEST_RUNNER_` environment-variable forwarding does not reach the on-device test runner app the way it does the simulator, so the script instead writes the server URL/display name into the tracked `CraftberryUITests/MinecraftImportConfig.json` before each build; expect that file to show as locally modified after a run. **Verified end-to-end on a physical iPhone**: every identifier was calibrated against live accessibility-tree dumps, and it reliably lands in Minecraft's foreground across repeated runs. One residual flake in Safari's address bar (a widely-reported XCUITest/Safari keyboard-focus race, not fixable by better element targeting alone) is absorbed by the script retrying the whole `xcodebuild test` invocation up to 3 times.
2. **`scripts/minecraft-mirror-drive.sh`** — activates the imported pack in a test world and confirms it appears correctly in-game. Minecraft Bedrock's own UI runs on a custom renderer (Coherent Gameface / Ore UI), not UIKit, so it exposes no accessibility tree XCUITest can navigate. This leg instead mirrors the iPhone onto the Mac via macOS's built-in **iPhone Mirroring** feature and drives it with synthetic `System Events` clicks plus screenshot + Vision-framework OCR verification (`scripts/ocr.swift`).

These two legs run sequentially, not concurrently: starting an iPhone Mirroring session locks the phone's own screen, and Xcode/XCUITest cannot talk to a locked device's UI — so leg 1 (device unlocked, driven by Xcode) must finish before leg 2 (device locked, driven by the mirror) begins.

**Manual steps neither script can automate:**
- Starting the iPhone Mirroring session itself — there is no CLI/AppleScript/URL scheme for this; open **iPhone Mirroring.app**, select the device, and authenticate with Face ID/passcode on the phone by hand before running `minecraft-mirror-drive.sh`.
- Calibrating `scripts/minecraft-activation-steps.json` — the exact tap locations for Minecraft's Play/world-settings/pack-activation screens are device- and Minecraft-version-specific and ship as `null` placeholders. Use `scripts/minecraft-mirror-drive.sh screenshot` to capture the live mirrored view, work out each tap as a fraction of the window's width/height, and fill in `x`/`y`; `scripts/minecraft-mirror-drive.sh tap <x> <y>` lets you test one tap at a time.

The core is also exposed as the `CraftberryCore` Swift package target for isolated Swift 6 compiler tests. See [ROADMAP.md](ROADMAP.md) for the active architecture and delivery plan, [CAPABILITIES.md](CAPABILITIES.md) for profile support and verification status, and [PLAN.md](PLAN.md) for the historical sword POC plan.
