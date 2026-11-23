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

    func testCraftberryRedstoneSwordCanBeEnchanted() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try MinecraftE2EHarness(testCase: self).runPreconfiguredWorld(.redstoneEnchantableSwordSet, gameMode: .creative)
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
                    // polls always miss (confirmed live). Takes auto-move
                    // straight to first-free slot 1; its boots icon
                    // measures ~800 red pixels against 0 empty in the
                    // tagged orientation (threshold 400).
                    afterPickupVerification: .pixels(.redCluster(xRange: 0.255...0.300, yRange: 0.810...0.950, minimumCount: 400)),
                    outputDestination: firstCraftSlot,
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
            // Select full HUD ingot slot 5 so boots slot 1 is unselected
            // when the inventory opens: taps only lift from unselected
            // slots, and only full-slot HUD taps reliably move selection
            // (empty-slot taps anywhere do not move it at all; confirmed
            // live). Slot 5 is used because the HUD hotbar's edge slots
            // deviate from the calibrated pitch (live: slot-2 taps miss
            // twice while center slots land), and slot 5 provably selects.
            // Leftover grid ingots deterministically refill slots 2-5, so
            // slot 5 always holds ingots; the Ingot tooltip gates the move
            // (tooltip-only on screen, Fiedstone-proof).
            MinecraftStep(name: "Select full HUD ingot slot 5 to deselect slot 1", action: .tapUntilText(x: layout.hudHotbarSlot(5).x, y: layout.hudHotbarSlot(5).y, fallbackX: layout.hudHotbarSlot(5).x, fallbackY: layout.hudHotbarSlot(5).y, text: "Ingot")),
            MinecraftStep(name: "Open the Survival inventory", action: .tapUntilText(x: 0.69, y: 0.90, fallbackX: 0.71, fallbackY: 0.91, text: "Crafting")),
            MinecraftStep(name: "Confirm the Survival inventory is open", action: .assertText("Crafting")),
            MinecraftStep(name: "Open the Armor tab", action: .tap(x: 0.945, y: 0.745)),
            MinecraftStep(name: "Confirm the Armor tab is open", action: .assertText("Armor")),
            // Drag, not tap: taps never lift from hotbar slot 1 in this
            // screen (confirmed live across repeated runs), while the slow
            // press-drag-release moves the item regardless of selection.
            MinecraftStep(name: "Drag the crafted Redstone Boots to the feet slot", action: .drag(x: layout.hotbarSlot(1).x, y: layout.hotbarSlot(1).y, endX: 0.552, endY: 0.616)),
            MinecraftStep(name: "Place the boots into the feet armor slot and confirm", action: .tapUntilPixels(x: 0.552, y: 0.616, fallbackX: 0.552, fallbackY: 0.616, expectation: .redCluster(xRange: 0.52...0.585, yRange: 0.55...0.68, minimumCount: 1150))),
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
                        .init(searchText: "redstone ingot", resultColumn: 1, destinations: [.topLeft, .topCenter, .topRight, .middleLeft, .middleRight])
                    ],
                    beforePickupVerification: nil,
                    afterPickupVerification: .text("Food"),
                    outputDestination: slotAfterIngredientsReturn,
                    shouldResetTableAfterPickup: false
                )
            ],
            finalHotbarTap: nil
        )
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
}
