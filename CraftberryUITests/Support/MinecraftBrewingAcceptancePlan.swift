import Foundation

/// Coordinate set for the brewing-stand gameplay check.
///
/// The station UI is not represented in Minecraft's accessibility tree. Leave
/// every point nil until it has been observed on the calibrated iPhone; the
/// plan then stops with a named calibration requirement instead of guessing.
struct MinecraftBrewingAcceptanceLayout {
    var standWorldTap: MinecraftCoordinate?
    var fuelSlot: MinecraftCoordinate?
    var reagentSlot: MinecraftCoordinate?
    var bottleSlot: MinecraftCoordinate?
    var outputSlot: MinecraftCoordinate?
    var closeStand: MinecraftCoordinate?
    var brewingScreenHotbarSlots: [Int: MinecraftCoordinate]

    static let uncalibrated = MinecraftBrewingAcceptanceLayout(
        standWorldTap: nil,
        fuelSlot: nil,
        reagentSlot: nil,
        bottleSlot: nil,
        outputSlot: nil,
        closeStand: nil,
        brewingScreenHotbarSlots: [:]
    )
}

enum MinecraftBrewingAcceptanceFixture {
    static let materialName = "Craftberry Brewing E2E"
    static let ingotName = "\(materialName) Ingot"
    static let elixirName = "\(materialName) Elixir"
    static let launchArgument = "--ui-testing-brewing-verification-set"
    static let prompt = "Generate the Craftberry Brewing E2E brewing set from redstone"
    static let behaviorPackName = "\(materialName) Behavior"
    static let resourcePackName = "\(materialName) Resources"
}

enum MinecraftBrewingAcceptancePlan {
    static func make(layout: MinecraftBrewingAcceptanceLayout = .uncalibrated) -> [MinecraftStep] {
        var steps: [MinecraftStep] = [
            MinecraftStep(name: "Place a brewing stand at the prepared station", action: .chatCommand("/setblock 98 80 95 brewing_stand")),
            MinecraftStep(name: "Give the player one water bottle", action: .chatCommand("/give @s potion 1 0")),
            MinecraftStep(name: "Give the player blaze powder for stand fuel", action: .chatCommand("/give @s blaze_powder 1")),
            MinecraftStep(name: "Give the player gunpowder for the container recipe", action: .chatCommand("/give @s gunpowder 1")),
            calibratedTap(
                "Open the brewing stand for the elixir recipe",
                coordinate: layout.standWorldTap,
                reason: "Calibrate the brewing stand world tap against the visible stand before opening its interface."
            ),
            MinecraftStep(name: "Wait for the elixir brewing stand screen", action: .wait(seconds: 3)),
            MinecraftStep(name: "Confirm the brewing stand screen is open", action: .assertText("Brewing Stand"))
        ]

        steps += elixirSteps(layout: layout)
        steps.append(calibratedTap(
            "Reopen the brewing stand for the container recipe",
            coordinate: layout.standWorldTap,
            reason: "Calibrate the brewing stand world tap against the visible stand before opening its interface."
        ))
        steps.append(MinecraftStep(name: "Wait for the container-recipe brewing stand screen", action: .wait(seconds: 3)))
        steps.append(MinecraftStep(name: "Confirm the container-recipe stand screen is open", action: .assertText("Brewing Stand")))
        steps += splashSteps(layout: layout)

        return steps
    }

    private static func elixirSteps(layout: MinecraftBrewingAcceptanceLayout) -> [MinecraftStep] {
        let ingotName = MinecraftBrewingAcceptanceFixture.ingotName
        let elixirName = MinecraftBrewingAcceptanceFixture.elixirName
        return transfer("blaze powder", fromHotbarSlot: 3, to: "the fuel slot", coordinate: layout.fuelSlot, reason: "Calibrate the brewing stand fuel slot.", layout: layout) +
        transfer("water bottle", fromHotbarSlot: 2, to: "the bottle slot", coordinate: layout.bottleSlot, reason: "Calibrate one brewing stand bottle slot.", layout: layout) +
        transfer(ingotName, fromHotbarSlot: 1, to: "the reagent slot", coordinate: layout.reagentSlot, reason: "Calibrate the brewing stand reagent slot.", layout: layout) + [
            MinecraftStep(name: "Wait for the \(elixirName) brew to finish", action: .wait(seconds: 25)),
            calibratedTap("Collect the \(elixirName) from the bottle slot", coordinate: layout.outputSlot, reason: "Calibrate the brewing stand output slot before collecting the elixir."),
            MinecraftStep(name: "Wait after collecting the \(elixirName)", action: .wait(seconds: 1)),
            calibratedTap("Close the brewing stand after collecting the elixir", coordinate: layout.closeStand, reason: "Calibrate the brewing stand close control before returning to the world."),
            MinecraftStep(name: "Wait after closing the elixir station", action: .wait(seconds: 2)),
            hudHotbarTap(1, item: elixirName),
            MinecraftStep(name: "Wait for the \(elixirName) tooltip", action: .wait(seconds: 0.2)),
            MinecraftStep(name: "Confirm the collected \(elixirName)", action: .assertText(elixirName)),
            MinecraftStep(name: "Wait for the \(elixirName) tooltip to fade", action: .wait(seconds: 2))
        ]
    }

    private static func splashSteps(layout: MinecraftBrewingAcceptanceLayout) -> [MinecraftStep] {
        let elixirName = MinecraftBrewingAcceptanceFixture.elixirName
        return transfer(elixirName, fromHotbarSlot: 1, to: "the bottle slot", coordinate: layout.bottleSlot, reason: "Calibrate one brewing stand bottle slot.", layout: layout) +
        transfer("gunpowder", fromHotbarSlot: 4, to: "the reagent slot", coordinate: layout.reagentSlot, reason: "Calibrate the brewing stand reagent slot.", layout: layout) + [
            MinecraftStep(name: "Wait for the splash container recipe to finish", action: .wait(seconds: 25)),
            calibratedTap("Collect the Splash Potion from the bottle slot", coordinate: layout.outputSlot, reason: "Calibrate the brewing stand output slot before collecting the splash potion."),
            MinecraftStep(name: "Wait after collecting the Splash Potion", action: .wait(seconds: 1)),
            calibratedTap("Close the brewing stand after collecting the splash output", coordinate: layout.closeStand, reason: "Calibrate the brewing stand close control before returning to the world."),
            MinecraftStep(name: "Wait after closing the container-recipe station", action: .wait(seconds: 2)),
            hudHotbarTap(1, item: "Splash Potion"),
            MinecraftStep(name: "Wait for the Splash Potion tooltip", action: .wait(seconds: 0.2)),
            MinecraftStep(name: "Confirm the collected Splash Potion", action: .assertText("Splash Potion")),
            MinecraftStep(name: "Wait for the Splash Potion tooltip to fade", action: .wait(seconds: 2))
        ]
    }

    private static func transfer(
        _ item: String,
        fromHotbarSlot slot: Int,
        to destination: String,
        coordinate: MinecraftCoordinate?,
        reason: String,
        layout: MinecraftBrewingAcceptanceLayout
    ) -> [MinecraftStep] {
        [
            screenHotbarTap(slot, item: item, layout: layout),
            MinecraftStep(name: "Wait after selecting \(item) for \(destination)", action: .wait(seconds: 1)),
            calibratedTap("Place \(item) in \(destination)", coordinate: coordinate, reason: reason),
            MinecraftStep(name: "Wait after placing \(item) in \(destination)", action: .wait(seconds: 1))
        ]
    }

    private static func screenHotbarTap(_ slot: Int, item: String, layout: MinecraftBrewingAcceptanceLayout) -> MinecraftStep {
        calibratedTap(
            "Select \(item) in brewing-screen hotbar slot \(slot)",
            coordinate: layout.brewingScreenHotbarSlots[slot],
            reason: "Calibrate the brewing-screen hotbar slot \(slot) tap."
        )
    }

    private static func hudHotbarTap(_ slot: Int, item: String) -> MinecraftStep {
        let coordinate = MinecraftCalibratedLayout().hudHotbarSlot(slot)
        return MinecraftStep(name: "Select collected \(item) in HUD hotbar slot \(slot)", action: .tap(x: coordinate.x, y: coordinate.y))
    }

    private static func calibratedTap(_ name: String, coordinate: MinecraftCoordinate?, reason: String) -> MinecraftStep {
        guard let coordinate else {
            return MinecraftStep(name: name, action: .calibrationRequired(reason))
        }
        return MinecraftStep(name: name, action: .tap(x: coordinate.x, y: coordinate.y))
    }
}

extension MinecraftE2EScenario {
    static let craftberryBrewingVerification = MinecraftE2EScenario(
        launchArgument: MinecraftBrewingAcceptanceFixture.launchArgument,
        prompt: MinecraftBrewingAcceptanceFixture.prompt,
        projectName: MinecraftBrewingAcceptanceFixture.materialName,
        expectedCraftedItemName: MinecraftBrewingAcceptanceFixture.elixirName,
        behaviorPackName: MinecraftBrewingAcceptanceFixture.behaviorPackName,
        resourcePackName: MinecraftBrewingAcceptanceFixture.resourcePackName,
        craftingPlan: MinecraftCraftingPlan(
            recipes: [
                .init(
                    outputName: MinecraftBrewingAcceptanceFixture.ingotName,
                    ingredients: [
                        .init(searchText: "redstone", resultColumn: 4, destinations: [.topLeft, .topCenter, .middleLeft, .middleCenter])
                    ],
                    beforePickupVerification: nil,
                    afterPickupVerification: .text(MinecraftBrewingAcceptanceFixture.ingotName),
                    outputDestination: MinecraftCalibratedLayout().hotbarSlot(1),
                    shouldResetTableAfterPickup: false
                )
            ],
            finalHotbarTap: nil
        ),
        postCraftingSteps: MinecraftBrewingAcceptancePlan.make()
    )
}
