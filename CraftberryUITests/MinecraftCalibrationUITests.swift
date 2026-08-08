import XCTest

/// Interactive calibration entry points for `scripts/minecraft-calibrate.sh`.
///
/// Each test performs the automatic Craftberry export/import and Minecraft
/// cold launch, then starts a `Network.framework` TCP listener on device port
/// 8765 and waits indefinitely for JSON controller commands from the Mac via
/// `iproxy`. This mirrors `MinecraftDeviceE2EUITests` fixtures but never
/// auto-runs the steps — the agent (or human via the CLI) drives them
/// turn-by-turn.
///
/// One calibration session and one physical iPhone are supported at a time; the
/// fixed device port is acceptable because the host side binds only to
/// localhost and the listener exists only during the calibration UI test.
final class MinecraftCalibrationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCalibrationEmeraldSword() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Calibration requires Minecraft on the dedicated physical iPhone.")
        #else
        let breakAt = ProcessInfo.processInfo.environment["MINECRAFT_CALIBRATION_BREAK_AT"]
        try MinecraftCalibrationHarness(testCase: self).runCalibration(.emeraldSword, breakAt: breakAt)
        #endif
    }

    func testCalibrationRedstoneToolSet() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Calibration requires Minecraft on the dedicated physical iPhone.")
        #else
        let breakAt = ProcessInfo.processInfo.environment["MINECRAFT_CALIBRATION_BREAK_AT"]
        try MinecraftCalibrationHarness(testCase: self).runCalibration(.redstoneToolSet, breakAt: breakAt)
        #endif
    }

    func testCalibrationRedstoneWeaponSet() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Calibration requires Minecraft on the dedicated physical iPhone.")
        #else
        let breakAt = ProcessInfo.processInfo.environment["MINECRAFT_CALIBRATION_BREAK_AT"]
        try MinecraftCalibrationHarness(testCase: self).runCalibration(.redstoneWeaponSet, breakAt: breakAt)
        #endif
    }

    func testCalibrationRedstoneArmorSet() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Calibration requires Minecraft on the dedicated physical iPhone.")
        #else
        let breakAt = ProcessInfo.processInfo.environment["MINECRAFT_CALIBRATION_BREAK_AT"]
        try MinecraftCalibrationHarness(testCase: self).runCalibration(.redstoneArmorSet, breakAt: breakAt)
        #endif
    }
}
