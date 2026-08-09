import XCTest

final class MinecraftE2EHarness {
    private let testCase: XCTestCase
    private let minecraftBundleID = "com.mojang.minecraftpe"
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

        let console = MinecraftDebuggerConsole(
            app: minecraft,
            executor: executor,
            resolve: { self.resolved($0, scenario: scenario) },
            onScreenshot: { [testCase] in
                let label = "Debugger console checkpoint screenshot"
                testCase.attachScreenshot(label)
                return "Attached to the Xcode test report as '\(label)'."
            }
        )
        MinecraftDebuggerConsole.current = console
        testCase.addTeardownBlock { MinecraftDebuggerConsole.current = nil }

        let slices = try configuration.slices()

        // 1) Always bring Minecraft to the world list (shared prefix). This is
        // needed both to create a new world and to detect that one exists.
        for step in slices.prefix.phased(as: .config) {
            run(step, using: console)
        }

        // Device-side detection: after the prefix (Play + 8s wait) the world
        // list is visible. Use Vision OCR to see if "craftberry test" is
        // already present — this is the source of truth on device, since the
        // host's AFC probe env (CRAFTBERRY_E2E_REUSE_WORLD) does not propagate
        // to the XCTest process on the phone. The host probe remains useful
        // for logging, but we do not rely on it.
        let shouldReuse: Bool = {
            // Give the world list a moment to settle after the 8s wait.
            Thread.sleep(forTimeInterval: 1)
            testCase.attachScreenshot("World list for reuse detection")
            var recognized = ocr.recognizedText()
            print("[MinecraftE2EHarness] OCR for reuse detection: '\(recognized.prefix(500))'")
            if recognized.localizedCaseInsensitiveContains("craftberry") {
                print("[MinecraftE2EHarness] reuse detected (craftberry substring)")
                return true
            }
            // Retry with a short poll — OCR can be transiently empty right
            // after a navigation or world name may be on next page.
            if ocr.waitForRecognizedText("craftberry", timeout: 5) {
                print("[MinecraftE2EHarness] reuse detected on retry (craftberry)")
                return true
            }
            // One swipe up to reveal worlds below the fold, then check again.
            minecraft.swipeUp()
            Thread.sleep(forTimeInterval: 2)
            testCase.attachScreenshot("World list after swipe for reuse detection")
            recognized = ocr.recognizedText()
            print("[MinecraftE2EHarness] OCR after swipe: '\(recognized.prefix(500))'")
            if recognized.localizedCaseInsensitiveContains("craftberry") {
                print("[MinecraftE2EHarness] reuse detected after swipe")
                return true
            }
            let found = ocr.waitForRecognizedText("craftberry", timeout: 3)
            if found {
                print("[MinecraftE2EHarness] reuse detected after swipe retry")
            } else {
                print("[MinecraftE2EHarness] no existing world found via OCR — will create")
            }
            return found
        }()

        if !shouldReuse {
            for step in slices.creation.phased(as: .config) {
                run(step, using: console)
            }
        } else {
            testCase.attachScreenshot("Reusing existing craftberry test world — skipped world creation steps")
        }

        for step in slices.activation.phased(as: .config) {
            run(step, using: console)
        }
        for step in slices.staging.phased(as: .config) {
            run(step, using: console)
        }

        let craftingSteps = compiler.compile(scenario.craftingPlan)
        let phasedCraftingSteps = craftingSteps.phased(as: .crafting)
        for step in phasedCraftingSteps {
            run(step, using: console)
        }

        let cleanupSteps = MinecraftE2EStepSlices.postScenarioCleanup.phased(as: .config)
        for step in cleanupSteps {
            run(step, using: console)
        }
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

    /// Runs one phased step via the debugger console's before/after checkpoints, attaches the
    /// normal per-step screenshot, and converts a failed result into an XCTest failure — matching
    /// the pre-extraction behavior of recording a failure and continuing rather than aborting the
    /// run. `beforeStep` hits an `@inline(never)` checkpoint a human/agent can break on; if they
    /// ran or skipped the step from LLDB while paused there, its result comes back from
    /// `beforeStep` and `runCurrentStep` here is a no-op.
    private func run(_ step: MinecraftPhasedStep, using console: MinecraftDebuggerConsole) {
        let result = console.beforeStep(step) ?? console.runCurrentStep()
            ?? .failure(step, reason: "Step '\(step.name)' (\(step.id)) produced no result.")
        console.afterStep(result)
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


