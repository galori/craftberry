import ImageIO
import XCTest

final class MinecraftE2ESupportTests: XCTestCase {
    func testTypedJSONDecodingMapsLegacyActions() throws {
        let data = Data(#"""
        [
          {"name":"Tap", "action":"tap", "x":0.1, "y":0.2},
          {"name":"Drag", "action":"drag", "x":0.7, "y":0.85, "endX":0.7, "endY":0.25},
          {"name":"Key", "action":"keyText", "text":"emerald"},
          {"name":"Command", "action":"chatCommand", "text":"/tp @s 1 2 3"},
          {"name":"OCR", "action":"ocr", "text":"Crafting"},
          {"name":"Pixels", "action":"redstonePickaxeOutput"}
        ]
        """#.utf8)

        let steps = try JSONDecoder().decode([MinecraftStep].self, from: data)

        XCTAssertEqual(steps[0].action, .tap(x: 0.1, y: 0.2))
        XCTAssertEqual(steps[1].action, .drag(x: 0.7, y: 0.85, endX: 0.7, endY: 0.25))
        XCTAssertEqual(steps[2].action, .keyboardText("emerald"))
        XCTAssertEqual(steps[3].action, .chatCommand("/tp @s 1 2 3"))
        XCTAssertEqual(steps[4].action, .assertText("Crafting"))
        XCTAssertEqual(steps[5].action, .assertPixels(.redstonePickaxeOutput))
    }

    func testMalformedPayloadIsRejected() {
        let data = Data(#"{"name":"Broken tap","action":"tap","x":0.1}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(MinecraftStep.self, from: data))
    }

    func testDeviceConfigurationEndsAtCraftingTableBoundary() throws {
        let configuration = try loadConfiguration()

        XCTAssertEqual(configuration.steps.last?.name, "Confirm the crafting table interface is open")
        XCTAssertNil(configuration.steps.first { step in
            step.name.localizedCaseInsensitiveContains("emerald")
                || step.name.localizedCaseInsensitiveContains("redstone ingot")
                || step.name.localizedCaseInsensitiveContains("crafted sword")
        })
    }

    func testCalibratedLayoutKeepsCreativeResultColumnsAndNamedCraftingSlots() {
        let layout = MinecraftCalibratedLayout()

        XCTAssertEqual(layout.creativeResult(column: 1).x, 0.143, accuracy: 0.001)
        XCTAssertEqual(layout.creativeResult(column: 3).x, 0.253, accuracy: 0.001)
        XCTAssertEqual(layout.creativeResult(column: 4).x, 0.308, accuracy: 0.001)

        let expected: [(MinecraftCraftingSlot, CGFloat, CGFloat)] = [
            (.topLeft, 0.654, 0.160), (.topCenter, 0.709, 0.160), (.topRight, 0.764, 0.160),
            (.middleLeft, 0.654, 0.280), (.middleCenter, 0.709, 0.280), (.middleRight, 0.764, 0.280),
            (.bottomLeft, 0.654, 0.400), (.bottomCenter, 0.709, 0.400), (.bottomRight, 0.764, 0.400)
        ]
        for (slot, x, y) in expected {
            XCTAssertEqual(layout.craftingSlot(slot).x, x, accuracy: 0.001)
            XCTAssertEqual(layout.craftingSlot(slot).y, y, accuracy: 0.001)
        }
    }

    func testEmeraldPlanPreservesIngredientOrderAndFinalEquip() {
        let steps = MinecraftCraftingPlanCompiler().compile(MinecraftE2EScenario.emeraldSword.craftingPlan)
        let names = steps.map(\.name)

        XCTAssertLessThan(names.firstIndex(of: "Type emerald search")!, names.firstIndex(of: "Type stick search")!)
        assertTap(named: "Place emerald in top-center recipe slot", in: steps, x: 0.709, y: 0.160)
        assertTap(named: "Place emerald in middle-center recipe slot", in: steps, x: 0.709, y: 0.280)
        assertTap(named: "Place stick in bottom-center recipe slot", in: steps, x: 0.709, y: 0.400)
        XCTAssertLessThan(names.firstIndex(of: "Take Emerald Test Sword output")!, names.firstIndex(of: "Confirm crafted Emerald Test Sword")!)
        XCTAssertEqual(steps.last?.name, "Select crafted Emerald Test Sword in the HUD hotbar")
    }

    func testRedstonePlanResetsBetweenRecipesAndVerifiesPixelsBeforePickup() {
        let steps = MinecraftCraftingPlanCompiler().compile(MinecraftE2EScenario.redstoneToolSet.craftingPlan)
        let names = steps.map(\.name)

        assertTap(named: "Pick first redstone ingot stack", in: steps, x: 0.143, y: 0.25)
        assertTap(named: "Place redstone ingot in top-right recipe slot", in: steps, x: 0.764, y: 0.160)
        assertTap(named: "Place stick in bottom-center recipe slot", in: steps, x: 0.709, y: 0.400)

        let resetIndex = names.firstIndex(of: "Close crafting table to return recipe inputs")!
        XCTAssertEqual(names[resetIndex + 1], "Wait for leftover recipe inputs to return to inventory")
        XCTAssertEqual(names[resetIndex + 2], "Reopen crafting table for the next recipe")
        XCTAssertEqual(names[resetIndex + 4], "Confirm crafting table reopened for the next recipe")
        XCTAssertLessThan(
            names.firstIndex(of: "Clear redstone ingot search")!,
            names.firstIndex(of: "Type redstone ingot search")!
        )

        XCTAssertLessThan(
            names.firstIndex(of: "Confirm Redstone Pickaxe output is visible")!,
            names.firstIndex(of: "Take Redstone Pickaxe output")!
        )
        XCTAssertEqual(steps.last?.name, "Wait for the creative HUD")
    }

    func testCommandKeyboardPlanningCoversLettersNumbersSymbolsSpacesAndDeadKeys() {
        let events = MinecraftCommandKeyboard().events(for: "/tp @s 100 80 95_~^")

        XCTAssertTrue(events.contains(.key("numbers")))
        XCTAssertTrue(events.contains(.key("/")))
        XCTAssertTrue(events.contains(.key("t")))
        XCTAssertTrue(events.contains(.key("p")))
        XCTAssertTrue(events.contains(.key("space")))
        XCTAssertTrue(events.contains(.key("@")))
        XCTAssertTrue(events.contains(.key("1")))
        XCTAssertTrue(events.contains(.key("_")))
        XCTAssertTrue(events.contains(.coordinate(0.376, 0.7165)))
        XCTAssertTrue(events.contains(.coordinate(0.6225, 0.630)))
    }

    func testPhasedStepsGetStableRunLocalIDsStartingAtOnePerPhase() {
        let steps = [
            MinecraftStep(name: "First", action: .wait(seconds: 1)),
            MinecraftStep(name: "Second", action: .swipeUp),
            MinecraftStep(name: "Third", action: .typeText("hi"))
        ]

        let configSteps = steps.phased(as: .config)
        let craftingSteps = steps.phased(as: .crafting)

        XCTAssertEqual(configSteps.map(\.id), ["config:1", "config:2", "config:3"])
        XCTAssertEqual(craftingSteps.map(\.id), ["crafting:1", "crafting:2", "crafting:3"])
        XCTAssertEqual(configSteps.map(\.name), steps.map(\.name))
        XCTAssertEqual(configSteps.map(\.action), steps.map(\.action))
    }

    func testStepResultCarriesFailureReasonOnlyWhenFailed() {
        let step = MinecraftPhasedStep(id: "config:1", name: "Tap something", action: .swipeUp)

        let success = MinecraftStepResult.success(step)
        XCTAssertTrue(success.succeeded)
        XCTAssertNil(success.failureReason)

        let failure = MinecraftStepResult.failure(step, reason: "did not land")
        XCTAssertFalse(failure.succeeded)
        XCTAssertEqual(failure.failureReason, "did not land")
    }

    func testExecutorRunsAWaitStepWithoutRequiringAnyAppInteraction() {
        let executor = MinecraftStepExecutor()
        let step = MinecraftPhasedStep(id: "config:1", name: "Brief wait", action: .wait(seconds: 0))

        let result = executor.execute(step, in: XCUIApplication(), resolve: { $0 })

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.step, step)
    }

    func testDebuggerConsoleRunCurrentStepExecutesOnceAndPreventsDuplicateExecution() {
        let console = makeDebuggerConsole()
        let step = MinecraftPhasedStep(id: "config:1", name: "Wait", action: .wait(seconds: 0))

        XCTAssertNil(console.beforeStep(step), "Nothing ran the step during the checkpoint, so the harness should be told to run it itself.")
        XCTAssertFalse(console.isCurrentStepExecuted)

        let first = console.runCurrentStep()
        XCTAssertEqual(first?.succeeded, true)
        XCTAssertTrue(console.isCurrentStepExecuted)

        XCTAssertNil(console.runCurrentStep(), "Running an already-executed step again must be a no-op.")
    }

    func testDebuggerConsoleSkipCurrentStepMarksExecutedWithoutRunningIt() {
        let console = makeDebuggerConsole()
        let step = MinecraftPhasedStep(id: "config:1", name: "Long wait", action: .wait(seconds: 999))
        _ = console.beforeStep(step)

        console.skipCurrentStep()

        XCTAssertTrue(console.isCurrentStepExecuted)
        XCTAssertEqual(console.lastResult?.succeeded, true)
        XCTAssertNil(console.runCurrentStep(), "A skipped step must not also run.")
    }

    func testDebuggerConsoleResetsExecutionStateForEachNewStep() {
        let console = makeDebuggerConsole()
        let first = MinecraftPhasedStep(id: "config:1", name: "First", action: .wait(seconds: 0))
        _ = console.beforeStep(first)
        console.skipCurrentStep()
        XCTAssertTrue(console.isCurrentStepExecuted)

        let second = MinecraftPhasedStep(id: "config:2", name: "Second", action: .wait(seconds: 0))
        XCTAssertNil(console.beforeStep(second), "A fresh step must not inherit the previous step's executed state.")
        XCTAssertEqual(console.currentStep?.id, second.id)
        XCTAssertFalse(console.isCurrentStepExecuted)
    }

    func testDebuggerConsoleAdHocWaitDoesNotAdvanceTheCurrentStep() {
        let console = makeDebuggerConsole()
        let step = MinecraftPhasedStep(id: "config:1", name: "Wait", action: .wait(seconds: 0))
        _ = console.beforeStep(step)

        console.wait(0)

        XCTAssertFalse(console.isCurrentStepExecuted, "An arbitrary console command must not mark the planned step as executed.")
        XCTAssertNotNil(console.runCurrentStep(), "The planned step must still be runnable after an ad hoc command.")
    }

    private func makeDebuggerConsole() -> MinecraftDebuggerConsole {
        MinecraftDebuggerConsole(
            app: XCUIApplication(),
            executor: MinecraftStepExecutor(),
            resolve: { $0 },
            onScreenshot: { "" }
        )
    }

    func testPixelExpectationMatchesSyntheticPositiveAndNegativeImages() throws {
        let inspector = MinecraftPixelInspector()
        let expectation = MinecraftPixelExpectation.redCluster(xRange: 0.2...0.3, yRange: 0.2...0.3, minimumCount: 4)

        XCTAssertTrue(inspector.matches(expectation, in: try syntheticImage(redCluster: true)))
        XCTAssertFalse(inspector.matches(expectation, in: try syntheticImage(redCluster: false)))
    }

    private func assertTap(named name: String, in steps: [MinecraftStep], x: CGFloat, y: CGFloat) {
        guard case .tap(let actualX, let actualY) = steps.first(where: { $0.name == name })?.action else {
            XCTFail("Expected tap step named \(name)")
            return
        }
        XCTAssertEqual(actualX, x, accuracy: 0.001)
        XCTAssertEqual(actualY, y, accuracy: 0.001)
    }

    private func loadConfiguration() throws -> MinecraftE2EConfiguration {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "MinecraftDeviceE2EConfig", withExtension: "json"))
        return try JSONDecoder().decode(MinecraftE2EConfiguration.self, from: Data(contentsOf: url))
    }

    private func syntheticImage(redCluster: Bool) throws -> CGImage {
        let width = 20
        let height = 20
        var bytes = Array(repeating: UInt8(0), count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = ((y * width) + x) * 4
                bytes[offset] = redCluster && (4...7).contains(x) && (4...9).contains(y) ? 255 : 20
                bytes[offset + 1] = 20
                bytes[offset + 2] = 20
                bytes[offset + 3] = 255
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
    }
}
