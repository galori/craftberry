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
          {"name":"Pixels", "action":"redstonePickaxeOutput"},
          {"name":"Layout-aware tab", "action":"tapUntilText", "x":0.5, "y":0.167, "fallbackX":0.5, "fallbackY":0.31, "text":"Redstone Behavior"}
        ]
        """#.utf8)

        let steps = try JSONDecoder().decode([MinecraftStep].self, from: data)

        XCTAssertEqual(steps[0].action, .tap(x: 0.1, y: 0.2))
        XCTAssertEqual(steps[1].action, .drag(x: 0.7, y: 0.85, endX: 0.7, endY: 0.25))
        XCTAssertEqual(steps[2].action, .keyboardText("emerald"))
        XCTAssertEqual(steps[3].action, .chatCommand("/tp @s 1 2 3"))
        XCTAssertEqual(steps[4].action, .assertText("Crafting"))
        XCTAssertEqual(steps[5].action, .assertPixels(.redstonePickaxeOutput))
        XCTAssertEqual(
            steps[6].action,
            .tapUntilText(x: 0.5, y: 0.167, fallbackX: 0.5, fallbackY: 0.31, text: "Redstone Behavior")
        )
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

    func testDeviceConfigurationClearsInventoryBeforeCrafting() throws {
        let configuration = try loadConfiguration()

        guard let clearIndex = configuration.steps.firstIndex(where: {
            $0.action == .chatCommand("/clear @s")
        }) else {
            return XCTFail("The device staging flow must clear the reused world's player inventory before crafting.")
        }
        let craftingTableIndex = try XCTUnwrap(configuration.steps.firstIndex {
            $0.name == "Open the crafting table directly in front of the player"
        })
        XCTAssertLessThan(clearIndex, craftingTableIndex)
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
        XCTAssertTrue(events.contains(.coordinate(0.1435, 0.7165)))
        XCTAssertTrue(events.contains(.coordinate(0.376, 0.7165)))
        XCTAssertTrue(events.contains(.coordinate(0.6225, 0.630)))

        let tableEvents = MinecraftCommandKeyboard().events(for: "crafting_table")
        let underscoreIndex = tableEvents.firstIndex(of: .coordinate(0.1435, 0.7165))!
        XCTAssertEqual(tableEvents[underscoreIndex + 2], .key("letters"))
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

    func testChatCommandRetriesOpeningChatBeforeTouchingTheCommandInput() {
        var tappedOffsets: [CGVector] = []
        var detectorCalls = 0
        var screenshots: [String] = []
        let executor = MinecraftStepExecutor(
            onIntermediateScreenshot: { screenshots.append($0) },
            wait: { _ in },
            tap: { _, offset in tappedOffsets.append(offset) },
            chatScreenDetector: { _ in
                detectorCalls += 1
                return false
            }
        )
        let step = MinecraftPhasedStep(id: "config:1", name: "Clear inventory", action: .chatCommand("/clear @s"))

        let result = executor.execute(step, in: XCUIApplication(), resolve: { $0 })

        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.failureReason?.contains("Chat and Commands") == true)
        XCTAssertEqual(detectorCalls, 3)
        XCTAssertEqual(tappedOffsets.count, 3)
        XCTAssertTrue(tappedOffsets.allSatisfy { $0.dx == 0.5 && $0.dy == 0.0325 })
        XCTAssertEqual(screenshots.count, 3)
        XCTAssertTrue(screenshots.allSatisfy { $0.contains("tapping the chat button") })
    }

    func testLayoutAwarePackTabTapUsesFallbackOnlyWhenExactPackTextIsAbsent() {
        var tappedOffsets: [CGVector] = []
        var recognitionAttempts = 0
        let executor = MinecraftStepExecutor(
            wait: { _ in },
            tap: { _, offset in tappedOffsets.append(offset) },
            recognizedText: { expected, _ in
                XCTAssertEqual(expected, "Redstone Behavior")
                recognitionAttempts += 1
                return recognitionAttempts == 2
            }
        )
        let step = MinecraftPhasedStep(
            id: "config:1",
            name: "Open Active Behavior Packs",
            action: .tapUntilText(x: 0.505, y: 0.167, fallbackX: 0.505, fallbackY: 0.31, text: "Redstone Behavior")
        )

        let result = executor.execute(step, in: XCUIApplication(), resolve: { $0 })

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(recognitionAttempts, 2)
        XCTAssertEqual(tappedOffsets.count, 2)
        XCTAssertEqual(tappedOffsets[0].dy, 0.167, accuracy: 0.001)
        XCTAssertEqual(tappedOffsets[1].dy, 0.31, accuracy: 0.001)
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

    private func makeTestSteps(count: Int) -> [MinecraftPhasedStep] {
        (1...count).map { i in
            let phase = i <= 3 ? "config" : "crafting"
            return MinecraftPhasedStep(id: "\(phase):\(i)", name: "Step \(i)", action: .wait(seconds: 0))
        }
    }

    private func makeController(
        steps: [MinecraftPhasedStep],
        failOnIds: Set<String> = [],
        screenshot: String? = "fake_base64",
        ocr: String? = "fake ocr"
    ) -> MinecraftCalibrationController {
        MinecraftCalibrationController(
            scenarioId: "--ui-testing-test",
            allSteps: steps,
            executePlanned: { step in
                if failOnIds.contains(step.id) || failOnIds.contains(step.name) {
                    return .failure(step, reason: "injected failure for \(step.id)")
                }
                return .success(step)
            },
            executeAdHoc: { action in
                let adHoc = MinecraftPhasedStep(id: "calibration:adhoc", name: "Ad hoc", action: action)
                if failOnIds.contains("adHoc") {
                    return .failure(adHoc, reason: "ad hoc failure")
                }
                return .success(adHoc)
            },
            screenshotBase64Provider: { screenshot },
            recognizedTextProvider: { ocr }
        )
    }

    // MARK: - Calibration protocol

    func testCalibrationProtocolCodingRoundTrips() throws {
        let request = MinecraftCalibrationRequest(command: "tap", target: "config:12", x: 0.5, y: 0.443, text: "hello", seconds: 1.5, ocr: true)
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(MinecraftCalibrationRequest.self, from: data)
        XCTAssertEqual(request, decoded)

        let response = MinecraftCalibrationResponse(
            success: true,
            scenario: "--ui-testing-emerald-sword",
            phase: "config",
            cursor: "config:3",
            completedCount: 2,
            totalCount: 10,
            currentStep: MinecraftCalibrationStepInfo(id: "config:3", name: "Tap", action: "tap(0.5, 0.443)"),
            nextStep: MinecraftCalibrationStepInfo(id: "config:4", name: "Wait", action: "wait(2.0)"),
            lastResult: MinecraftCalibrationResultInfo(stepId: "config:2", stepName: "Prev", succeeded: true),
            steps: [MinecraftCalibrationStepInfo(id: "config:1", name: "First", action: "wait(1.0)")],
            screenshotBase64: "abc123",
            recognizedText: "hello"
        )
        let rData = try JSONEncoder().encode(response)
        let rDecoded = try JSONDecoder().decode(MinecraftCalibrationResponse.self, from: rData)
        XCTAssertEqual(response, rDecoded)
    }

    func testCalibrationCursorAdvancementOnSuccess() {
        let steps = makeTestSteps(count: 4)
        let controller = makeController(steps: steps)

        XCTAssertEqual(controller.cursor, 0)
        XCTAssertEqual(controller.handle(MinecraftCalibrationRequest(command: "status")).cursor, "config:1")

        let first = controller.handle(MinecraftCalibrationRequest(command: "step"))
        XCTAssertTrue(first.success)
        XCTAssertEqual(controller.cursor, 1)
        XCTAssertEqual(first.cursor, "config:2")
        XCTAssertEqual(first.completedCount, 1)

        let second = controller.handle(MinecraftCalibrationRequest(command: "step"))
        XCTAssertTrue(second.success)
        XCTAssertEqual(controller.cursor, 2)
    }

    func testCalibrationFailureRetention() {
        let steps = makeTestSteps(count: 3)
        // Make second step fail
        let controller = makeController(steps: steps, failOnIds: ["config:2"])

        let first = controller.handle(MinecraftCalibrationRequest(command: "step"))
        XCTAssertTrue(first.success)
        XCTAssertEqual(controller.cursor, 1)

        let failed = controller.handle(MinecraftCalibrationRequest(command: "step"))
        XCTAssertFalse(failed.success)
        XCTAssertEqual(controller.cursor, 1, "Failed step must not advance cursor")
        XCTAssertEqual(failed.error, "injected failure for config:2")

        // Retry still fails and cursor stays
        let retry = controller.handle(MinecraftCalibrationRequest(command: "step"))
        XCTAssertFalse(retry.success)
        XCTAssertEqual(controller.cursor, 1)
    }

    func testCalibrationRunUntilStopsBeforeTarget() {
        let steps = makeTestSteps(count: 5)
        let controller = makeController(steps: steps)

        let result = controller.handle(MinecraftCalibrationRequest(command: "run_until", target: "crafting:4"))
        XCTAssertTrue(result.success)
        // Should run config:1, config:2, config:3 and stop before crafting:4 (index 3)
        XCTAssertEqual(controller.cursor, 3)
        XCTAssertEqual(result.cursor, "crafting:4")
    }

    func testCalibrationRunUntilStopsImmediatelyOnFailure() {
        let steps = makeTestSteps(count: 5)
        let controller = makeController(steps: steps, failOnIds: ["config:2"])

        let result = controller.handle(MinecraftCalibrationRequest(command: "run_until", target: "crafting:5"))
        XCTAssertFalse(result.success)
        // Ran config:1 successfully, then config:2 failed and stopped
        XCTAssertEqual(controller.cursor, 1)
        XCTAssertEqual(result.error, "injected failure for config:2")
    }

    func testCalibrationRunUntilByName() {
        let steps = makeTestSteps(count: 4)
        let controller = makeController(steps: steps)

        let result = controller.handle(MinecraftCalibrationRequest(command: "run_until", target: "Step 3"))
        XCTAssertTrue(result.success)
        XCTAssertEqual(controller.cursor, 2)
    }

    func testCalibrationArbitraryActionsNeverAdvanceCursor() {
        let steps = makeTestSteps(count: 3)
        let controller = makeController(steps: steps)
        let startCursor = controller.cursor

        let tap = controller.handle(MinecraftCalibrationRequest(command: "tap", x: 0.5, y: 0.443))
        XCTAssertTrue(tap.success)
        XCTAssertEqual(controller.cursor, startCursor)

        let drag = controller.handle(MinecraftCalibrationRequest(command: "drag", x: 0.1, y: 0.2, endX: 0.3, endY: 0.4))
        XCTAssertTrue(drag.success)
        XCTAssertEqual(controller.cursor, startCursor)

        let chat = controller.handle(MinecraftCalibrationRequest(command: "chat_command", text: "/tp @s 1 2 3"))
        XCTAssertTrue(chat.success)
        XCTAssertEqual(controller.cursor, startCursor)

        let kb = controller.handle(MinecraftCalibrationRequest(command: "keyboard_text", text: "emerald"))
        XCTAssertTrue(kb.success)
        XCTAssertEqual(controller.cursor, startCursor)

        let wait = controller.handle(MinecraftCalibrationRequest(command: "wait", seconds: 0.01))
        XCTAssertTrue(wait.success)
        XCTAssertEqual(controller.cursor, startCursor)
    }

    func testCalibrationMarkCompleteAdvancesWithoutExecuting() {
        let steps = makeTestSteps(count: 3)
        // Even if this step would fail, mark_complete should succeed and advance
        let controller = makeController(steps: steps, failOnIds: ["config:1"])

        let result = controller.handle(MinecraftCalibrationRequest(command: "mark_complete"))
        XCTAssertTrue(result.success)
        XCTAssertEqual(controller.cursor, 1)
        XCTAssertEqual(result.lastResult?.succeeded, true)
        XCTAssertEqual(result.cursor, "config:2")
    }

    func testCalibrationSelectStepMovesCursorOnly() {
        let steps = makeTestSteps(count: 5)
        let controller = makeController(steps: steps)

        // Advance two steps
        _ = controller.handle(MinecraftCalibrationRequest(command: "step"))
        _ = controller.handle(MinecraftCalibrationRequest(command: "step"))
        XCTAssertEqual(controller.cursor, 2)

        // Jump back
        let back = controller.handle(MinecraftCalibrationRequest(command: "select_step", target: "config:1"))
        XCTAssertTrue(back.success)
        XCTAssertEqual(controller.cursor, 0)
        XCTAssertEqual(back.cursor, "config:1")

        // Jump forward by name
        let forward = controller.handle(MinecraftCalibrationRequest(command: "select_step", target: "Step 5"))
        XCTAssertTrue(forward.success)
        XCTAssertEqual(controller.cursor, 4)
    }

    func testCalibrationSelectStepDoesNotRestoreUIState() {
        // Verifies explicit contract: select-step changes only cursor.
        let steps = makeTestSteps(count: 5)
        let controller = makeController(steps: steps)
        _ = controller.handle(MinecraftCalibrationRequest(command: "step"))
        let before = controller.cursor
        _ = controller.handle(MinecraftCalibrationRequest(command: "select_step", target: "crafting:4"))
        XCTAssertNotEqual(controller.cursor, before)
        // No execution should have happened; lastResult still reflects the earlier step
        XCTAssertEqual(controller.lastResult?.step.id, "config:1")
    }

    func testCalibrationReconnectSafeState() {
        // Controller state persists across multiple handle calls (simulating reconnects)
        let steps = makeTestSteps(count: 4)
        let controller = makeController(steps: steps)

        _ = controller.handle(MinecraftCalibrationRequest(command: "step"))
        _ = controller.handle(MinecraftCalibrationRequest(command: "tap", x: 0.1, y: 0.1))
        XCTAssertEqual(controller.cursor, 1, "Ad hoc tap must not change cursor")

        // New "connection" - same controller instance - sees updated cursor
        let status = controller.handle(MinecraftCalibrationRequest(command: "status"))
        XCTAssertEqual(status.cursor, "config:2")
        XCTAssertEqual(status.completedCount, 1)

        _ = controller.handle(MinecraftCalibrationRequest(command: "step"))
        XCTAssertEqual(controller.cursor, 2)
    }

    func testCalibrationMalformedJSONAndUnknownCommandReturnError() {
        // Malformed handling is server-level, but controller also returns error for unknown command
        let steps = makeTestSteps(count: 2)
        let controller = makeController(steps: steps)

        let unknown = controller.handle(MinecraftCalibrationRequest(command: "bogus"))
        XCTAssertFalse(unknown.success)
        XCTAssertNotNil(unknown.error)

        let missingTarget = controller.handle(MinecraftCalibrationRequest(command: "run_until"))
        XCTAssertFalse(missingTarget.success)

        let unknownStep = controller.handle(MinecraftCalibrationRequest(command: "select_step", target: "does-not-exist"))
        XCTAssertFalse(unknownStep.success)
    }

    func testCalibrationListStepsReturnsAllPhasedIds() {
        let steps = makeTestSteps(count: 5)
        let controller = makeController(steps: steps)
        let resp = controller.handle(MinecraftCalibrationRequest(command: "list_steps"))
        XCTAssertTrue(resp.success)
        XCTAssertEqual(resp.steps?.count, 5)
        XCTAssertEqual(resp.steps?.first?.id, "config:1")
        XCTAssertEqual(resp.steps?.last?.id, "crafting:5")
    }

    func testPixelExpectationMatchesSyntheticPositiveAndNegativeImages() throws {
        let inspector = MinecraftPixelInspector()
        let expectation = MinecraftPixelExpectation.redCluster(xRange: 0.2...0.3, yRange: 0.2...0.3, minimumCount: 4)

        XCTAssertTrue(inspector.matches(expectation, in: try syntheticImage(redCluster: true)))
        XCTAssertFalse(inspector.matches(expectation, in: try syntheticImage(redCluster: false)))
    }

    func testRedstonePickaxePixelExpectationMatchesOutputCluster() throws {
        let inspector = MinecraftPixelInspector()
        let image = try syntheticImage(
            width: 100,
            height: 100,
            redRect: CGRect(x: 68, y: 66, width: 8, height: 8)
        )

        XCTAssertTrue(inspector.matches(.redstonePickaxeOutput, in: image))
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
        try syntheticImage(
            width: 20,
            height: 20,
            redRect: redCluster ? CGRect(x: 4, y: 4, width: 4, height: 6) : nil
        )
    }

    private func syntheticImage(width: Int, height: Int, redRect: CGRect?) throws -> CGImage {
        var bytes = Array(repeating: UInt8(0), count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = ((y * width) + x) * 4
                bytes[offset] = redRect?.contains(CGPoint(x: x, y: y)) == true ? 255 : 20
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
