import XCTest

/// Interactive coordinate-calibration entry point for the brewing gameplay scenario.
final class MinecraftBrewingCalibrationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCalibrationBrewingGameplay() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Brewing calibration requires Minecraft on the dedicated physical iPhone.")
        #else
        let breakAt = ProcessInfo.processInfo.environment["MINECRAFT_CALIBRATION_BREAK_AT"]
        try MinecraftCalibrationHarness(testCase: self).runPreconfiguredWorldCalibration(
            .craftberryBrewingVerification,
            gameMode: .creative,
            breakAt: breakAt
        )
        #endif
    }
}
