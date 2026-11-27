import XCTest

final class MinecraftFurnacePlanCompilerTests: XCTestCase {
    func testFurnacePlanPlacesInputAndFuelBeforeWaitingAndCollectingOutput() throws {
        let layout = MinecraftFurnaceLayout(
            furnaceBlock: MinecraftCoordinate(x: 0.1, y: 0.2),
            inputSlot: MinecraftCoordinate(x: 0.3, y: 0.4),
            fuelSlot: MinecraftCoordinate(x: 0.5, y: 0.6),
            outputSlot: MinecraftCoordinate(x: 0.7, y: 0.8),
            closeButton: MinecraftCoordinate(x: 0.9, y: 0.1),
            inputHotbarSlot: MinecraftCoordinate(x: 0.11, y: 0.22),
            fuelHotbarSlot: MinecraftCoordinate(x: 0.33, y: 0.44),
            outputHUDHotbarSlot: MinecraftCoordinate(x: 0.55, y: 0.66)
        )

        let steps = MinecraftFurnacePlanCompiler(layout: layout).smelt(
            inputName: "sand",
            fuelName: "Redstone Fuel",
            expectedOutputName: "Glass"
        )
        let outputSlot = try XCTUnwrap(layout.outputSlot)
        let hudSlot = layout.outputHUDHotbarSlot

        XCTAssertEqual(steps.count, 15)
        XCTAssertEqual(steps[0].action, .tap(x: 0.1, y: 0.2))
        XCTAssertEqual(steps[2].action, .assertText("Furnace"))
        XCTAssertEqual(steps[3].action, .tap(x: 0.11, y: 0.22))
        XCTAssertEqual(steps[4].action, .tap(x: 0.3, y: 0.4))
        XCTAssertEqual(steps[5].action, .tap(x: 0.33, y: 0.44))
        XCTAssertEqual(steps[6].action, .tap(x: 0.5, y: 0.6))
        XCTAssertEqual(steps[7].action, .wait(seconds: 12))
        XCTAssertEqual(steps[8].action, .assertText("Glass"))
        XCTAssertEqual(steps[9].action, .tap(x: 0.7, y: 0.8))
        XCTAssertEqual(steps[10].action, .wait(seconds: 2))
        XCTAssertEqual(
            steps[11].action,
            .assertPixels(.itemContrastAbsent(
                xRange: (outputSlot.x - 0.018)...(outputSlot.x + 0.018),
                yRange: (outputSlot.y - 0.034)...(outputSlot.y + 0.034),
                maximumCount: 2
            ))
        )
        XCTAssertEqual(
            steps[12].action,
            .assertPixels(.itemContrastCluster(
                xRange: (hudSlot.x - 0.02)...(hudSlot.x + 0.02),
                yRange: (hudSlot.y - 0.025)...(hudSlot.y + 0.05),
                minimumCount: 20
            ))
        )
        XCTAssertEqual(steps[13].action, .tap(x: 0.9, y: 0.1))
        XCTAssertFalse(steps.suffix(from: 9).contains { $0.action == .assertText("Glass") })
    }

    func testFurnacePlanStopsAtExplicitCalibrationRequirementWhenSlotsAreUnknown() {
        let layout = MinecraftFurnaceLayout(
            furnaceBlock: MinecraftCoordinate(x: 0.1, y: 0.2),
            inputSlot: nil,
            fuelSlot: nil,
            outputSlot: nil,
            closeButton: nil,
            inputHotbarSlot: nil,
            fuelHotbarSlot: nil,
            outputHUDHotbarSlot: MinecraftCoordinate(x: 0.55, y: 0.66)
        )

        let steps = MinecraftFurnacePlanCompiler(layout: layout).smelt(
            inputName: "sand",
            fuelName: "Redstone Fuel",
            expectedOutputName: "Glass"
        )

        XCTAssertEqual(steps.count, 4)
        XCTAssertEqual(steps[0].action, .tap(x: 0.1, y: 0.2))
        XCTAssertEqual(steps[2].action, .assertText("Furnace"))
        guard case .calibrationRequired(let reason) = steps[3].action else {
            return XCTFail("Missing furnace slot coordinates must stop at an explicit calibration step.")
        }
        XCTAssertTrue(reason.contains("furnace input"))
        XCTAssertTrue(reason.contains("furnace fuel"))
        XCTAssertTrue(reason.contains("furnace output"))
    }

    func testFurnaceScenarioSetsUpGeneratedIngotRecipeWithVanillaFuel() throws {
        let scenario = MinecraftFurnaceE2EScenarioFactory.redstoneFurnaceSmelt(layout: testLayout)
        let commands = scenario.postCraftingSteps.compactMap { step -> String? in
            guard case .chatCommand(let command) = step.action else { return nil }
            return command
        }

        XCTAssertEqual(scenario.launchArgument, "--ui-testing-redstone-furnace-set")
        XCTAssertEqual(scenario.expectedCraftedItemName, "Redstone Ingot")
        XCTAssertEqual(commands, [
            "/setblock 98 80 95 furnace",
            "/give @s redstone",
            "/give @s coal"
        ])
        XCTAssertTrue(scenario.postCraftingSteps.contains { $0.action == .assertText("Furnace") })
        let waitForOutput = try XCTUnwrap(scenario.postCraftingSteps.firstIndex { $0.name == "Wait for Redstone Ingot to smelt" })
        XCTAssertEqual(scenario.postCraftingSteps[waitForOutput + 1].action, .assertText("Redstone Ingot"))
        XCTAssertFalse(scenario.postCraftingSteps.suffix(from: waitForOutput + 2).contains { $0.action == .assertText("Redstone Ingot") })
        XCTAssertTrue(scenario.postCraftingSteps.contains { $0.name == "Confirm furnace output slot is empty" })
        XCTAssertTrue(scenario.postCraftingSteps.contains { $0.name == "Confirm collected Redstone Ingot in the HUD hotbar" })
        XCTAssertFalse(scenario.postCraftingSteps.contains { $0.name == "Wait for Redstone Ingot tooltip" })
    }

    func testFuelScenarioUsesStableGeneratedFuelAndChecksSmeltedGlass() {
        let scenario = MinecraftFurnaceE2EScenarioFactory.generatedFuelSmeltsSand(layout: testLayout)
        let commands = scenario.postCraftingSteps.compactMap { step -> String? in
            guard case .chatCommand(let command) = step.action else { return nil }
            return command
        }

        XCTAssertEqual(scenario.launchArgument, "--ui-testing-redstone-consumable-set")
        XCTAssertEqual(scenario.additionalLaunchArguments, ["--ui-testing-stable-fuel-identifier"])
        XCTAssertEqual(scenario.expectedCraftedItemName, "Glass")
        XCTAssertTrue(commands.contains("/give @s craftberry:redstone_fueltest_fuel"))
        XCTAssertTrue(commands.contains("/clear @s craftberry:redstone_fueltest_fuel"))
        XCTAssertTrue(scenario.postCraftingSteps.contains { $0.action == .assertText("Furnace") })
        XCTAssertTrue(scenario.postCraftingSteps.contains { $0.action == .assertText("Glass") })
        XCTAssertTrue(scenario.postCraftingSteps.contains { $0.name == "Confirm furnace output slot is empty" })
        XCTAssertTrue(scenario.postCraftingSteps.contains { $0.name == "Confirm collected Glass in the HUD hotbar" })
        XCTAssertFalse(scenario.postCraftingSteps.contains { $0.name == "Wait for Glass tooltip" })
        XCTAssertTrue(scenario.postCraftingSteps.contains { $0.action == .assertText("no items to remove") })
        XCTAssertFalse(scenario.postCraftingSteps.contains { $0.action == .assertText("Removed 0 items") })
    }

    private var testLayout: MinecraftFurnaceLayout {
        MinecraftFurnaceLayout(
            furnaceBlock: MinecraftCoordinate(x: 0.1, y: 0.2),
            inputSlot: MinecraftCoordinate(x: 0.3, y: 0.4),
            fuelSlot: MinecraftCoordinate(x: 0.5, y: 0.6),
            outputSlot: MinecraftCoordinate(x: 0.7, y: 0.8),
            closeButton: MinecraftCoordinate(x: 0.9, y: 0.1),
            inputHotbarSlot: MinecraftCoordinate(x: 0.11, y: 0.22),
            fuelHotbarSlot: MinecraftCoordinate(x: 0.33, y: 0.44),
            outputHUDHotbarSlot: MinecraftCoordinate(x: 0.55, y: 0.66)
        )
    }
}
