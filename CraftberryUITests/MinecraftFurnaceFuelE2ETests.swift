import XCTest

/// Physical acceptance for furnace recipes and generated furnace fuel.
/// Furnace-panel slot taps remain explicitly pending until calibrated on the iPhone 13 Pro.
final class MinecraftFurnaceFuelE2ETests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testRedstoneFurnaceRecipeSmeltsInputToGeneratedIngot() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        let scenario = MinecraftFurnaceE2EScenarioFactory.redstoneFurnaceSmelt(layout: pendingFurnaceLayout)
        try MinecraftE2EHarness(testCase: self).runPreconfiguredWorld(scenario, gameMode: .survival)
        #endif
    }

    func testGeneratedFuelSmeltsSandIntoGlass() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        let scenario = MinecraftFurnaceE2EScenarioFactory.generatedFuelSmeltsSand(layout: pendingFurnaceLayout)
        try MinecraftE2EHarness(testCase: self).runPreconfiguredWorld(scenario, gameMode: .survival)
        #endif
    }

    private var pendingFurnaceLayout: MinecraftFurnaceLayout {
        let calibrated = MinecraftCalibratedLayout()
        return MinecraftFurnaceLayout(
            furnaceBlock: calibrated.reopenCraftingTable,
            inputSlot: nil,
            fuelSlot: nil,
            outputSlot: nil,
            closeButton: nil,
            inputHotbarSlot: nil,
            fuelHotbarSlot: nil,
            outputHUDHotbarSlot: calibrated.hudHotbarSlot(1)
        )
    }
}
