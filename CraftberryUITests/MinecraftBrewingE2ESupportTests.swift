import XCTest

final class MinecraftBrewingE2ESupportTests: XCTestCase {
    func testBrewingAcceptancePlanCoversBothRecipesAndCollectsVisibleOutputs() throws {
        let scenario = MinecraftE2EScenario.craftberryBrewingVerification
        let steps = scenario.postCraftingSteps
        let commands = steps.compactMap { step -> String? in
            guard case .chatCommand(let command) = step.action else { return nil }
            return command
        }

        XCTAssertEqual(scenario.launchArgument, MinecraftBrewingAcceptanceFixture.launchArgument)
        XCTAssertTrue(commands.contains("/setblock 98 80 95 brewing_stand"))
        XCTAssertTrue(commands.contains("/give @s potion 1 0"))
        XCTAssertTrue(commands.contains("/give @s blaze_powder 1"))
        XCTAssertTrue(commands.contains("/give @s gunpowder 1"))

        let names = steps.map(\.name)
        let elixirName = MinecraftBrewingAcceptanceFixture.elixirName
        let ingotName = MinecraftBrewingAcceptanceFixture.ingotName
        let openStand = try XCTUnwrap(names.firstIndex(of: "Open the brewing stand for the elixir recipe"))
        let elixirBrew = try XCTUnwrap(names.firstIndex(of: "Wait for the \(elixirName) brew to finish"))
        let collectElixir = try XCTUnwrap(names.firstIndex(of: "Collect the \(elixirName) from the bottle slot"))
        let verifyElixir = try XCTUnwrap(names.firstIndex(of: "Confirm the collected \(elixirName)"))
        let openContainer = try XCTUnwrap(names.firstIndex(of: "Reopen the brewing stand for the container recipe"))
        let splashBrew = try XCTUnwrap(names.firstIndex(of: "Wait for the splash container recipe to finish"))
        let collectSplash = try XCTUnwrap(names.firstIndex(of: "Collect the Splash Potion from the bottle slot"))
        let verifySplash = try XCTUnwrap(names.firstIndex(of: "Confirm the collected Splash Potion"))

        XCTAssertLessThan(openStand, verifyElixir)
        XCTAssertLessThan(elixirBrew, collectElixir)
        XCTAssertLessThan(collectElixir, verifyElixir)
        XCTAssertLessThan(verifyElixir, openContainer)
        XCTAssertLessThan(splashBrew, collectSplash)
        XCTAssertLessThan(collectSplash, verifySplash)
        XCTAssertLessThan(openContainer, verifySplash)
        XCTAssertEqual(scenario.craftingPlan.recipes.first?.outputName, ingotName)
        XCTAssertEqual(steps[verifyElixir].action, .assertText(elixirName))
        XCTAssertEqual(steps[verifySplash].action, .assertText("Splash Potion"))
        XCTAssertEqual(steps.filter { $0.action == .wait(seconds: 25) }.count, 2, "The plan should let the stand finish each brew before collecting its output.")
    }

    func testUncalibratedBrewingPlanStopsAtEveryUnmeasuredTouchTarget() {
        let steps = MinecraftBrewingAcceptancePlan.make(layout: .uncalibrated)
        let stops = steps.compactMap { step -> String? in
            guard case .calibrationRequired(let reason) = step.action else { return nil }
            return reason
        }

        XCTAssertTrue(stops.contains { $0.localizedCaseInsensitiveContains("stand world tap") })
        XCTAssertTrue(stops.contains { $0.localizedCaseInsensitiveContains("fuel slot") })
        XCTAssertTrue(stops.contains { $0.localizedCaseInsensitiveContains("reagent slot") })
        XCTAssertTrue(stops.contains { $0.localizedCaseInsensitiveContains("bottle slot") })
        XCTAssertTrue(stops.contains { $0.localizedCaseInsensitiveContains("output slot") })
        XCTAssertTrue(stops.contains { $0.localizedCaseInsensitiveContains("hotbar slot") })
        XCTAssertTrue(steps.contains { $0.name == "Confirm the brewing stand screen is open" && $0.action == .assertText("Brewing Stand") })
        XCTAssertTrue(steps.contains { $0.name == "Confirm the container-recipe stand screen is open" && $0.action == .assertText("Brewing Stand") })
    }

    func testBrewingScenarioCalibratesStandWorldTap() {
        let steps = MinecraftE2EScenario.craftberryBrewingVerification.postCraftingSteps
        let opens = steps.filter { $0.name == "Open the brewing stand for the elixir recipe" || $0.name == "Reopen the brewing stand for the container recipe" }
        XCTAssertEqual(opens.count, 2)
        for step in opens {
            guard case .tap(let x, let y) = step.action else {
                return XCTFail("\(step.name) must be a calibrated tap, not \(step.action).")
            }
            XCTAssertEqual(x, 0.72, accuracy: 0.001)
            XCTAssertEqual(y, 0.47, accuracy: 0.001)
        }
    }

    func testBrewingPlanReusesOnlyTheExistingGeneratedIngotRecipe() {
        let scenario = MinecraftE2EScenario.craftberryBrewingVerification

        XCTAssertEqual(scenario.craftingPlan.recipes.map(\.outputName), [MinecraftBrewingAcceptanceFixture.ingotName])
        XCTAssertEqual(scenario.craftingPlan.recipes[0].ingredients[0].searchText, "redstone")
        XCTAssertEqual(scenario.craftingPlan.recipes[0].ingredients[0].destinations, [.topLeft, .topCenter, .middleLeft, .middleCenter])
    }

    func testBrewingWorldUsesUniqueNameAndModeQualifiedImportedRowMatch() throws {
        let scenario = MinecraftE2EScenario.craftberryBrewingVerification
        let importedWorldName = MinecraftE2EWorldNaming.name(for: scenario, gameMode: .creative)
        let rowTap = MinecraftE2EWorldNaming.rowTap(for: scenario, gameMode: .creative)

        XCTAssertEqual(scenario.launchArgument, MinecraftBrewingAcceptanceFixture.launchArgument)
        XCTAssertEqual(importedWorldName, "Craftberry Brewing E2E (Creative)")
        XCTAssertNotEqual(importedWorldName, "Azure (Survival)")
        XCTAssertNotEqual(importedWorldName, "craftberry test")
        guard case .tapTextRowWithContext(let x, let title, let context) = rowTap.action else {
            return XCTFail("Imported-world selection must match both the fixture title and selected game mode.")
        }
        XCTAssertEqual(x, 0.16)
        XCTAssertEqual(title, "Craftberry Brewing E2E")
        XCTAssertEqual(context, "Creative")
    }

    func testImportedWorldOCRRequiresTitleAndModeToShareOneRow() {
        let candidates: [(text: String, boundingBox: CGRect)] = [
            ("Craftberry Brewing E2E", CGRect(x: 0.1, y: 0.69, width: 0.5, height: 0.07)),
            ("Creative", CGRect(x: 0.1, y: 0.6, width: 0.2, height: 0.05)),
            ("Craftberry Brewing E2E", CGRect(x: 0.1, y: 0.29, width: 0.5, height: 0.07)),
            ("Survival", CGRect(x: 0.1, y: 0.2, width: 0.2, height: 0.05))
        ]

        let creativeRow = MinecraftOCRInspector.matchingRowBoundingBox(
            title: "Craftberry Brewing E2E",
            context: "Creative",
            among: candidates
        )
        let survivalRow = MinecraftOCRInspector.matchingRowBoundingBox(
            title: "Craftberry Brewing E2E",
            context: "Survival",
            among: candidates
        )

        XCTAssertEqual(creativeRow, candidates[0].boundingBox)
        XCTAssertEqual(survivalRow, candidates[2].boundingBox)
        XCTAssertNil(
            MinecraftOCRInspector.matchingRowBoundingBox(title: "Craftberry Brewing E2E", context: "Adventure", among: candidates)
        )
        XCTAssertNil(
            MinecraftOCRInspector.matchingRowBoundingBox(
                title: "Craftberry Brewing E2E",
                context: "Creative",
                among: [
                    ("Craftberry Brewing E2E", CGRect(x: 0.1, y: 0.5, width: 0.5, height: 0.07)),
                    ("CreativePlus", CGRect(x: 0.1, y: 0.41, width: 0.2, height: 0.05))
                ]
            ),
            "A substring inside another mode label must not count as the Creative game mode."
        )
    }
}
