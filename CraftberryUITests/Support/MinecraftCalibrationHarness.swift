import XCTest

/// Shared setup for both the non-interactive `MinecraftE2EHarness` and the
/// interactive calibration server. The calibration path reuses the deterministic
/// Craftberry export/import/cold-launch sequence, then hands control to a
/// `MinecraftCalibrationServer` on port 8765 instead of auto-running the steps.
final class MinecraftCalibrationHarness {
    private let testCase: XCTestCase
    private let minecraftBundleID = "com.mojang.minecraftpe"
    private let compiler = MinecraftCraftingPlanCompiler()
    private let ocr = MinecraftOCRInspector()

    init(testCase: XCTestCase) {
        self.testCase = testCase
    }

    /// Performs Craftberry generation, export, Minecraft import, and cold launch,
    /// then starts the calibration TCP server and waits indefinitely for
    /// controller commands. This method never returns under normal operation; the
    /// caller (`scripts/minecraft-calibrate.sh stop`) terminates the test
    /// process externally.
    func runCalibration(_ scenario: MinecraftE2EScenario, breakAt target: String? = nil) throws {
        let configuration = try loadConfiguration()
        guard configuration.enabled else {
            throw XCTSkip("This is a physical-device calibration test. Calibrate and enable MinecraftDeviceE2EConfig.json before running it on the dedicated iPhone.")
        }

        let craftberry = XCUIApplication()
        craftberry.launchArguments = [
            "--ui-testing",
            scenario.launchArgument,
            "--ui-testing-fresh-pack-identity"
        ]
        craftberry.launch()
        XCTAssertTrue(testCase.waitForAppElement("craftberry.state.editing", in: craftberry, timeout: 8))

        let prompt = craftberry.textViews["craftberry.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.tap()
        prompt.typeText(scenario.prompt)

        try dismissKeyboard(in: craftberry)
        craftberry.buttons["craftberry.generate"].tap()
        XCTAssertTrue(testCase.waitForAppElement("craftberry.state.ready", in: craftberry, timeout: 8))
        XCTAssertTrue(
            craftberry.staticTexts[scenario.projectName].waitForExistence(timeout: 2),
            "The deterministic device fixture did not generate \(scenario.projectName)."
        )

        craftberry.buttons["craftberry.build"].tap()
        XCTAssertTrue(testCase.waitForAppElement("craftberry.state.built", in: craftberry, timeout: 10))
        craftberry.buttons["craftberry.export"].tap()
        testCase.attachScreenshot("Craftberry export share sheet")
        testCase.attachAccessibilityTree("Craftberry export share sheet", app: craftberry)
        try tapMinecraftShareDestination(in: craftberry)

        let minecraft = XCUIApplication(bundleIdentifier: minecraftBundleID)
        testCase.addTeardownBlock { [testCase] in
            minecraft.terminate()
            testCase.attachScreenshot("Minecraft terminated before AFC cleanup")
        }

        XCTAssertTrue(
            minecraft.wait(for: .runningForeground, timeout: 30),
            "Minecraft did not open after exporting the .mcaddon from Craftberry."
        )
        Thread.sleep(forTimeInterval: 5)
        testCase.attachScreenshot("Minecraft after importing Craftberry's \(scenario.projectName)")
        XCTAssertFalse(
            ocr.recognizedText().localizedCaseInsensitiveContains("Failed to import"),
            "Minecraft rejected Craftberry's exported add-on. Inspect the import screenshot and Content Log before calibrating world steps."
        )

        minecraft.terminate()
        Thread.sleep(forTimeInterval: 1)
        minecraft.launch()
        XCTAssertTrue(
            minecraft.wait(for: .runningForeground, timeout: 30),
            "Minecraft did not return to the foreground after the post-import cold launch."
        )
        Thread.sleep(forTimeInterval: 8)
        testCase.attachScreenshot("Minecraft cold launch after importing Craftberry's \(scenario.projectName)")

        // Build the calibration controller over the full phased plan.
        let executor = MinecraftStepExecutor(onIntermediateScreenshot: { [testCase] name in
            testCase.attachScreenshot(name)
        })
        let controller = MinecraftCalibrationController(
            scenario: scenario,
            configSteps: configuration.steps,
            craftingPlan: scenario.craftingPlan,
            compiler: compiler,
            app: minecraft,
            executor: executor,
            resolve: { self.resolved($0, scenario: scenario) }
        )

        // Optional break-at: run until just before target before exposing the server.
        if let target = target, !target.isEmpty {
            if let targetIndex = controller.allSteps.firstIndex(where: { $0.id == target || $0.name == target }) {
                while controller.cursor < targetIndex {
                    let step = controller.allSteps[controller.cursor]
                    // Use the controller's step handling so cursor/failure semantics match.
                    let request = MinecraftCalibrationRequest(command: "step")
                    let response = controller.handle(request)
                    if !response.success {
                        print("[CalibrationHarness] break-at pre-run failed at \(step.id): \(response.error ?? "unknown")")
                        break
                    }
                }
                print("[CalibrationHarness] break-at \(target) reached (cursor \(controller.cursor)/\(controller.allSteps.count))")
            } else {
                print("[CalibrationHarness] warning: break-at target '\(target)' not found; starting at beginning")
            }
        }

        let server = MinecraftCalibrationServer(controller: controller)
        do {
            try server.start()
            print("[CalibrationHarness] calibration server listening on 8765 for scenario \(scenario.launchArgument)")
        } catch {
            XCTFail("Failed to start calibration server: \(error)")
            return
        }
        testCase.addTeardownBlock { server.stop() }

        // Keep the test alive indefinitely. `scripts/minecraft-calibrate.sh stop`
        // terminates the xcodebuild process; until then we must not return.
        print("[CalibrationHarness] waiting indefinitely for controller commands (scenario \(scenario.launchArgument))")
        // RunLoop keeps the process responsive to NWListener callbacks while blocking return.
        RunLoop.current.run()
    }

    private func dismissKeyboard(in app: XCUIApplication) throws {
        guard app.keyboards.element.exists else { return }
        let doneButton = app.buttons["craftberry.dismissKeyboard"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 3), "Expected the keyboard's Done button to exist while the prompt field is focused.")
        doneButton.tap()
        XCTAssertFalse(
            app.keyboards.element.exists,
            "The on-screen keyboard did not dismiss after tapping Done; it may still be covering the Generate button."
        )
    }

    private func tapMinecraftShareDestination(in app: XCUIApplication) throws {
        let label = NSPredicate(format: "label == %@", "Minecraft")
        let candidates = [
            app.buttons.matching(label).firstMatch,
            app.collectionViews.buttons.matching(label).firstMatch,
            app.icons.matching(label).firstMatch,
            app.images.matching(label).firstMatch,
            app.otherElements.matching(label).firstMatch,
            app.staticTexts.matching(label).firstMatch
        ]

        let deadline = Date().addingTimeInterval(12)
        repeat {
            for candidate in candidates where candidate.exists && candidate.isHittable {
                candidate.tap()
                return
            }
            usleep(200_000)
        } while Date() < deadline

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.385, dy: 0.460)).tap()
    }

    private func loadConfiguration() throws -> MinecraftE2EConfiguration {
        guard let url = Bundle(for: MinecraftDeviceE2EUITests.self).url(forResource: "MinecraftDeviceE2EConfig", withExtension: "json") else {
            throw MinecraftE2EError.missingResource
        }
        return try JSONDecoder().decode(MinecraftE2EConfiguration.self, from: Data(contentsOf: url))
    }

    private func resolved(_ text: String, scenario: MinecraftE2EScenario) -> String {
        switch text {
        case "$EXPECTED_BEHAVIOR_PACK": scenario.behaviorPackName
        case "$EXPECTED_RESOURCE_PACK": scenario.resourcePackName
        case "$EXPECTED_CRAFTED_ITEM_NAME": scenario.expectedCraftedItemName
        default: text
        }
    }
}
