import Foundation

/// Partitioning of the flat `MinecraftDeviceE2EConfig.json` step list into
/// reusable-world slices.
///
/// The JSON itself stays a single flat array so calibrated coordinates keep
/// working. Slicing is derived from sentinel step names so a reordering in the
/// JSON fails loudly (the slice init throws) rather than silently skipping
/// wrong steps.
///
/// Layout (as of 2026-08-09, 70 steps):
/// - `prefix` (0..<2): "Open the world list..." + "Wait for the world list to finish rendering"
///   — always runs, needed to reach the world list for OCR detection.
/// - `creation` (2..<35): "Tap Create new world" … "Wait for the world list" (after Save & Quit)
///   — skipped when the `craftberry test` world already exists.
/// - `activation` (35..<63): "Open the craftberry test world edit screen" … "Wait for the craftberry test world to finish loading"
///   — always runs (activates the freshly-imported packs).
/// - `staging` (63..<end): "Teleport ..." … "Confirm the crafting table interface is open"
///   — always runs, idempotent staging for the crafting plan.
///
/// Changing the shape of the JSON without updating sentinels is a hard error.
struct MinecraftE2EStepSlices {
    let prefix: [MinecraftStep]
    let creation: [MinecraftStep]
    let activation: [MinecraftStep]
    let staging: [MinecraftStep]

    static let prefixEndSentinel = "Wait for the world list to finish rendering"
    static let creationEndSentinel = "Wait for the world list"
    static let activationEndSentinel = "Wait for the craftberry test world to finish loading"

    // `creationEndSentinel` ("Wait for the world list") is distinct from
    // `prefixEndSentinel` ("Wait for the world list to finish rendering").
    // The short name only appears once — after "Save and quit to the world list".
    static func make(from steps: [MinecraftStep]) throws -> MinecraftE2EStepSlices {
        guard let prefixEnd = steps.firstIndex(where: { $0.name == prefixEndSentinel }) else {
            throw MinecraftE2EError.missingResource
        }
        guard let creationEnd = steps.firstIndex(where: { $0.name == creationEndSentinel }) else {
            throw MinecraftE2EError.missingResource
        }
        guard let activationEnd = steps.firstIndex(where: { $0.name == activationEndSentinel }) else {
            throw MinecraftE2EError.missingResource
        }
        // prefixEnd < creationEnd < activationEnd must hold; otherwise the JSON was reordered.
        guard prefixEnd < creationEnd, creationEnd < activationEnd else {
            throw MinecraftE2EError.missingResource
        }

        let prefix = Array(steps[0...prefixEnd])
        let creation = Array(steps[(prefixEnd + 1)...creationEnd])
        let activation = Array(steps[(creationEnd + 1)...activationEnd])
        let staging = Array(steps[(activationEnd + 1)..<steps.count])

        // Structural sanity: staging must end at the crafting-table boundary.
        guard let last = staging.last, last.name == "Confirm the crafting table interface is open" else {
            throw MinecraftE2EError.missingResource
        }

        return MinecraftE2EStepSlices(prefix: prefix, creation: creation, activation: activation, staging: staging)
    }

    /// Ordered config steps for a run, given whether the world already exists.
    func configSteps(reusingWorld: Bool) -> [MinecraftStep] {
        if reusingWorld {
            return prefix + activation + staging
        } else {
            return prefix + creation + activation + staging
        }
    }

    /// Chat-command steps that leave the world clean for the next run.
    /// Run after crafting verification, before Minecraft is terminated so the
    /// next scenario starts with an empty inventory. The `crafting_table` left
    /// at 98 80 95 is intentionally preserved — `/setblock crafting_table` is
    /// idempotent and the next run re-places it anyway.
    static var postScenarioCleanup: [MinecraftStep] {
        [
            MinecraftStep(name: "Clear player inventory for next scenario", action: .chatCommand("/clear @s")),
            MinecraftStep(name: "Wait after clearing inventory", action: .wait(seconds: 2)),
            MinecraftStep(name: "Clear crafting table for next scenario", action: .chatCommand("/setblock 98 80 95 air")),
            MinecraftStep(name: "Wait after clearing crafting table", action: .wait(seconds: 1)),
            MinecraftStep(name: "Replace crafting table for next scenario", action: .chatCommand("/setblock 98 80 95 crafting_table")),
            MinecraftStep(name: "Wait after replacing crafting table", action: .wait(seconds: 1))
        ]
    }
}



/// Host-side hint that the `craftberry test` world already exists, set by
/// `scripts/ios-device.sh` / `scripts/minecraft-calibrate.sh` via the
/// environment after an AFC `status` probe. Also readable inside XCTest via
/// `ProcessInfo.processInfo.environment`.
enum MinecraftWorldReuseFlag {
    static let environmentKey = "CRAFTBERRY_E2E_REUSE_WORLD"
    static let calibrationEnvironmentKey = "MINECRAFT_CALIBRATION_REUSE_WORLD"

    static func shouldReuseWorld() -> Bool {
        let env = ProcessInfo.processInfo.environment
        let raw = env[environmentKey] ?? env[calibrationEnvironmentKey]
        return raw == "1" || raw?.lowercased() == "true" || raw == "YES"
    }
}

extension MinecraftE2EConfiguration {
    func slices() throws -> MinecraftE2EStepSlices {
        try MinecraftE2EStepSlices.make(from: steps)
    }
}
