import XCTest

/// Dedicated device acceptance for planting a generated seed, growing each crop stage, and
/// collecting the mature produce. Kept separate from the shared feature test suite so a crop
/// mechanic change does not modify another worker's active scenario list.
final class MinecraftCropGrowthE2EUITests: XCTestCase {
    func testCropSeedPlantsGrowsToMaturityAndDropsProduce() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try MinecraftE2EHarness(testCase: self).runPreconfiguredWorld(
            .cropGrowth,
            gameMode: .creative,
            freshPackIdentity: false
        )
        #endif
    }
}

private extension MinecraftE2EScenario {
    static let cropBlockID = "craftberry:crop_growth_uitest_crop"
    static let cropGrowthState = "craftberry:growth_crop_growth_uitest_crop"

    static let cropGrowth = MinecraftE2EScenario(
        launchArgument: "--ui-testing-crop-growth",
        prompt: "Create a crop named Crop Growth that grows through eight stages and can be harvested",
        projectName: "Crop Growth",
        expectedCraftedItemName: "Crop Growth Seeds",
        behaviorPackName: "Crop Growth Behavior",
        resourcePackName: "Crop Growth Resources",
        craftingPlan: MinecraftCraftingPlan(
            recipes: [
                .init(
                    outputName: "Crop Growth Seeds",
                    ingredients: [
                        .init(searchText: "diamond", resultColumn: 4, destinations: [.topLeft, .topCenter, .middleLeft, .middleCenter])
                    ],
                    beforePickupVerification: nil,
                    afterPickupVerification: .text("Seeds"),
                    outputDestination: MinecraftCalibratedLayout().hotbarSlot(1),
                    shouldResetTableAfterPickup: false
                )
            ],
            finalHotbarTap: MinecraftCalibratedLayout().hudHotbarSlot(1)
        ),
        postCraftingSteps: [
            MinecraftStep(name: "Speed up random ticks for crop growth", action: .chatCommand("/gamerule randomtickspeed 1000")),
            MinecraftStep(name: "Prepare farmland at the calibrated target", action: .chatCommand("/setblock 98 79 95 farmland")),
            MinecraftStep(name: "Clear the crop placement target", action: .chatCommand("/setblock 98 80 95 air")),
            MinecraftStep(name: "Enter Survival to verify harvest drops", action: .chatCommand("/gamemode survival @s")),
            MinecraftStep(name: "Return to the calibrated seed-planting position", action: .chatCommand("/tp @s 100 80 95 90 45")),
            MinecraftStep(name: "Plant the crafted seeds on farmland", action: .tap(x: 0.5075, y: 0.265)),
            MinecraftStep(name: "Wait for all eight crop growth stages", action: .wait(seconds: 45)),
            MinecraftStep(
                name: "Verify the crop reached mature growth stage seven",
                action: .chatCommand("/testforblock 98 80 95 \(Self.cropBlockID) [\"\(Self.cropGrowthState)\"=7]")
            ),
            MinecraftStep(name: "Confirm the mature crop block state", action: .assertText("found the block")),
            MinecraftStep(name: "Move within pickup range of the mature crop", action: .chatCommand("/tp @s 98.5 80 95.2")),
            MinecraftStep(name: "Harvest the mature crop and its drops", action: .chatCommand("/setblock 98 80 95 air destroy")),
            MinecraftStep(name: "Collect one mature crop produce item", action: .chatCommand("/clear @s craftberry:crop_growth_uitest_produce -1 1")),
            MinecraftStep(name: "Confirm mature crop produced harvest food", action: .assertText("Removed 1")),
            MinecraftStep(name: "Restore the test world's normal random tick speed", action: .chatCommand("/gamerule randomtickspeed 1"))
        ]
    )
}
