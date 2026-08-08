import XCTest

final class MinecraftE2EHarness {
    private let testCase: XCTestCase
    private let minecraftBundleID = "com.mojang.minecraftpe"
    private let observationPauseEnvironmentKey = "MINECRAFT_E2E_OBSERVE_EACH_STEP"
    private let observationPauseSecondsEnvironmentKey = "MINECRAFT_E2E_OBSERVE_SECONDS"
    private let compiler = MinecraftCraftingPlanCompiler()
    private let ocr = MinecraftOCRInspector()
    private let executor: MinecraftStepExecutor

    init(testCase: XCTestCase) {
        self.testCase = testCase
        self.executor = MinecraftStepExecutor(onIntermediateScreenshot: { [testCase] name in
            testCase.attachScreenshot(name)
        })
    }

    func run(_ scenario: MinecraftE2EScenario) throws {
        let configuration = try loadConfiguration()
        guard configuration.enabled else {
            throw XCTSkip("This is a physical-device acceptance test. Calibrate and enable MinecraftDeviceE2EConfig.json before running it on the dedicated iPhone.")
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

        let phasedConfigSteps = configuration.steps.phased(as: .config)
        for (index, step) in phasedConfigSteps.enumerated() {
            run(step, in: minecraft, scenario: scenario)
            observeIfRequested(afterStep: step.name, index: index + 1, total: phasedConfigSteps.count, phase: "config")
        }

        let craftingSteps = compiler.compile(scenario.craftingPlan)
        let phasedCraftingSteps = craftingSteps.phased(as: .crafting)
        for (index, step) in phasedCraftingSteps.enumerated() {
            run(step, in: minecraft, scenario: scenario)
            if !craftingSteps[index].isPassiveObservation {
                observeIfRequested(afterStep: step.name, index: index + 1, total: phasedCraftingSteps.count, phase: "crafting")
            }
        }
    }

    /// When `MINECRAFT_E2E_OBSERVE_EACH_STEP=1`, pauses after every step (config and crafting)
    /// so an operator watching the physical device can confirm each step landed correctly before
    /// the run continues. This is a fixed-duration pause, not a real block on operator input — the
    /// on-device test-runner process has no live channel back to the Mac to wait on mid-run — but
    /// printing a clear marker before each pause (surfaced immediately via a log-tailing Monitor)
    /// gives near-real-time visibility into exactly which step just ran, which is what actually
    /// matters for calibrating fast instead of only diagnosing from a completed run's failure.
    /// Pause length defaults to 15s and is configurable via `MINECRAFT_E2E_OBSERVE_SECONDS`.
    private func observeIfRequested(afterStep name: String, index: Int, total: Int, phase: String) {
        guard ProcessInfo.processInfo.environment[observationPauseEnvironmentKey] == "1" else { return }
        let seconds = ProcessInfo.processInfo.environment[observationPauseSecondsEnvironmentKey]
            .flatMap(TimeInterval.init) ?? 15
        print("CRAFTBERRY_E2E_STEP [\(phase) \(index)/\(total)]: \(name) — pausing \(Int(seconds))s")
        Thread.sleep(forTimeInterval: seconds)
    }

    /// The keyboard toolbar's Done button (`craftberry.dismissKeyboard`) resigns the prompt text
    /// editor's focus. Dismissal matters because the on-screen keyboard otherwise overlaps and
    /// intercepts taps on the Generate button (both sit at the bottom of the screen) — confirmed
    /// on a physical device/iOS version where backgrounding and reactivating the app did not
    /// reliably resign focus on its own. Fail loudly rather than tap Generate while occluded,
    /// which would silently mistap the keyboard and hang waiting for a state transition that
    /// never happens.
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

    /// Runs one phased step through `MinecraftStepExecutor`, attaches the normal per-step
    /// screenshot, and converts a failed result into an XCTest failure — matching the executor's
    /// pre-extraction behavior of recording a failure and continuing rather than aborting the run.
    private func run(_ step: MinecraftPhasedStep, in minecraft: XCUIApplication, scenario: MinecraftE2EScenario) {
        let result = executor.execute(step, in: minecraft, resolve: { self.resolved($0, scenario: scenario) })
        testCase.attachScreenshot(step.name)
        if !result.succeeded {
            XCTFail(result.failureReason ?? "Step '\(step.name)' (\(step.id)) failed with no reason.")
        }
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

private extension MinecraftStep {
    var isPassiveObservation: Bool {
        switch action {
        case .wait, .assertText, .assertPixels:
            true
        default:
            false
        }
    }
}
