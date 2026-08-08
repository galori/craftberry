import XCTest

final class MinecraftE2EHarness {
    private let testCase: XCTestCase
    private let minecraftBundleID = "com.mojang.minecraftpe"
    private let observationPauseEnvironmentKey = "MINECRAFT_E2E_OBSERVE_EACH_STEP"
    private let observationPauseSecondsEnvironmentKey = "MINECRAFT_E2E_OBSERVE_SECONDS"
    private let compiler = MinecraftCraftingPlanCompiler()
    private let commandKeyboard = MinecraftCommandKeyboard()
    private let ocr = MinecraftOCRInspector()
    private let pixels = MinecraftPixelInspector()

    init(testCase: XCTestCase) {
        self.testCase = testCase
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

        for (index, step) in configuration.steps.enumerated() {
            try execute(step, in: minecraft, scenario: scenario)
            observeIfRequested(afterStep: step.name, index: index + 1, total: configuration.steps.count, phase: "config")
        }

        let craftingSteps = compiler.compile(scenario.craftingPlan)
        for (index, step) in craftingSteps.enumerated() {
            try execute(step, in: minecraft, scenario: scenario)
            if !step.isPassiveObservation {
                observeIfRequested(afterStep: step.name, index: index + 1, total: craftingSteps.count, phase: "crafting")
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

    private func execute(_ step: MinecraftStep, in minecraft: XCUIApplication, scenario: MinecraftE2EScenario) throws {
        switch step.action {
        case .wait(let seconds):
            Thread.sleep(forTimeInterval: seconds)
        case .tap(let x, let y):
            minecraft.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
        case .drag(let x, let y, let endX, let endY):
            let start = minecraft.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
            let end = minecraft.coordinate(withNormalizedOffset: CGVector(dx: endX, dy: endY))
            // A fast synthesized flick (the previous plain press-then-drag) reads to Minecraft's
            // custom UI engine as a swipe-to-go-back gesture on some screens (confirmed live: it
            // silently bounced the Edit World pack-settings screen back to the world list instead
            // of scrolling). Slow velocity plus a brief hold at the end makes it land as a
            // deliberate scroll instead.
            start.press(forDuration: 0.2, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        case .swipeUp:
            minecraft.swipeUp()
        case .typeText(let text):
            minecraft.typeText(text)
        case .keyboardText(let text):
            for character in text {
                minecraft.keyboardKey(String(character)).tap()
            }
            minecraft.buttons["Done"].tap()
        case .numericKeyboardText(let text):
            let numericPlane = minecraft.keyboardKey("numbers")
            XCTAssertTrue(
                numericPlane.waitForExistence(timeout: 3),
                "Could not find the keyboard's numeric-plane switch, so \(step.name) would type into the letters plane."
            )
            numericPlane.tap()
            for character in text {
                minecraft.keyboardKey(String(character)).tap()
            }
            minecraft.buttons["Done"].tap()
        case .chatCommand(let text):
            sendChatCommand(text, in: minecraft)
        case .assertText(let rawExpected):
            let expected = resolved(rawExpected, scenario: scenario)
            XCTAssertTrue(
                ocr.waitForRecognizedText(expected, timeout: 5),
                "OCR did not find '\(expected)' after \(step.name). Recalibrate this step if Minecraft's UI changed."
            )
        case .assertPixels(let expectation):
            XCTAssertTrue(
                pixels.matches(expectation),
                "The expected pixel cluster was not visible after \(step.name)."
            )
        }
        testCase.attachScreenshot(step.name)
    }

    private func sendChatCommand(_ text: String, in minecraft: XCUIApplication) {
        minecraft.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.0325)).tap()
        Thread.sleep(forTimeInterval: 2)
        testCase.attachScreenshot("Chat screen after tapping the chat button")
        minecraft.coordinate(withNormalizedOffset: CGVector(dx: 0.495, dy: 0.935)).tap()
        Thread.sleep(forTimeInterval: 2)
        testCase.attachScreenshot("Chat screen after focusing the command input field")
        // The command keyboard drives raw key elements, so a missing keyboard here fails deep inside
        // key lookup with no indication of which tap missed. Check it up front instead.
        XCTAssertTrue(
            minecraft.keyboards.element.waitForExistence(timeout: 5),
            "The on-screen keyboard did not appear after focusing Minecraft's chat input, so the command could not be typed. Recalibrate the chat-input tap against the attached chat screenshots."
        )
        // Per-key taps rather than typeText: Minecraft's chat field is custom-drawn and never reports
        // keyboard focus to the accessibility layer, so typeText fails with "Neither element nor any
        // descendant has keyboard focus" even while the software keyboard is plainly up.
        commandKeyboard.type(text, in: minecraft)
        Thread.sleep(forTimeInterval: 1)
        testCase.attachScreenshot("Chat input after typing the command")
        minecraft.coordinate(withNormalizedOffset: CGVector(dx: 0.9275, dy: 0.434)).tap()
        Thread.sleep(forTimeInterval: 2)
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
