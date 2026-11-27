import XCTest

/// Physical acceptance for furnace recipes and generated furnace fuel.
/// Furnace-panel slot taps were measured from the iPhone 13 Pro calibration screenshot.
final class MinecraftFurnaceFuelE2ETests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testRedstoneFurnaceRecipeSmeltsInputToGeneratedIngot() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        let scenario = MinecraftFurnaceE2EScenarioFactory.redstoneFurnaceSmelt(layout: furnaceLayout)
        try MinecraftE2EHarness(testCase: self).runPreconfiguredWorld(scenario, gameMode: .survival)
        #endif
    }

    func testGeneratedFuelSmeltsSandIntoGlass() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        let scenario = MinecraftFurnaceE2EScenarioFactory.generatedFuelSmeltsSand(layout: furnaceLayout)
        try MinecraftE2EHarness(testCase: self).runPreconfiguredWorld(scenario, gameMode: .survival)
        #endif
    }

    private var furnaceLayout: MinecraftFurnaceLayout {
        let calibrated = MinecraftCalibratedLayout()
        return MinecraftFurnaceLayout(
            furnaceBlock: calibrated.reopenCraftingTable,
            inputSlot: MinecraftCoordinate(x: 0.620, y: 0.278),
            fuelSlot: MinecraftCoordinate(x: 0.620, y: 0.526),
            outputSlot: MinecraftCoordinate(x: 0.774, y: 0.402),
            closeButton: MinecraftCoordinate(x: 0.922, y: 0.070),
            inputHotbarSlot: calibrated.hotbarSlot(1),
            fuelHotbarSlot: calibrated.hotbarSlot(2),
            outputHUDHotbarSlot: calibrated.hudHotbarSlot(1)
        )
    }
}
