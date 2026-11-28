import XCTest

/// Physical-device acceptance for the complete Craftberry-to-Bedrock loop.
///
/// Craftberry export is deterministic. Minecraft's Ore UI does not expose
/// accessibility elements, so in-world setup and crafting are driven through
/// calibrated normalized coordinates from `MinecraftDeviceE2EConfig.json` and
/// `MinecraftCalibratedLayout`.
final class MinecraftDeviceE2EUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCraftberryEmeraldSwordCanBeCraftedInImportedCreativeWorld() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try MinecraftE2EHarness(testCase: self).runPreconfiguredWorld(.emeraldSword, gameMode: .creative)
        #endif
    }

    func testCraftberryShareTargetOpensMinecraftAndImportsWorld() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This share/import check requires Minecraft installed on the dedicated iPhone.")
        #else
        try MinecraftE2EHarness(testCase: self).runPreconfiguredWorldImportOnly(.emeraldSword, gameMode: .creative)
        #endif
    }

    func testCraftberryRedstoneToolSetCanBeImportedActivatedAndCraftedIntoPickaxe() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try MinecraftE2EHarness(testCase: self).run(.redstoneToolSet)
        #endif
    }

    func testCraftberryRedstoneWeaponSetCanCraftSpearInImportedCreativeWorld() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try MinecraftE2EHarness(testCase: self).runPreconfiguredWorld(.redstoneWeaponSet, gameMode: .creative)
        #endif
    }

    func testCraftberryRedstoneArmorSetCanCraftAndEquipBootsInSurvival() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try MinecraftE2EHarness(testCase: self).runPreconfiguredWorld(.redstoneArmorSet, gameMode: .creative)
        #endif
    }

    func testCraftberryRedstoneConsumableSetCanCraftFoodInImportedCreativeWorld() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try MinecraftE2EHarness(testCase: self).runPreconfiguredWorld(.redstoneConsumableSet, gameMode: .creative)
        #endif
    }

    func testCraftberryRedstoneBlockSetCanCraftBlockInImportedCreativeWorld() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try MinecraftE2EHarness(testCase: self).runPreconfiguredWorld(.redstoneBlockSet, gameMode: .creative)
        #endif
    }

    func testCraftberryRedstoneSmithingSetCanCraftIngotInImportedCreativeWorld() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try MinecraftE2EHarness(testCase: self).runPreconfiguredWorld(.redstoneSmithingSet, gameMode: .creative)
        #endif
    }

    func testCraftberryRedstoneFurnaceSetCanCraftSwordInImportedCreativeWorld() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try MinecraftE2EHarness(testCase: self).runPreconfiguredWorld(.redstoneFurnaceSet, gameMode: .creative)
        #endif
    }

    func testCraftberryRedstoneBrewingSetCanCraftIngotInImportedCreativeWorld() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try MinecraftE2EHarness(testCase: self).runPreconfiguredWorld(.redstoneBrewingSet, gameMode: .creative)
        #endif
    }

    func testCraftberryRedstoneStructureSetCanCraftBlockInImportedCreativeWorld() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try MinecraftE2EHarness(testCase: self).runPreconfiguredWorld(.redstoneStructureSet, gameMode: .creative)
        #endif
    }

    func testCraftberryRedstoneOreSetCanCraftOreInImportedCreativeWorld() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try MinecraftE2EHarness(testCase: self).runPreconfiguredWorld(.redstoneOreSet, gameMode: .creative)
        #endif
    }

    func testCraftberryRedstoneCropSetCanCraftSeedsInImportedCreativeWorld() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try MinecraftE2EHarness(testCase: self).runPreconfiguredWorld(.redstoneCropSet, gameMode: .creative)
        #endif
    }

    func testCraftberryRedstoneHostileEntityDamagesPlayerInSurvival() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try MinecraftE2EHarness(testCase: self).runPreconfiguredWorld(.redstoneHostileEntitySet, gameMode: .creative)
        #endif
    }

    func testCraftberryRedstoneBossChangesPhaseAndDropsIngot() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try MinecraftE2EHarness(testCase: self).runPreconfiguredWorld(.redstoneBossEntitySet, gameMode: .creative)
        #endif
    }

    func testCraftberryRedstoneTameableCompanionTamesWithBoneAndFollowsOwner() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try MinecraftE2EHarness(testCase: self).runPreconfiguredWorld(.redstoneTameableEntitySet, gameMode: .creative)
        #endif
    }

    func testCraftberryRedstoneSwordCanBeEnchanted() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try MinecraftE2EHarness(testCase: self).runPreconfiguredWorld(.redstoneEnchantableSwordSet, gameMode: .creative)
        #endif
    }

    func testCraftberryMusicRecordPlaysAndEjectsInJukebox() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        throw XCTSkip("The experiments-off stable profile cannot use custom minecraft:record sound-event names; this scenario is blocked until that changes.")
        #endif
    }
}

/// Where each recipe's output lands in the hotbar.
///
/// Taking an output drops it into the lowest-numbered free slot, so the slot a recipe should tap is
/// a consequence of what the run has already put there — not a free choice. The first recipe of a
/// scenario always crafts into an empty hotbar. A scenario that resets the crafting table between
/// recipes then returns that recipe's four part-used ingredient stacks to slots 2...5, so its second
/// recipe lands in slot 6. Derived rather than measured per recipe, because a stale hand-measured
/// coordinate silently taps a neighbouring slot and reads the wrong item's name.
private let layout = MinecraftCalibratedLayout()
private let firstCraftSlot = layout.hotbarSlot(1)
private let slotAfterIngredientsReturn = layout.hotbarSlot(6)

extension MinecraftE2EScenario {
    static let emeraldSword = MinecraftE2EScenario(
        launchArgument: "--ui-testing-emerald-sword",
        prompt: "Create an Emerald Test Sword crafted from emeralds",
        projectName: "Emerald Test Sword",
        expectedCraftedItemName: "Emerald Test Sword",
        behaviorPackName: "Emerald Test Sword Behavior",
        resourcePackName: "Emerald Test Sword Resources",
        craftingPlan: MinecraftCraftingPlan(
            recipes: [
                .init(
                    outputName: "Emerald Test Sword",
                    ingredients: [
                        .init(searchText: "emerald", resultColumn: 4, destinations: [.topCenter, .middleCenter]),
                        .init(searchText: "stick", resultColumn: 3, destinations: [.bottomCenter])
                    ],
                    beforePickupVerification: nil,
                    afterPickupVerification: .text("$EXPECTED_CRAFTED_ITEM_NAME"),
                    outputDestination: firstCraftSlot,
                    shouldResetTableAfterPickup: false
                )
            ],
            finalHotbarTap: firstCraftSlot
        )
    )

    static let redstoneToolSet = MinecraftE2EScenario(
        launchArgument: "--ui-testing-redstone-tool-set",
        prompt: "Generate a redstone tool set crafted from redstone",
        projectName: "Redstone",
        expectedCraftedItemName: "Redstone Pickaxe",
        behaviorPackName: "Redstone Behavior",
        resourcePackName: "Redstone Resources",
        craftingPlan: MinecraftCraftingPlan(
            recipes: [
                .init(
                    outputName: "Redstone Ingot",
                    ingredients: [
                        .init(searchText: "redstone", resultColumn: 4, destinations: [.topLeft, .topCenter, .middleLeft, .middleCenter])
                    ],
                    beforePickupVerification: nil,
                    afterPickupVerification: .text("Redstone Ingot"),
                    outputDestination: firstCraftSlot,
                    shouldResetTableAfterPickup: true
                ),
                .init(
                    outputName: "Redstone Pickaxe",
                    ingredients: [
                        .init(searchText: "redstone ingot", resultColumn: 1, destinations: [.topLeft, .topCenter, .topRight]),
                        .init(searchText: "stick", resultColumn: 3, destinations: [.middleCenter, .bottomCenter])
                    ],
                    beforePickupVerification: .pixels(.redstonePickaxeOutput),
                    afterPickupVerification: .text("Pickaxe"),
                    outputDestination: slotAfterIngredientsReturn,
                    shouldResetTableAfterPickup: false
                )
            ],
            finalHotbarTap: nil
        )
    )

    static let redstoneWeaponSet = MinecraftE2EScenario(
        launchArgument: "--ui-testing-redstone-weapon-set",
        prompt: "Generate a redstone weapon set crafted from redstone",
        projectName: "Redstone",
        expectedCraftedItemName: "Redstone Spear",
        behaviorPackName: "Redstone Behavior",
        resourcePackName: "Redstone Resources",
        craftingPlan: MinecraftCraftingPlan(
            recipes: [
                .init(
                    outputName: "Redstone Ingot",
                    ingredients: [
                        .init(searchText: "redstone", resultColumn: 4, destinations: [.topLeft, .topCenter, .middleLeft, .middleCenter])
                    ],
                    beforePickupVerification: nil,
                    afterPickupVerification: .text("Redstone"),
                    outputDestination: firstCraftSlot,
                    shouldResetTableAfterPickup: true
                ),
                .init(
                    outputName: "Redstone Spear",
                    ingredients: [
                        .init(searchText: "redstone ingot", resultColumn: 1, destinations: [.topRight]),
                        .init(searchText: "stick", resultColumn: 3, destinations: [.middleCenter, .bottomLeft])
                    ],
                    beforePickupVerification: nil,
                    afterPickupVerification: .text("Spear"),
                    outputDestination: slotAfterIngredientsReturn,
                    shouldResetTableAfterPickup: false
                )
            ],
            finalHotbarTap: nil
        )
    )

    static let redstoneArmorSet = MinecraftE2EScenario(
        launchArgument: "--ui-testing-redstone-armor-set",
        prompt: "Generate a redstone armor set crafted from redstone",
        projectName: "Redstone",
        expectedCraftedItemName: "Redstone Boots",
        behaviorPackName: "Redstone Behavior",
        resourcePackName: "Redstone Resources",
        craftingPlan: MinecraftCraftingPlan(
            // Single recipe: the boots pick their ingots straight from
            // Creative search, so no ingot-crafting prelude is needed (the
            // identical shapeless ingot shape is covered across all other
            // scenarios). Skipping the prelude also skips the mid-flow
            // table close/reopen, whose post-reopen takes proved flaky.
            recipes: [
                .init(
                    outputName: "Redstone Boots",
                    ingredients: [
                        // Each 64-stack cell measures ~1000 red pixels
                        // against 0 empty in every plausible orientation
                        // (threshold 600).
                        MinecraftCraftingPlan.IngredientPlacement(
                            searchText: "redstone ingot",
                            resultColumn: 1,
                            destinations: [.topLeft, .topRight, .middleLeft, .middleRight],
                            verifyPlacements: [
                                .redCluster(xRange: 0.639...0.669, yRange: 0.130...0.190, minimumCount: 600),
                                .redCluster(xRange: 0.749...0.779, yRange: 0.130...0.190, minimumCount: 600),
                                .redCluster(xRange: 0.639...0.669, yRange: 0.250...0.310, minimumCount: 600),
                                .redCluster(xRange: 0.749...0.779, yRange: 0.250...0.310, minimumCount: 600)
                            ]
                        )
                    ],
                    // Fails loudly when any place tap was dropped (no
                    // output can appear): boots measure ~1442 red pixels
                    // against 0 empty (threshold 800).
                    beforePickupVerification: .pixels(.redCluster(xRange: 0.66...0.73, yRange: 0.63...0.75, minimumCount: 800)),
                    // Pixels, not a tooltip: a fresh selection raises only
                    // a ~500ms transient tooltip that OCR's multi-second
                    // polls always miss (confirmed live). Six takes land
                    // boots through slot 6, which stays unselected (and
                    // therefore liftable) while selection sits on slot 1;
                    // its icon measures 667 red pixels against 0 empty
                    // (threshold 300).
                    afterPickupVerification: .pixels(.redCluster(xRange: 0.548...0.575, yRange: 0.848...0.914, minimumCount: 300)),
                    outputDestination: slotAfterIngredientsReturn,
                    shouldResetTableAfterPickup: false
                )
            ],
            finalHotbarTap: nil
        ),
        postCraftingSteps: [
            MinecraftStep(name: "Set daytime before the Survival equip test", action: .chatCommand("/time set day")),
            MinecraftStep(name: "Set peaceful difficulty before the Survival equip test", action: .chatCommand("/difficulty peaceful")),
            MinecraftStep(name: "Disable mob spawning before the Survival equip test", action: .chatCommand("/gamerule domobspawning false")),
            MinecraftStep(name: "Enter Survival to equip the crafted boots", action: .chatCommand("/gamemode survival @s")),
            MinecraftStep(name: "Wait to land after entering Survival", action: .wait(seconds: 4)),
            // No deselect needed: the boots land in slot 6 while selection
            // stays on slot 1, so slot 6 is already unselected (and
            // therefore liftable) when the inventory opens.
            MinecraftStep(name: "Open the Survival inventory", action: .tapUntilText(x: 0.69, y: 0.90, fallbackX: 0.71, fallbackY: 0.91, text: "Crafting")),
            MinecraftStep(name: "Confirm the Survival inventory is open", action: .assertText("Crafting")),
            MinecraftStep(name: "Open the Armor tab", action: .tap(x: 0.945, y: 0.745)),
            MinecraftStep(name: "Confirm the Armor tab is open", action: .assertText("Armor")),
            // Tap slot 6 to pick the boots up, tap feet to place them. The
            // icon stays put visually through taps, but the stack moves
            // logically (verified: a vanilla control pair swapped in and
            // back out through this exact flow).
            MinecraftStep(name: "Pick up the crafted Redstone Boots from hotbar slot 6", action: .tap(x: layout.hotbarSlot(6).x, y: layout.hotbarSlot(6).y)),
            MinecraftStep(name: "Place the boots into the feet armor slot", action: .tap(x: 0.552, y: 0.616)),
            // Lift-back proof, NOT a pixel count: run 37 proved the
            // equipped boots render pixel-identical (874 red) to the
            // empty-slot ghost, so no red threshold can ever pass here.
            // Tapping the occupied feet slot lifts the boots and raises
            // their "Boots" tooltip; tapping the ghost yields nothing, so
            // the tooltip discriminates perfectly. "Boots", not "Redstone":
            // Vision reads the pixel font's "Redstone" as "Fiedstone".
            MinecraftStep(name: "Lift the boots back out to prove they equipped", action: .tapUntilText(x: 0.552, y: 0.616, fallbackX: 0.552, fallbackY: 0.616, text: "Boots")),
            MinecraftStep(name: "Close the inventory for world cleanup", action: .tap(x: layout.closeCraftingTable.x, y: layout.closeCraftingTable.y)),
        ]
    )

    static let redstoneConsumableSet = MinecraftE2EScenario(
        launchArgument: "--ui-testing-redstone-consumable-set",
        prompt: "Generate a redstone consumable set crafted from redstone",
        projectName: "Redstone",
        expectedCraftedItemName: "Redstone Food",
        behaviorPackName: "Redstone Behavior",
        resourcePackName: "Redstone Resources",
        craftingPlan: MinecraftCraftingPlan(
            recipes: [
                .init(
                    outputName: "Redstone Ingot",
                    ingredients: [
                        .init(searchText: "redstone", resultColumn: 4, destinations: [.topLeft, .topCenter, .middleLeft, .middleCenter])
                    ],
                    beforePickupVerification: nil,
                    afterPickupVerification: .text("Redstone"),
                    outputDestination: firstCraftSlot,
                    shouldResetTableAfterPickup: true
                ),
                .init(
                    outputName: "Redstone Food",
                    ingredients: [
                        // This prefix uniquely selects the ingot in the consumable fixture.
                        // The full query repeated a vowel on-device and returned no results.
                        .init(searchText: "redstone ing", resultColumn: 1, destinations: [.topLeft, .topCenter, .topRight, .middleLeft, .middleRight])
                    ],
                    // Captured frames show 1,292 red pixels with food ready and zero with an empty grid.
                    beforePickupVerification: .pixels(.redCluster(xRange: 0.66...0.73, yRange: 0.63...0.75, minimumCount: 600)),
                    afterPickupVerification: .text("Food"),
                    outputDestination: slotAfterIngredientsReturn,
                    shouldResetTableAfterPickup: false
                )
            ],
            finalHotbarTap: nil
        ),
        postCraftingSteps: [
            MinecraftStep(name: "Set daytime for the food-eating test", action: .chatCommand("/time set day")),
            MinecraftStep(name: "Clear weather for the food-eating test", action: .chatCommand("/weather clear")),
            MinecraftStep(name: "Set normal difficulty so hunger can drain", action: .chatCommand("/difficulty normal")),
            MinecraftStep(name: "Disable mob spawning for the food-eating test", action: .chatCommand("/gamerule domobspawning false")),
            MinecraftStep(name: "Enter Survival to eat the crafted food", action: .chatCommand("/gamemode survival @s")),
            MinecraftStep(name: "Wait to land after entering Survival", action: .wait(seconds: 4)),
            // Face away from the crafting table, level: the eat press cannot
            // open it, and the top of the screen (where the hunger row sits)
            // shows sky, so dirt browns cannot pollute the pixel asserts.
            MinecraftStep(name: "Face away from the crafting table", action: .chatCommand("/tp @s 100 80 95 270 0")),
            // The fixture food has canAlwaysEat false, so the player must be
            // hungry before the eat press can consume anything. Drain to a
            // known-empty bar, prove it empty, then eat and prove it restored.
            // Amplifier 255: amplifier 10 drained only 3 drumsticks in 25s
            // live (2250 to 1575 brown), far too slow for a full drain.
            MinecraftStep(name: "Drain hunger with the hunger effect", action: .chatCommand("/effect @s hunger 300 255")),
            MinecraftStep(name: "Wait for hunger to drain", action: .wait(seconds: 60)),
            // Full drumstick row, measured off a device screenshot: x
            // 0.80...0.96, y 0.01...0.04. Sky behind it reads 0 brown; dirt
            // elsewhere in frame does match brown, hence facing away first.
            MinecraftStep(name: "Confirm the hunger bar is empty", action: .assertPixels(.brownAbsent(xRange: 0.795...0.965, yRange: 0.005...0.045, maximumCount: 80))),
            MinecraftStep(name: "Clear the hunger effect before eating", action: .chatCommand("/effect @s clear")),
            MinecraftStep(name: "Select the crafted Redstone Food", action: .tap(x: layout.hudHotbarSlot(6).x, y: layout.hudHotbarSlot(6).y)),
            MinecraftStep(name: "Confirm the Redstone Food tooltip", action: .assertText("Food")),
            // Two presses: the engine silently ignores some synthesized
            // gestures, and the restore assert below passes for any nonzero
            // number of eats, so a retry only helps.
            MinecraftStep(name: "Eat the held Redstone Food", action: .pressAndHold(x: 0.5, y: 0.4, seconds: 6)),
            MinecraftStep(name: "Wait between eat presses", action: .wait(seconds: 2)),
            MinecraftStep(name: "Eat the held Redstone Food again", action: .pressAndHold(x: 0.5, y: 0.4, seconds: 6)),
            MinecraftStep(name: "Wait for the eat animation to finish", action: .wait(seconds: 3)),
            // Nutrition 6 restores exactly three drumsticks from empty, filled
            // left to right — the left slice of the bar reads ~675 brown
            // against 0 drained, so it is brown only when the eat consumed.
            MinecraftStep(name: "Confirm hunger restored after eating", action: .assertPixels(.brownCluster(xRange: 0.795...0.85, yRange: 0.005...0.045, minimumCount: 350))),
        ]
    )

    static let redstoneSmithingSet = MinecraftE2EScenario(
        launchArgument: "--ui-testing-redstone-smithing-set",
        prompt: "Generate a redstone smithing set crafted from redstone",
        projectName: "Redstone",
        expectedCraftedItemName: "Redstone Ingot",
        behaviorPackName: "Redstone Behavior",
        resourcePackName: "Redstone Resources",
        craftingPlan: MinecraftCraftingPlan(
            recipes: [
                .init(
                    outputName: "Redstone Ingot",
                    ingredients: [
                        .init(searchText: "redstone", resultColumn: 4, destinations: [.topLeft, .topCenter, .middleLeft, .middleCenter])
                    ],
                    beforePickupVerification: nil,
                    afterPickupVerification: .text("Redstone"),
                    outputDestination: firstCraftSlot,
                    shouldResetTableAfterPickup: false
                )
            ],
            finalHotbarTap: nil
        )
    )

    static let redstoneFurnaceSet = MinecraftE2EScenario(
        launchArgument: "--ui-testing-redstone-furnace-set",
        prompt: "Generate a redstone furnace set crafted from redstone",
        projectName: "Redstone",
        expectedCraftedItemName: "Redstone Sword",
        behaviorPackName: "Redstone Behavior",
        resourcePackName: "Redstone Resources",
        craftingPlan: MinecraftCraftingPlan(
            recipes: [
                .init(
                    outputName: "Redstone Sword",
                    ingredients: [
                        .init(searchText: "redstone ingot", resultColumn: 1, destinations: [.topCenter, .middleCenter]),
                        .init(searchText: "stick", resultColumn: 3, destinations: [.bottomCenter])
                    ],
                    beforePickupVerification: nil,
                    afterPickupVerification: .text("Sword"),
                    outputDestination: firstCraftSlot,
                    shouldResetTableAfterPickup: false
                )
            ],
            finalHotbarTap: nil
        )
    )

    static let redstoneBrewingSet = MinecraftE2EScenario(
        launchArgument: "--ui-testing-redstone-brewing-set",
        prompt: "Generate a redstone brewing set crafted from redstone",
        projectName: "Redstone",
        expectedCraftedItemName: "Redstone Ingot",
        behaviorPackName: "Redstone Behavior",
        resourcePackName: "Redstone Resources",
        craftingPlan: MinecraftCraftingPlan(
            recipes: [
                .init(
                    outputName: "Redstone Ingot",
                    ingredients: [
                        .init(searchText: "redstone", resultColumn: 4, destinations: [.topLeft, .topCenter, .middleLeft, .middleCenter])
                    ],
                    beforePickupVerification: nil,
                    afterPickupVerification: .text("Redstone"),
                    outputDestination: firstCraftSlot,
                    shouldResetTableAfterPickup: false
                )
            ],
            finalHotbarTap: nil
        )
    )

    static let redstoneStructureSet = MinecraftE2EScenario(
        launchArgument: "--ui-testing-redstone-structure-set",
        prompt: "Generate a redstone structure hut built from redstone blocks",
        projectName: "Redstone",
        expectedCraftedItemName: "Redstone Block",
        behaviorPackName: "Redstone Behavior",
        resourcePackName: "Redstone Resources",
        craftingPlan: MinecraftCraftingPlan(
            recipes: [
                .init(
                    outputName: "Redstone Ingot",
                    ingredients: [
                        .init(searchText: "redstone", resultColumn: 4, destinations: [.topLeft, .topCenter, .middleLeft, .middleCenter])
                    ],
                    beforePickupVerification: nil,
                    afterPickupVerification: .text("Redstone"),
                    outputDestination: firstCraftSlot,
                    shouldResetTableAfterPickup: true
                ),
                .init(
                    outputName: "Redstone Block",
                    ingredients: [
                        .init(searchText: "redstone ingot", resultColumn: 1, destinations: [.topLeft, .topCenter, .topRight, .middleLeft, .middleCenter, .middleRight, .bottomLeft, .bottomCenter, .bottomRight])
                    ],
                    beforePickupVerification: nil,
                    afterPickupVerification: .text("Block"),
                    outputDestination: slotAfterIngredientsReturn,
                    shouldResetTableAfterPickup: false
                )
            ],
            finalHotbarTap: nil
        )
    )

    static let redstoneOreSet = MinecraftE2EScenario(
        launchArgument: "--ui-testing-redstone-ore-set",
        prompt: "Generate a redstone ore set crafted from redstone",
        projectName: "Redstone",
        expectedCraftedItemName: "Redstone Ore",
        behaviorPackName: "Redstone Behavior",
        resourcePackName: "Redstone Resources",
        craftingPlan: MinecraftCraftingPlan(
            recipes: [
                .init(outputName: "Redstone Ingot", ingredients: [.init(searchText: "redstone", resultColumn: 4, destinations: [.topLeft, .topCenter, .middleLeft, .middleCenter])], beforePickupVerification: nil, afterPickupVerification: .text("Redstone"), outputDestination: firstCraftSlot, shouldResetTableAfterPickup: true),
                .init(outputName: "Redstone Ore", ingredients: [.init(searchText: "redstone ingot", resultColumn: 1, destinations: [.topLeft, .topCenter, .topRight, .middleLeft, .middleCenter, .middleRight, .bottomLeft, .bottomCenter, .bottomRight])], beforePickupVerification: nil, afterPickupVerification: .text("Ore"), outputDestination: slotAfterIngredientsReturn, shouldResetTableAfterPickup: false)
            ], finalHotbarTap: nil)
    )

    static let redstoneCropSet = MinecraftE2EScenario(
        launchArgument: "--ui-testing-redstone-crop-set",
        prompt: "Generate a redstone crop set crafted from redstone",
        projectName: "Redstone",
        expectedCraftedItemName: "Redstone Seeds",
        behaviorPackName: "Redstone Behavior",
        resourcePackName: "Redstone Resources",
        craftingPlan: MinecraftCraftingPlan(recipes: [.init(outputName: "Redstone Seeds", ingredients: [.init(searchText: "redstone", resultColumn: 4, destinations: [.topLeft, .topCenter, .middleLeft, .middleCenter])], beforePickupVerification: nil, afterPickupVerification: .text("Seeds"), outputDestination: firstCraftSlot, shouldResetTableAfterPickup: false)], finalHotbarTap: nil)
    )

    static let redstoneHostileEntitySet = MinecraftE2EScenario(
        launchArgument: "--ui-testing-redstone-hostile-entity-set",
        prompt: "Generate a hostile redstone creature with a craftable spawn egg",
        projectName: "Redstone",
        expectedCraftedItemName: "Redstone Spawn Egg",
        behaviorPackName: "Redstone Behavior",
        resourcePackName: "Redstone Resources",
        craftingPlan: MinecraftCraftingPlan(
            recipes: [
                .init(
                    outputName: "Redstone Spawn Egg",
                    ingredients: [
                        .init(searchText: "redstone ingot", resultColumn: 1, destinations: [.topCenter, .middleLeft, .middleRight, .bottomCenter]),
                        .init(searchText: "egg", resultColumn: 1, destinations: [.middleCenter])
                    ],
                    beforePickupVerification: nil,
                    afterPickupVerification: .text("Spawn"),
                    outputDestination: firstCraftSlot,
                    shouldResetTableAfterPickup: false
                )
            ],
            finalHotbarTap: nil
        ),
        postCraftingSteps: [
            MinecraftStep(name: "Set daytime for a controlled hostile test", action: .chatCommand("/time set day")),
            MinecraftStep(name: "Clear weather for a controlled hostile test", action: .chatCommand("/weather clear")),
            MinecraftStep(name: "Set a non-peaceful difficulty for hostile AI", action: .chatCommand("/difficulty normal")),
            MinecraftStep(name: "Disable natural mob spawning for a deterministic hostile test", action: .chatCommand("/gamerule domobspawning false")),
            MinecraftStep(name: "Clear existing hostile mobs", action: .chatCommand("/kill @e[family=monster]")),
            MinecraftStep(name: "Build a safe, deterministic platform", action: .chatCommand("/fill 98 79 94 101 79 96 stone")),
            MinecraftStep(name: "Place a solid, non-interactable spawn-egg target block", action: .chatCommand("/setblock 98 80 95 stone")),
            MinecraftStep(name: "Return to the calibrated spawn-egg position", action: .chatCommand("/tp @s 100 80 95 90 45")),
            MinecraftStep(name: "Select the crafted Redstone Spawn Egg", action: .tap(x: layout.hotbarSlot(1).x, y: layout.hotbarSlot(1).y)),
            MinecraftStep(name: "Use the spawn egg on the nearby block", action: .tap(x: 0.5075, y: 0.265)),
            MinecraftStep(name: "Wait for the hostile creature to spawn", action: .wait(seconds: 2)),
            MinecraftStep(name: "Query for the hostile creature family", action: .chatCommand("/testfor @e[family=monster]")),
            MinecraftStep(name: "Confirm a hostile creature spawned", action: .assertText("Found")),
            MinecraftStep(name: "Enter Survival for the damage check", action: .chatCommand("/gamemode survival @s")),
            MinecraftStep(name: "Wait for the hostile creature to attack in Survival", action: .wait(seconds: 45)),
            MinecraftStep(name: "Verify hostile damage reaches zero health", action: .assertText("You died")),
            MinecraftStep(name: "Respawn after verifying hostile damage", action: .tapTextRow(x: 0.5, text: "Respawn")),
            MinecraftStep(name: "Wait for the player to respawn", action: .wait(seconds: 8))
        ]
    )

    static let redstoneBossEntitySet = MinecraftE2EScenario(
        launchArgument: "--ui-testing-redstone-boss-set",
        prompt: "Generate a redstone boss with a health-triggered second phase and a guaranteed ingot reward",
        projectName: "Redstone",
        expectedCraftedItemName: "Redstone Spawn Egg",
        behaviorPackName: "Redstone Behavior",
        resourcePackName: "Redstone Resources",
        craftingPlan: MinecraftCraftingPlan(
            recipes: [
                .init(
                    outputName: "Redstone Spawn Egg",
                    ingredients: [
                        .init(searchText: "redstone ingot", resultColumn: 1, destinations: [.topCenter, .middleLeft, .middleRight, .bottomCenter]),
                        .init(searchText: "egg", resultColumn: 1, destinations: [.middleCenter])
                    ],
                    beforePickupVerification: nil,
                    afterPickupVerification: .text("Spawn"),
                    outputDestination: firstCraftSlot,
                    shouldResetTableAfterPickup: false
                )
            ],
            finalHotbarTap: nil
        ),
        postCraftingSteps: [
            MinecraftStep(name: "Set daytime for a controlled boss test", action: .chatCommand("/time set day")),
            MinecraftStep(name: "Clear weather for a controlled boss test", action: .chatCommand("/weather clear")),
            MinecraftStep(name: "Set a non-peaceful difficulty for boss AI", action: .chatCommand("/difficulty normal")),
            MinecraftStep(name: "Disable natural mob spawning for a deterministic boss test", action: .chatCommand("/gamerule domobspawning false")),
            MinecraftStep(name: "Clear existing hostile mobs", action: .chatCommand("/kill @e[family=monster]")),
            MinecraftStep(name: "Build a wide deterministic boss platform", action: .chatCommand("/fill 90 79 85 110 79 105 stone")),
            MinecraftStep(name: "Place a solid boss spawn-egg target block", action: .chatCommand("/setblock 98 80 95 stone")),
            MinecraftStep(name: "Return to the calibrated boss spawn position", action: .chatCommand("/tp @s 100 80 95 90 45")),
            MinecraftStep(name: "Select the crafted Redstone Spawn Egg", action: .tap(x: layout.hotbarSlot(1).x, y: layout.hotbarSlot(1).y)),
            MinecraftStep(name: "Use the spawn egg on the nearby block", action: .tap(x: 0.5075, y: 0.265)),
            MinecraftStep(name: "Wait for the boss to spawn", action: .wait(seconds: 2)),
            MinecraftStep(name: "Confirm the boss name is visible", action: .assertText("Redstone Boss")),
            MinecraftStep(name: "Query for the spawned boss family", action: .chatCommand("/testfor @e[family=monster]")),
            MinecraftStep(name: "Confirm exactly one hostile boss spawned", action: .assertText("Found 1")),
            MinecraftStep(name: "Damage the boss below half health to trigger phase two", action: .chatCommand("/damage @e[family=monster] 21 magic")),
            MinecraftStep(name: "Wait for the health sensor to change phases", action: .wait(seconds: 2)),
            MinecraftStep(name: "Enter Survival to verify phase-two attacks", action: .chatCommand("/gamemode survival @s")),
            MinecraftStep(name: "Wait for the stronger boss to defeat the player", action: .wait(seconds: 8)),
            MinecraftStep(name: "Verify the phase-two attack defeats the player", action: .assertText("You died")),
            MinecraftStep(name: "Respawn after verifying the phase-two attack", action: .tapTextRow(x: 0.5, text: "Respawn")),
            MinecraftStep(name: "Wait for the player to respawn", action: .wait(seconds: 8)),
            MinecraftStep(name: "Return to Creative to finish the reward check safely", action: .chatCommand("/gamemode creative @s")),
            MinecraftStep(name: "Remove any earlier generated ingot from the test inventory", action: .chatCommand("/clear @s craftberry:redstone_uitest_ingot")),
            MinecraftStep(name: "Clear item drops before defeating the boss", action: .chatCommand("/kill @e[type=item]")),
            MinecraftStep(name: "Defeat the boss with player-attributed damage", action: .chatCommand("/damage @e[family=monster] 100 entity_attack entity @s")),
            MinecraftStep(name: "Wait for the boss reward to drop", action: .wait(seconds: 2)),
            MinecraftStep(name: "Collect the isolated boss reward", action: .chatCommand("/tp @s @e[type=item]")),
            MinecraftStep(name: "Wait for the redstone ingot to enter inventory", action: .wait(seconds: 2)),
            MinecraftStep(name: "Count the generated redstone ingot", action: .chatCommand("/clear @s craftberry:redstone_uitest_ingot 0 0")),
            MinecraftStep(name: "Confirm exactly one generated redstone ingot", action: .assertText("has 1 items that match the criteria")),
            MinecraftStep(name: "Remove the verified reward from the test inventory", action: .chatCommand("/clear @s craftberry:redstone_uitest_ingot"))
        ]
    )

    static let redstoneTameableEntitySet = MinecraftE2EScenario(
        launchArgument: "--ui-testing-redstone-tameable-entity-set",
        prompt: "Generate a redstone companion tamed with bone that follows its owner",
        projectName: "Redstone",
        expectedCraftedItemName: "Redstone Spawn Egg",
        behaviorPackName: "Redstone Behavior",
        resourcePackName: "Redstone Resources",
        craftingPlan: MinecraftCraftingPlan(
            recipes: [
                .init(
                    outputName: "Redstone Spawn Egg",
                    ingredients: [
                        .init(searchText: "redstone ingot", resultColumn: 1, destinations: [.topCenter, .middleLeft, .middleRight, .bottomCenter]),
                        .init(searchText: "egg", resultColumn: 1, destinations: [.middleCenter])
                    ],
                    beforePickupVerification: nil,
                    afterPickupVerification: .text("Spawn"),
                    outputDestination: firstCraftSlot,
                    shouldResetTableAfterPickup: false
                )
            ],
            finalHotbarTap: nil
        ),
        postCraftingSteps: [
            MinecraftStep(name: "Set daytime for a controlled tameable test", action: .chatCommand("/time set day")),
            MinecraftStep(name: "Clear weather for a controlled tameable test", action: .chatCommand("/weather clear")),
            MinecraftStep(name: "Disable natural mob spawning for a deterministic tameable test", action: .chatCommand("/gamerule domobspawning false")),
            MinecraftStep(name: "Clear prior tameable test creatures", action: .chatCommand("/kill @e[family=tameable_companion]")),
            MinecraftStep(name: "Build a safe path from the spawn point to the owner destination", action: .chatCommand("/fill 98 79 94 114 79 96 stone")),
            MinecraftStep(name: "Place a solid, non-interactable spawn-egg target block", action: .chatCommand("/setblock 98 80 95 stone")),
            MinecraftStep(name: "Return to the calibrated spawn-egg position", action: .chatCommand("/tp @s 100 80 95 90 45")),
            MinecraftStep(name: "Select the crafted Redstone Spawn Egg", action: .tap(x: layout.hotbarSlot(1).x, y: layout.hotbarSlot(1).y)),
            MinecraftStep(name: "Use the spawn egg on the nearby block", action: .tap(x: 0.5075, y: 0.265)),
            MinecraftStep(name: "Wait for the tameable companion to spawn", action: .wait(seconds: 2)),
            MinecraftStep(name: "Query for the spawned tameable companion", action: .chatCommand("/testfor @e[family=tameable_companion,r=5]")),
            MinecraftStep(name: "Confirm a tameable companion spawned", action: .assertText("Found")),
            MinecraftStep(name: "Replace the spawn-egg slot with a bone for guaranteed taming", action: .chatCommand("/replaceitem entity @s slot.hotbar 0 bone 1")),
            MinecraftStep(name: "Select the bone", action: .tap(x: layout.hotbarSlot(1).x, y: layout.hotbarSlot(1).y)),
            MinecraftStep(name: "Confirm the selected item is a bone", action: .assertText("Bone")),
            MinecraftStep(name: "Return to the calibrated tame position", action: .chatCommand("/tp @s 100 80 95 90 45")),
            MinecraftStep(name: "Bring the companion back to the calibrated tame spot", action: .chatCommand("/tp @e[family=tameable_companion] 98 81 95")),
            MinecraftStep(name: "Tame the spawned companion with bone", action: .tap(x: 0.5075, y: 0.265)),
            MinecraftStep(name: "Wait for bone taming and follow behavior to activate", action: .wait(seconds: 2)),
            MinecraftStep(name: "Move the owner beyond the follow start distance", action: .chatCommand("/tp @s 112 80 95 270 0")),
            MinecraftStep(name: "Allow the tamed companion time to follow", action: .wait(seconds: 20)),
            MinecraftStep(name: "Query for the companion near its distant owner", action: .chatCommand("/execute if entity @e[family=tameable_companion,r=6] run time query daytime")),
            MinecraftStep(name: "Confirm the companion followed its owner", action: .assertText("Daytime is"))
        ]
    )

    static let redstoneEnchantableSwordSet = MinecraftE2EScenario(
        launchArgument: "--ui-testing-redstone-enchantable-sword-set",
        prompt: "Generate a redstone sword set with an enchantable sword",
        projectName: "Redstone",
        expectedCraftedItemName: "Redstone Sword",
        behaviorPackName: "Redstone Behavior",
        resourcePackName: "Redstone Resources",
        craftingPlan: MinecraftCraftingPlan(
            recipes: [
                .init(
                    outputName: "Redstone Ingot",
                    ingredients: [.init(searchText: "redstone", resultColumn: 4, destinations: [.topLeft, .topCenter, .middleLeft, .middleCenter])],
                    beforePickupVerification: nil,
                    afterPickupVerification: .text("Redstone"),
                    outputDestination: firstCraftSlot,
                    shouldResetTableAfterPickup: true
                ),
                .init(
                    outputName: "Redstone Sword",
                    ingredients: [
                        .init(searchText: "redstone ingot", resultColumn: 1, destinations: [.topCenter, .middleCenter]),
                        .init(searchText: "stick", resultColumn: 3, destinations: [.bottomCenter])
                    ],
                    beforePickupVerification: nil,
                    afterPickupVerification: .text("Sword"),
                    outputDestination: slotAfterIngredientsReturn,
                    shouldResetTableAfterPickup: false
                )
            ],
            finalHotbarTap: nil
        ),
        postCraftingSteps: [
            MinecraftStep(name: "Set daytime for the enchanting test", action: .chatCommand("/time set day")),
            MinecraftStep(name: "Place an enchanting table at the calibrated station", action: .chatCommand("/setblock 98 80 95 enchanting_table")),
            MinecraftStep(name: "Enter Survival before opening the enchanting table", action: .chatCommand("/gamemode survival @s")),
            MinecraftStep(name: "Open the enchanting table using the calibrated world interaction point", action: .tapUntilText(x: 0.5075, y: 0.265, fallbackX: 0.5075, fallbackY: 0.38, text: "Enchant")),
            MinecraftStep(name: "Confirm the enchanting-table interface is open", action: .assertText("Enchant")),
            MinecraftStep(name: "Close the enchanting table interface", action: .tap(x: 0.865, y: 0.16)),
            MinecraftStep(name: "Select the crafted Redstone Sword", action: .tap(x: layout.hudHotbarSlot(6).x, y: layout.hudHotbarSlot(6).y)),
            MinecraftStep(name: "Confirm the Redstone Sword tooltip", action: .assertText("Redstone Sword")),
            MinecraftStep(name: "Wait for the sword tooltip to fade", action: .wait(seconds: 2)),
            MinecraftStep(name: "Enchant the held sword with sharpness", action: .chatCommand("/enchant @s sharpness")),
            MinecraftStep(name: "Confirm the enchantment applied", action: .assertText("Enchanting succeeded")),
        ],
        cleansUpInWorld: false
    )

    static let redstoneBlockSet = MinecraftE2EScenario(
        launchArgument: "--ui-testing-redstone-block-set",
        prompt: "Generate a redstone block set crafted from redstone",
        projectName: "Redstone",
        expectedCraftedItemName: "Redstone Block",
        behaviorPackName: "Redstone Behavior",
        resourcePackName: "Redstone Resources",
        craftingPlan: MinecraftCraftingPlan(
            recipes: [
                .init(
                    outputName: "Redstone Ingot",
                    ingredients: [
                        .init(searchText: "redstone", resultColumn: 4, destinations: [.topLeft, .topCenter, .middleLeft, .middleCenter])
                    ],
                    beforePickupVerification: nil,
                    afterPickupVerification: .text("Redstone"),
                    outputDestination: firstCraftSlot,
                    shouldResetTableAfterPickup: true
                ),
                .init(
                    outputName: "Redstone Block",
                    ingredients: [
                        .init(searchText: "redstone ingot", resultColumn: 1, destinations: [.topLeft, .topCenter, .topRight, .middleLeft, .middleCenter, .middleRight, .bottomLeft, .bottomCenter, .bottomRight])
                    ],
                    beforePickupVerification: nil,
                    afterPickupVerification: .text("Block"),
                    outputDestination: slotAfterIngredientsReturn,
                    shouldResetTableAfterPickup: false
                )
            ],
            finalHotbarTap: nil
        )
    )

    static let musicRecord = MinecraftE2EScenario(
        launchArgument: "--ui-testing-music-record-set",
        prompt: "A cyan music record called First Light, dreamy",
        projectName: "First Light",
        expectedCraftedItemName: "First Light",
        behaviorPackName: "First Light Behavior",
        resourcePackName: "First Light Resources",
        craftingPlan: MinecraftCraftingPlan(
            recipes: [
                .init(
                    outputName: "First Light",
                    ingredients: [
                        .init(searchText: "diamond", resultColumn: 4, destinations: [.topLeft, .topCenter, .topRight, .middleLeft, .middleRight, .bottomLeft, .bottomCenter, .bottomRight]),
                        .init(searchText: "redstone", resultColumn: 4, destinations: [.middleCenter])
                    ],
                    beforePickupVerification: nil,
                    afterPickupVerification: .text("First Light"),
                    outputDestination: firstCraftSlot,
                    shouldResetTableAfterPickup: false
                )
            ],
            finalHotbarTap: nil
        ),
        postCraftingSteps: [
            MinecraftStep(name: "Set daytime for jukebox verification", action: .chatCommand("/time set day")),
            MinecraftStep(name: "Prepare a clear jukebox test platform", action: .chatCommand("/fill 97 79 94 101 79 96 stone")),
            MinecraftStep(name: "Place a jukebox at the calibrated test station", action: .chatCommand("/setblock 98 80 95 jukebox")),
            MinecraftStep(name: "Face the jukebox from the calibrated interaction point", action: .chatCommand("/tp @s 100 80 95 90 45")),
            MinecraftStep(name: "Clear loose items before the jukebox ejection check", action: .chatCommand("/kill @e[type=item]")),
            MinecraftStep(name: "Select the crafted First Light music record", action: .tap(x: layout.hudHotbarSlot(1).x, y: layout.hudHotbarSlot(1).y)),
            MinecraftStep(name: "Confirm the First Light record tooltip", action: .assertText("First Light")),
            MinecraftStep(name: "Insert First Light into the jukebox", action: .tap(x: 0.5075, y: 0.265)),
            MinecraftStep(name: "Confirm jukebox playback notification", action: .assertText("Now Playing")),
            MinecraftStep(name: "Let the original record play", action: .wait(seconds: 3)),
            MinecraftStep(name: "Eject First Light from the jukebox", action: .tap(x: 0.5075, y: 0.265)),
            MinecraftStep(name: "Check that the ejected record is dropped nearby", action: .chatCommand("/testfor @e[type=item]")),
            MinecraftStep(name: "Confirm the record was ejected", action: .assertText("Found"))
        ]
    )
}
