# Craftberry

Craftberry is an iOS proof of concept for compiling one Minecraft Bedrock custom sword from a natural-language prompt into a valid `.mcaddon` build artifact.

## Run locally

1. Install full Xcode, then open `Craftberry.xcodeproj`.
2. Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` and set `OPENAI_API_KEY` for a Debug-only personal build. This key is compiled into the app: never commit, archive, TestFlight, or distribute it.
3. Select an iOS Simulator and run the `Craftberry` scheme; no development team or Minecraft installation is needed for the initial workflow.
4. Generate a sword and tap **Build .mcaddon**. Export the artifact through the share sheet or save it to Files. Transfer it to a physical iPhone later for Minecraft validation.

## Validate

```sh
xcodebuild -scheme Craftberry -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
xcodebuild -scheme Craftberry -destination 'generic/platform=iOS' build
```

The core is also exposed as the `CraftberryCore` Swift package target for isolated compiler tests. See [PLAN.md](PLAN.md) for scope, constraints, and the physical-device Minecraft acceptance test.
