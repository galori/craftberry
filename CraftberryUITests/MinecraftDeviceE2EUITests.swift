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

    func testCraftberryEmeraldSwordCanBeImportedActivatedAndCrafted() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try MinecraftE2EHarness(testCase: self).run(.emeraldSword)
        #endif
    }

    func testCraftberryRedstoneToolSetCanBeImportedActivatedAndCraftedIntoPickaxe() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try MinecraftE2EHarness(testCase: self).run(.redstoneToolSet)
        #endif
    }

    func testCraftberryRedstoneWeaponSetCanBeImportedActivatedAndCraftedIntoSpear() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try MinecraftE2EHarness(testCase: self).run(.redstoneWeaponSet)
        #endif
    }

    func testCraftberryRedstoneArmorSetCanBeImportedActivatedAndCraftedIntoBoots() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try MinecraftE2EHarness(testCase: self).run(.redstoneArmorSet)
        #endif
    }

    func testCraftberryRedstoneConsumableSetCanBeImportedActivatedAndCraftedIntoFood() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try MinecraftE2EHarness(testCase: self).run(.redstoneConsumableSet)
        #endif
    }

    func testCraftberryRedstoneBlockSetCanBeImportedActivatedAndCraftedIntoBlock() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try MinecraftE2EHarness(testCase: self).run(.redstoneBlockSet)
        #endif
    }

    func testCraftberryRedstoneSmithingSetCanBeImportedActivatedAndCraftedIntoIngot() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try MinecraftE2EHarness(testCase: self).run(.redstoneSmithingSet)
        #endif
    }

    func testCraftberryRedstoneFurnaceSetCanBeImportedActivatedAndCraftedIntoSword() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try MinecraftE2EHarness(testCase: self).run(.redstoneFurnaceSet)
        #endif
    }

    func testCraftberryRedstoneBrewingSetCanBeImportedActivatedAndCraftedIntoIngot() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try MinecraftE2EHarness(testCase: self).run(.redstoneBrewingSet)
        #endif
    }

    func testCraftberryRedstoneOreSetCanBeImportedActivatedAndCraftedIntoOre() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try MinecraftE2EHarness(testCase: self).run(.redstoneOreSet)
        #endif
    }

    func testCraftberryRedstoneCropSetCanBeImportedActivatedAndCraftedIntoSeeds() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try MinecraftE2EHarness(testCase: self).run(.redstoneCropSet)
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
                    afterPickupVerification: .text("Redstone"),
                    outputDestination: firstCraftSlot,
                    shouldResetTableAfterPickup: true
                ),
                .init(
                    outputName: "Redstone Pickaxe",
                    ingredients: [
                        .init(searchText: "redstone ingot", resultColumn: 1, destinations: [.topLeft, .topCenter, .topRight]),
                        .init(searchText: "stick", resultColumn: 3, destinations: [.middleCenter, .bottomCenter])
                    ],
                    beforePickupVerification: nil,
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
                    outputName: "Redstone Boots",
                    ingredients: [
                        .init(searchText: "redstone ingot", resultColumn: 1, destinations: [.topLeft, .topRight, .middleLeft, .middleRight])
                    ],
                    beforePickupVerification: nil,
                    afterPickupVerification: .text("Redstone"),
                    outputDestination: slotAfterIngredientsReturn,
                    shouldResetTableAfterPickup: false
                )
            ],
            finalHotbarTap: nil
        )
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
