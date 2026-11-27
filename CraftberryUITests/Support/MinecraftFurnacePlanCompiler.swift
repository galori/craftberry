import Foundation

/// Calibrated coordinates for one furnace interaction. The slot locations are supplied by the
/// physical-device calibration; the compiler keeps the interaction order and assertions stable.
struct MinecraftFurnaceLayout: Equatable {
    let furnaceBlock: MinecraftCoordinate
    let inputSlot: MinecraftCoordinate?
    let fuelSlot: MinecraftCoordinate?
    let outputSlot: MinecraftCoordinate?
    let closeButton: MinecraftCoordinate?
    let inputHotbarSlot: MinecraftCoordinate?
    let fuelHotbarSlot: MinecraftCoordinate?
    let outputHUDHotbarSlot: MinecraftCoordinate
}

struct MinecraftFurnacePlanCompiler {
    var layout: MinecraftFurnaceLayout

    func smelt(
        inputName: String,
        fuelName: String,
        expectedOutputName: String,
        smeltDuration: TimeInterval = 12
    ) -> [MinecraftStep] {
        var steps = [
            .tap("Open furnace", layout.furnaceBlock),
            MinecraftStep(name: "Wait for furnace interface", action: .wait(seconds: 4)),
            MinecraftStep(name: "Confirm furnace interface", action: .assertText("Furnace"))
        ]
        let missingCalibration = [
            layout.inputHotbarSlot == nil ? "input hotbar" : nil,
            layout.inputSlot == nil ? "furnace input" : nil,
            layout.fuelHotbarSlot == nil ? "fuel hotbar" : nil,
            layout.fuelSlot == nil ? "furnace fuel" : nil,
            layout.outputSlot == nil ? "furnace output" : nil,
            layout.closeButton == nil ? "furnace close button" : nil
        ].compactMap { $0 }
        guard missingCalibration.isEmpty,
              let inputHotbarSlot = layout.inputHotbarSlot,
              let inputSlot = layout.inputSlot,
              let fuelHotbarSlot = layout.fuelHotbarSlot,
              let fuelSlot = layout.fuelSlot,
              let outputSlot = layout.outputSlot,
              let closeButton = layout.closeButton else {
            steps.append(MinecraftStep(
                name: "Calibrate furnace panel controls",
                action: .calibrationRequired("Missing calibrated furnace coordinates: \(missingCalibration.joined(separator: ", ")).")
            ))
            return steps
        }
        steps += [
            .tap("Pick \(inputName) from the hotbar", inputHotbarSlot),
            .tap("Place \(inputName) into the furnace input slot", inputSlot),
            .tap("Pick \(fuelName) from the hotbar", fuelHotbarSlot),
            .tap("Place \(fuelName) into the furnace fuel slot", fuelSlot),
            MinecraftStep(name: "Wait for \(expectedOutputName) to smelt", action: .wait(seconds: smeltDuration)),
            MinecraftStep(name: "Confirm furnace produced \(expectedOutputName)", action: .assertText(expectedOutputName)),
            .tap("Collect \(expectedOutputName) from the furnace output slot", outputSlot),
            MinecraftStep(name: "Wait for collected \(expectedOutputName)", action: .wait(seconds: 2)),
            MinecraftStep(
                name: "Confirm furnace output slot is empty",
                action: .assertPixels(.itemContrastAbsent(
                    xRange: (outputSlot.x - 0.018)...(outputSlot.x + 0.018),
                    yRange: (outputSlot.y - 0.034)...(outputSlot.y + 0.034),
                    maximumCount: 2
                ))
            ),
            MinecraftStep(
                name: "Confirm collected \(expectedOutputName) in the HUD hotbar",
                action: .assertPixels(.itemContrastCluster(
                    xRange: (layout.outputHUDHotbarSlot.x - 0.02)...(layout.outputHUDHotbarSlot.x + 0.02),
                    yRange: (layout.outputHUDHotbarSlot.y - 0.025)...(layout.outputHUDHotbarSlot.y + 0.05),
                    minimumCount: 20
                ))
            ),
            .tap("Close furnace interface", closeButton),
            MinecraftStep(name: "Wait for the world HUD", action: .wait(seconds: 2))
        ]
        return steps
    }
}

enum MinecraftFurnaceE2EScenarioFactory {
    static func redstoneFurnaceSmelt(layout: MinecraftFurnaceLayout) -> MinecraftE2EScenario {
        let calibrated = MinecraftCalibratedLayout()
        let setup = [
            MinecraftStep.tap("Close the staged crafting table", calibrated.closeCraftingTable),
            MinecraftStep(name: "Wait for the world HUD", action: .wait(seconds: 2)),
            MinecraftStep(
                name: "Replace the staged crafting table with a furnace",
                action: .chatCommand("/setblock 98 80 95 furnace")
            ),
            MinecraftStep(name: "Give the furnace its generated-recipe input", action: .chatCommand("/give @s redstone")),
            MinecraftStep(name: "Give the furnace vanilla fuel", action: .chatCommand("/give @s coal")),
            MinecraftStep(name: "Wait for the furnace setup commands", action: .wait(seconds: 2))
        ]

        return MinecraftE2EScenario(
            launchArgument: "--ui-testing-redstone-furnace-set",
            prompt: "Generate a redstone furnace set crafted from redstone",
            projectName: "Redstone",
            expectedCraftedItemName: "Redstone Ingot",
            behaviorPackName: "Redstone Behavior",
            resourcePackName: "Redstone Resources",
            craftingPlan: MinecraftCraftingPlan(recipes: [], finalHotbarTap: nil),
            postCraftingSteps: setup + MinecraftFurnacePlanCompiler(layout: layout).smelt(
                inputName: "redstone",
                fuelName: "coal",
                expectedOutputName: "Redstone Ingot"
            )
        )
    }

    static func generatedFuelSmeltsSand(layout: MinecraftFurnaceLayout) -> MinecraftE2EScenario {
        let calibrated = MinecraftCalibratedLayout()
        let setup = [
            MinecraftStep.tap("Close the staged crafting table", calibrated.closeCraftingTable),
            MinecraftStep(name: "Wait for the world HUD", action: .wait(seconds: 2)),
            MinecraftStep(
                name: "Replace the staged crafting table with a furnace",
                action: .chatCommand("/setblock 98 80 95 furnace")
            ),
            MinecraftStep(name: "Give the furnace its sand input", action: .chatCommand("/give @s sand")),
            MinecraftStep(
                name: "Give the player Craftberry's generated fuel",
                action: .chatCommand("/give @s craftberry:redstone_fueltest_fuel")
            ),
            MinecraftStep(name: "Wait for the furnace setup commands", action: .wait(seconds: 2))
        ]
        let smeltSteps = MinecraftFurnacePlanCompiler(layout: layout).smelt(
            inputName: "sand",
            fuelName: "Redstone Fuel",
            expectedOutputName: "Glass"
        )

        return MinecraftE2EScenario(
            launchArgument: "--ui-testing-redstone-consumable-set",
            additionalLaunchArguments: ["--ui-testing-stable-fuel-identifier"],
            prompt: "Generate a redstone consumable set crafted from redstone",
            projectName: "Redstone",
            expectedCraftedItemName: "Glass",
            behaviorPackName: "Redstone Behavior",
            resourcePackName: "Redstone Resources",
            craftingPlan: MinecraftCraftingPlan(recipes: [], finalHotbarTap: nil),
            postCraftingSteps: setup + smeltSteps + [
                MinecraftStep(
                    name: "Check generated fuel was consumed by the furnace",
                    action: .chatCommand("/clear @s craftberry:redstone_fueltest_fuel")
                ),
                MinecraftStep(name: "Confirm Bedrock found no generated fuel to remove", action: .assertText("no items to remove"))
            ]
        )
    }
}

private extension MinecraftStep {
    static func tap(_ name: String, _ coordinate: MinecraftCoordinate) -> MinecraftStep {
        MinecraftStep(name: name, action: .tap(x: coordinate.x, y: coordinate.y))
    }
}
