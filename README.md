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

The core is also exposed as the `CraftberryCore` Swift package target for isolated Swift 6 compiler tests. See [ROADMAP.md](ROADMAP.md) for the active architecture and delivery plan, [CAPABILITIES.md](CAPABILITIES.md) for profile support and verification status, and [PLAN.md](PLAN.md) for the historical sword POC plan.
