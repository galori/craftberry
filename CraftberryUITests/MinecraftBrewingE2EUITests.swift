import XCTest

/// Physical-device acceptance for the brewing mix and container recipe outputs.
/// Coordinate-dependent station interactions remain guarded by named calibration stops.
final class MinecraftBrewingE2EUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCraftberryBrewingFixtureBrewsElixirAndConvertsToSplashPotion() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try MinecraftE2EHarness(testCase: self).runPreconfiguredWorld(.craftberryBrewingVerification, gameMode: .creative)
        #endif
    }
}
