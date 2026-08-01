# Craftberry Development Guide

## Workflow

### Required after every change

- Use test-driven development when feasible: add or update a failing test that captures the intended behavior before implementing it, then make it pass. If TDD is not feasible, explain why in the final handoff or PR notes.
- Run the smallest relevant checks while iterating, then run the full unit-test suite before considering a cohesive change complete.
- Keep ordinary validation local and side-effect-free. Builds and tests may write ignored derived data or temporary files, but must not modify Minecraft, iOS device data, Xcode user settings, or external services unless the task explicitly requires it.
- Preserve unrelated or pre-existing worktree changes.
- Make branch, PR, commit, push, or merge changes only when the user has asked for them. Never commit directly to `main`.

### Pull request flow

- Branch from the default branch unless the work explicitly depends on unmerged changes.
- Use a concise PR title and description that state the user-visible change and validation performed.
- Keep secrets, signed artifacts, device logs containing personal data, and generated Bedrock archives out of commits.

## Project Structure

- `Craftberry/` — native iOS app sources, organized by app shell, feature, domain, AI service, and Bedrock packaging responsibility.
- `CraftberryTests/` — deterministic unit tests for the IR, compiler, pixel renderer, archive layout, and service adapters.
- `CraftberryUITests/` — focused user-flow smoke tests for prompt, result, and error states.
- `Config/` — tracked configuration examples only; real local secrets are ignored.
- `PLAN.md` — agreed product and implementation plan for the MVP.

Update this section when the actual Xcode project layout is introduced or materially changed.

## Principles

- **The LLM produces intent, not game files.** Treat the structured intermediate representation as the sole AI boundary; Swift code owns validation and every Bedrock JSON, PNG, UUID, and archive entry.
- **Keep the Bedrock content profile explicit.** Isolate version-specific paths and schemas in the compiler, generate fresh pack identifiers, and test generated archives against the selected Minecraft release on a physical device.
- **Packaging must be deterministic.** Archive contents, manifest dependencies, and generated identifiers should be inspectable and covered by tests. Never silently emit an invalid or partial add-on.
- **Treat the add-on as the product.** The app builds and exports a valid `.mcaddon`; it does not write into Minecraft's sandbox, activate a pack in a world, or depend on Minecraft being installed. Keep device-transfer validation separate from artifact generation.
- **No distributable client secrets.** A direct API key is allowed only in an ignored Debug-only local configuration for this personal POC. Replace it with a backend before TestFlight, sharing, or release.
- **Prefer native, small dependencies.** Use SwiftUI and Apple frameworks first. Add a package only when it removes meaningful complexity and has a focused responsibility.
- **Accessibility is a feature.** Maintain Dynamic Type, VoiceOver labels, sufficient contrast, and useful loading/error states in every user flow.
- **No unlicensed Minecraft assets.** Use original generated pixel art and plain compatibility text; do not copy Mojang logos, textures, or UI assets.

## Testing

- Use XCTest as the default test framework; run focused tests while iterating and the full test target before handoff.
- Unit-test all IR validation and defaults, identifier sanitization, manifest dependency wiring, generated JSON, texture dimensions, and both `.mcpack` and `.mcaddon` archive entries.
- Use fixtures and fake `LLMClient` implementations for deterministic app and UI tests. Keep live API tests opt-in and never require a real key for the normal suite.
- Test generic iOS share behavior on a physical device when changing export code. When the Bedrock compiler or packaging layout changes, separately validate an exported artifact in Minecraft on a physical iPhone; this is compatibility coverage, not an app handoff flow.
- Keep generated test archives in temporary directories and clean them up after each test.

## Local Commands

Once the Xcode project exists, prefer these commands from the repository root (replace the placeholder scheme and simulator as the project is created):

```sh
xcodebuild -list
xcodebuild -scheme Craftberry -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
xcodebuild -scheme Craftberry -destination 'generic/platform=iOS' build
```

Do not run a signed archive, upload, TestFlight distribution, or device installation unless the user explicitly asks.
