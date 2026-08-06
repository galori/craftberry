import XCTest

final class MinecraftE2EHarness {
    private let testCase: XCTestCase
    private let minecraftBundleID = "com.mojang.minecraftpe"
    private let observationPauseEnvironmentKey = "MINECRAFT_E2E_OBSERVE_EACH_STEP"
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

        XCUIDevice.shared.press(.home)
        craftberry.activate()
        XCTAssertTrue(testCase.waitForAppElement("craftberry.state.editing", in: craftberry, timeout: 5))
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

        for step in configuration.steps {
            try execute(step, in: minecraft, scenario: scenario)
        }

        let craftingSteps = compiler.compile(scenario.craftingPlan)
        let observesEachCraftingStep = ProcessInfo.processInfo.environment[observationPauseEnvironmentKey] == "1"
        for step in craftingSteps {
            try execute(step, in: minecraft, scenario: scenario)
            if observesEachCraftingStep, !step.isPassiveObservation {
                print("Observation pause after: \(step.name)")
                Thread.sleep(forTimeInterval: 20)
            }
        }
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
            start.press(forDuration: 0.1, thenDragTo: end)
        case .swipeUp:
            minecraft.swipeUp()
        case .typeText(let text):
            minecraft.typeText(text)
        case .keyboardText(let text):
            for character in text {
                minecraft.keys[String(character)].tap()
            }
            minecraft.buttons["Done"].tap()
        case .numericKeyboardText(let text):
            minecraft.keys["numbers"].tap()
            for character in text {
                minecraft.keys[String(character)].tap()
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
        minecraft.coordinate(withNormalizedOffset: CGVector(dx: 0.495, dy: 0.935)).tap()
        Thread.sleep(forTimeInterval: 2)
        commandKeyboard.type(text, in: minecraft)
        Thread.sleep(forTimeInterval: 1)
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
