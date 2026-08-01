# Craftberry

Craftberry is an iOS proof of concept for creating one Minecraft Bedrock custom sword from a natural-language prompt, then exporting it as an `.mcaddon` on the same iPhone.

## Run locally

1. Install full Xcode, then open `Craftberry.xcodeproj`.
2. Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` and set `OPENAI_API_KEY` for a Debug-only personal build. This key is compiled into the app: never commit, archive, TestFlight, or distribute it.
3. Select a signed personal-development team and run the `Craftberry` scheme on an iPhone running iOS 17 or later.
4. Generate a sword, tap **Create Add-On**, then **Open in Minecraft**. Enable the behavior pack in a world before crafting the sword or using the displayed `/give` command.

## Validate

```sh
xcodebuild -scheme Craftberry -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
xcodebuild -scheme Craftberry -destination 'generic/platform=iOS' build
```

The core is also exposed as the `CraftberryCore` Swift package target for isolated compiler tests. See [PLAN.md](PLAN.md) for scope, constraints, and the physical-device Minecraft acceptance test.
