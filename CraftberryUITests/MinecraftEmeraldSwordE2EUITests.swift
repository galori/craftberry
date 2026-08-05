import Vision
import XCTest

/// Physical-device acceptance for the complete Craftberry-to-Bedrock loop.
///
/// The Craftberry and import portions are deterministic. Minecraft's Ore UI
/// does not expose accessibility elements, so the in-world portion is driven
/// by calibrated normalized coordinates from `MinecraftDeviceE2EConfig.json`.
/// Keep that file disabled until its coordinates have been calibrated against
/// the target iPhone (see docs/MINECRAFT_DEVICE_AUTOMATION.md). This prevents
/// a normal UI-test run from mutating Minecraft state.
final class MinecraftEmeraldSwordE2EUITests: XCTestCase {
    private let minecraftBundleID = "com.mojang.minecraftpe"
    private let observationPauseEnvironmentKey = "MINECRAFT_E2E_OBSERVE_EACH_STEP"

    private struct DeviceScenario {
        let launchArgument: String
        let prompt: String
        let projectName: String
        let expectedCraftedItemName: String
        let behaviorPackName: String
        let resourcePackName: String
    }

    /// The Minecraft crafting screen is landscape while XCTest supplies
    /// normalized portrait coordinates. On the calibrated iPhone, visual
    /// crafting-grid columns therefore advance along `x`, and visual rows
    /// advance along increasing `y`. Keep all recipe layouts in logical
    /// row/column terms and translate them here.
    private struct CraftingGrid {
        struct Slot: Equatable {
            let row: Int
            let column: Int
        }

        static let calibrated = CraftingGrid(
            topLeftX: 0.654,
            topLeftY: 0.160,
            columnStep: 0.055,
            rowStep: 0.120
        )

        let topLeftX: CGFloat
        let topLeftY: CGFloat
        let columnStep: CGFloat
        let rowStep: CGFloat

        func coordinate(for slot: Slot) -> (x: CGFloat, y: CGFloat) {
            precondition((0...2).contains(slot.row) && (0...2).contains(slot.column))
            return (
                x: topLeftX + (CGFloat(slot.column) * columnStep),
                y: topLeftY + (CGFloat(slot.row) * rowStep)
            )
        }
    }

    private let emeraldSwordScenario = DeviceScenario(
        launchArgument: "--ui-testing-emerald-sword",
        prompt: "Create an Emerald Test Sword crafted from emeralds",
        projectName: "Emerald Test Sword",
        expectedCraftedItemName: "Emerald Test Sword",
        behaviorPackName: "Emerald Test Sword Behavior",
        resourcePackName: "Emerald Test Sword Resources"
    )

    private let redstoneToolSetScenario = DeviceScenario(
        launchArgument: "--ui-testing-redstone-tool-set",
        prompt: "Generate a redstone tool set crafted from redstone",
        projectName: "Redstone",
        expectedCraftedItemName: "Redstone Pickaxe",
        behaviorPackName: "Redstone Behavior",
        resourcePackName: "Redstone Resources"
    )

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTargetedDragStepDecodesStartAndEndCoordinates() throws {
        let data = Data(
            #"{"name":"Scroll the pack list","action":"drag","x":0.7,"y":0.85,"endX":0.7,"endY":0.25}"#.utf8
        )

        let step = try JSONDecoder().decode(MinecraftDeviceE2EStep.self, from: data)

        XCTAssertEqual(step.action, .drag)
        XCTAssertEqual(step.x, 0.7)
        XCTAssertEqual(step.y, 0.85)
        XCTAssertEqual(step.endX, 0.7)
        XCTAssertEqual(step.endY, 0.25)
    }

    func testVisionOrientationTracksPhysicalDeviceLandscapeDirection() {
        XCTAssertEqual(visionOrientation(for: .landscapeRight), .left)
        XCTAssertEqual(visionOrientation(for: .landscapeLeft), .right)
        XCTAssertEqual(visionOrientation(for: .portrait), .up)
        XCTAssertEqual(visionOrientation(for: .portraitUpsideDown), .down)
    }

    func testMinecraftOCRTriesTheCalibratedAndUprightScreenshotOrientations() {
        XCTAssertEqual(minecraftOCROrientations, [.left, .up])
    }

    func testRedstoneIngotSearchUsesTheSingleResultCoordinate() throws {
        let steps = redstonePickaxeCraftingSteps.filter { $0.name.contains("Pick") && $0.name.contains("Redstone Ingot") }

        XCTAssertEqual(steps.count, 3)
        XCTAssertTrue(steps.allSatisfy { $0.x == 0.143 && $0.y == 0.25 })
    }

    func testCraftingGridKeepsThePickaxeRecipeInItsVisualRows() {
        let grid = CraftingGrid.calibrated

        XCTAssertEqual(grid.coordinate(for: .init(row: 0, column: 0)).x, 0.654, accuracy: 0.001)
        XCTAssertEqual(grid.coordinate(for: .init(row: 0, column: 0)).y, 0.160, accuracy: 0.001)
        XCTAssertEqual(grid.coordinate(for: .init(row: 0, column: 2)).x, 0.764, accuracy: 0.001)
        XCTAssertEqual(grid.coordinate(for: .init(row: 1, column: 1)).y, 0.280, accuracy: 0.001)
        XCTAssertEqual(grid.coordinate(for: .init(row: 2, column: 1)).y, 0.400, accuracy: 0.001)
    }

    func testRedstonePickaxePlacementStepsFollowThePickaxeGrid() throws {
        let placements = redstonePickaxeCraftingSteps.filter { $0.name.hasPrefix("Place Redstone Ingot") || $0.name.hasPrefix("Place stick") }

        let expected: [(x: CGFloat, y: CGFloat)] = [
            (0.654, 0.160), (0.709, 0.160), (0.764, 0.160),
            (0.709, 0.280), (0.709, 0.400)
        ]
        XCTAssertEqual(placements.count, expected.count)
        for (placement, expectedCoordinate) in zip(placements, expected) {
            XCTAssertEqual(try XCTUnwrap(placement.x), expectedCoordinate.x, accuracy: 0.001)
            XCTAssertEqual(try XCTUnwrap(placement.y), expectedCoordinate.y, accuracy: 0.001)
        }
    }

    func testRedstoneIngotCraftingResetsTheCraftingTableBeforeThePickaxeRecipe() throws {
        let steps = redstonePickaxeCraftingSteps
        let resetIndex = try XCTUnwrap(steps.firstIndex { $0.name == "Close crafting table to return recipe inputs" })

        XCTAssertEqual(steps[resetIndex + 1].name, "Wait for leftover recipe inputs to return to inventory")
        XCTAssertEqual(steps[resetIndex + 2].name, "Reopen crafting table for the next recipe")
        XCTAssertEqual(steps[resetIndex + 3].name, "Wait for crafting table to reopen")
        XCTAssertEqual(steps[resetIndex + 4].name, "Confirm crafting table reopened for the next recipe")
    }

    func testKeyboardTextStepDecodesText() throws {
        let data = Data(
            #"{"name":"Search for emerald","action":"keyText","text":"emerald"}"#.utf8
        )

        let step = try JSONDecoder().decode(MinecraftDeviceE2EStep.self, from: data)

        XCTAssertEqual(step.action, .keyText)
        XCTAssertEqual(step.text, "emerald")
    }

    func testConfigurationDecodesWithoutCleanupSteps() throws {
        let data = Data(#"""
        {
          "enabled": false,
          "expectedSwordName": "Emerald Test Sword",
          "steps": []
        }
        """#.utf8)

        let configuration = try JSONDecoder().decode(MinecraftDeviceE2EConfiguration.self, from: data)

        XCTAssertFalse(configuration.enabled)
        XCTAssertEqual(configuration.expectedSwordName, "Emerald Test Sword")
        XCTAssertTrue(configuration.steps.isEmpty)
    }

    func testDeviceConfigurationVerifiesBothPacksAreActiveBeforeWorldLaunch() throws {
        let configuration = try loadConfiguration()

        let stackingWarningStep = try XCTUnwrap(configuration.steps.first { $0.name == "Accept the add-on stacking warning" })
        XCTAssertEqual(stackingWarningStep.x, 0.5)
        XCTAssertEqual(stackingWarningStep.y, 0.705)
        XCTAssertEqual(
            configuration.steps.first { $0.name == "Confirm the behavior pack is active" }?.text,
            "$EXPECTED_BEHAVIOR_PACK"
        )
        XCTAssertEqual(
            configuration.steps.first { $0.name == "Confirm the dependent resource pack is active" }?.text,
            "$EXPECTED_RESOURCE_PACK"
        )

        let playIndex = try XCTUnwrap(
            configuration.steps.firstIndex { $0.name == "Launch the craftberry test world locally in creative mode" }
        )
        let behaviorCheckIndex = try XCTUnwrap(
            configuration.steps.firstIndex { $0.name == "Confirm the behavior pack is active" }
        )
        let resourceCheckIndex = try XCTUnwrap(
            configuration.steps.firstIndex { $0.name == "Confirm the dependent resource pack is active" }
        )
        XCTAssertLessThan(behaviorCheckIndex, playIndex)
        XCTAssertLessThan(resourceCheckIndex, playIndex)

        let localizedNameCheckIndex = try XCTUnwrap(
            configuration.steps.firstIndex { $0.name == "Confirm the crafted sword's localized display name" }
        )
        let closeCraftingIndex = try XCTUnwrap(
            configuration.steps.firstIndex { $0.name == "Close the crafting interface" }
        )
        XCTAssertLessThan(localizedNameCheckIndex, closeCraftingIndex)
    }

    func testCraftberryEmeraldSwordCanBeImportedActivatedAndCrafted() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try runDeviceAcceptance(scenario: emeraldSwordScenario, craftingSteps: nil)
        #endif
    }

    func testCraftberryRedstoneToolSetCanBeImportedActivatedAndCraftedIntoPickaxe() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        try runDeviceAcceptance(scenario: redstoneToolSetScenario, craftingSteps: redstonePickaxeCraftingSteps)
        #endif
    }

    private func runDeviceAcceptance(
        scenario: DeviceScenario,
        craftingSteps: [MinecraftDeviceE2EStep]?
    ) throws {
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
        XCTAssertTrue(waitForElement("craftberry.state.editing", in: craftberry, timeout: 8))

        let prompt = craftberry.textViews["craftberry.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.tap()
        prompt.typeText(scenario.prompt)

        // TextEditor keeps the software keyboard up on the physical iPhone,
        // where it covers the Generate button in landscape. Briefly
        // backgrounding and reactivating Craftberry dismisses that keyboard
        // without losing the in-progress prompt.
        XCUIDevice.shared.press(.home)
        craftberry.activate()
        XCTAssertTrue(waitForElement("craftberry.state.editing", in: craftberry, timeout: 5))
        craftberry.buttons["craftberry.generate"].tap()
        XCTAssertTrue(waitForElement("craftberry.state.ready", in: craftberry, timeout: 8))
        XCTAssertTrue(
            craftberry.staticTexts[scenario.projectName].waitForExistence(timeout: 2),
            "The deterministic device fixture did not generate \(scenario.projectName)."
        )

        craftberry.buttons["craftberry.build"].tap()
        XCTAssertTrue(waitForElement("craftberry.state.built", in: craftberry, timeout: 10))
        craftberry.buttons["craftberry.export"].tap()
        attach("Craftberry export share sheet")
        attachAccessibilityTree("Craftberry export share sheet", app: craftberry)

        // Minecraft's share extension imports both nested .mcpack files from
        // the exported .mcaddon. This is deliberately the app's export path,
        // rather than the standalone Safari fixture path.
        try tapMinecraftShareDestination(in: craftberry)

        let minecraft = XCUIApplication(bundleIdentifier: minecraftBundleID)

        // Mac-side cleanup runs scripts/minecraft-cleanup.sh from
        // scripts/ios-device.sh after xcodebuild exits. The on-device test
        // runner cannot execute that local shell script, but it can ensure
        // Minecraft is not running before AFC cleanup inspects its files.
        addTeardownBlock { [self] in
            minecraft.terminate()
            attach("Minecraft terminated before AFC cleanup")
        }

        XCTAssertTrue(
            minecraft.wait(for: .runningForeground, timeout: 30),
            "Minecraft did not open after exporting the .mcaddon from Craftberry."
        )
        Thread.sleep(forTimeInterval: 5)
        attach("Minecraft after importing Craftberry's \(scenario.projectName)")
        XCTAssertFalse(
            recognizedText().localizedCaseInsensitiveContains("Failed to import"),
            "Minecraft rejected Craftberry's exported add-on. Inspect the import screenshot and Content Log before calibrating world steps."
        )

        // Import returns Minecraft to whichever Ore UI it had open before the
        // handoff. Restart it after the import completes so the calibrated
        // coordinate flow always begins at the known main-menu Play button.
        minecraft.terminate()
        Thread.sleep(forTimeInterval: 1)
        minecraft.launch()
        XCTAssertTrue(
            minecraft.wait(for: .runningForeground, timeout: 30),
            "Minecraft did not return to the foreground after the post-import cold launch."
        )
        Thread.sleep(forTimeInterval: 8)
        attach("Minecraft cold launch after importing Craftberry's \(scenario.projectName)")

        let steps: [MinecraftDeviceE2EStep]
        if let craftingSteps {
            let craftingTableIndex = try XCTUnwrap(
                configuration.steps.firstIndex { $0.name == "Confirm the crafting table interface is open" }
            )
            steps = Array(configuration.steps.prefix(through: craftingTableIndex)) + craftingSteps
        } else {
            steps = configuration.steps
        }
        let observesEachCraftingStep = craftingSteps != nil
            && ProcessInfo.processInfo.environment[observationPauseEnvironmentKey] == "1"
        for step in steps {
            try execute(step, in: minecraft, scenario: scenario, expectedSwordName: configuration.expectedSwordName)
            if observesEachCraftingStep, step.action != .wait, step.action != .ocr {
                print("Observation pause after: \(step.name)")
                Thread.sleep(forTimeInterval: 20)
            }
        }
    }

    /// The tool-set compiler first turns four redstone dust into a Redstone
    /// Ingot, then its pickaxe recipe requires three ingots and two sticks.
    /// These coordinates share the calibrated crafting-table screen from the
    /// Emerald Sword flow above; only the recipe-specific portion differs.
    private var redstonePickaxeCraftingSteps: [MinecraftDeviceE2EStep] {
        let grid = CraftingGrid.calibrated
        let ingotCraftingSlots = [
            CraftingGrid.Slot(row: 0, column: 0), CraftingGrid.Slot(row: 0, column: 1),
            CraftingGrid.Slot(row: 1, column: 0), CraftingGrid.Slot(row: 1, column: 1)
        ]
        let pickaxeIngotSlots = [
            CraftingGrid.Slot(row: 0, column: 0), CraftingGrid.Slot(row: 0, column: 1), CraftingGrid.Slot(row: 0, column: 2)
        ]
        let pickaxeStickSlots = [
            CraftingGrid.Slot(row: 1, column: 1), CraftingGrid.Slot(row: 2, column: 1)
        ]
        return [
            step("Search Creative inventory for redstone", .tap, x: 0.29, y: 0.155),
            step("Type redstone search", .keyText, text: "redstone"),
            step("Wait for redstone search results", .wait, seconds: 4),
        ] + placeCreativeSearchResult("redstone", from: (x: 0.309, y: 0.25), into: ingotCraftingSlots, grid: grid) + [
            step("Wait for Redstone Ingot output", .wait, seconds: 4),
            step("Take Redstone Ingot output", .tap, x: 0.709, y: 0.756),
            step("Confirm crafted Redstone Ingot", .ocr, text: "Redstone Ingot"),
            step("Put Redstone Ingot in inventory", .tap, x: 0.611, y: 0.91),
        ] + resetCraftingTableForNextRecipe() + [
            step("Clear redstone search", .tap, x: 0.463, y: 0.155),
            step("Search Creative inventory for Redstone Ingot", .tap, x: 0.29, y: 0.155),
            step("Type Redstone Ingot search", .keyText, text: "redstone ingot"),
            step("Wait for Redstone Ingot search results", .wait, seconds: 4),
        ] + placeCreativeSearchResult("Redstone Ingot", from: (x: 0.143, y: 0.25), into: pickaxeIngotSlots, grid: grid) + [
            step("Clear Redstone Ingot search", .tap, x: 0.463, y: 0.155),
            step("Search Creative inventory for stick", .tap, x: 0.29, y: 0.155),
            step("Type stick search", .keyText, text: "stick"),
            step("Wait for stick search results", .wait, seconds: 4),
        ] + placeCreativeSearchResult("stick", from: (x: 0.253, y: 0.25), into: pickaxeStickSlots, grid: grid) + [
            step("Wait for Redstone Pickaxe output", .wait, seconds: 4),
            step("Confirm Redstone Pickaxe output is visible", .redstonePickaxeOutput),
            step("Take Redstone Pickaxe output", .tap, x: 0.709, y: 0.756),
            step("Put crafted Redstone Pickaxe in hotbar", .tap, x: 0.611, y: 0.91),
            step("Close crafting interface", .tap, x: 0.947, y: 0.065)
        ]
    }

    private func placeCreativeSearchResult(
        _ itemName: String,
        from source: (x: CGFloat, y: CGFloat),
        into destinations: [CraftingGrid.Slot],
        grid: CraftingGrid
    ) -> [MinecraftDeviceE2EStep] {
        destinations.enumerated().flatMap { index, slot in
            let destination = grid.coordinate(for: slot)
            return [
                step("Pick \(ordinal(index + 1)) \(itemName) stack", .tap, x: source.x, y: source.y),
                step("Place \(itemName) in crafting row \(slot.row + 1), column \(slot.column + 1)", .tap, x: destination.x, y: destination.y)
            ]
        }
    }

    /// Closing the table returns every unconsumed input to the player. This is
    /// more reliable than individually tapping an Ore UI grid after a
    /// shapeless recipe, and makes each recipe begin from an empty table.
    private func resetCraftingTableForNextRecipe() -> [MinecraftDeviceE2EStep] {
        [
            step("Close crafting table to return recipe inputs", .tap, x: 0.947, y: 0.065),
            step("Wait for leftover recipe inputs to return to inventory", .wait, seconds: 2),
            step("Reopen crafting table for the next recipe", .tap, x: 0.5075, y: 0.265),
            step("Wait for crafting table to reopen", .wait, seconds: 4),
            step("Confirm crafting table reopened for the next recipe", .ocr, text: "Crafting")
        ]
    }

    private func ordinal(_ value: Int) -> String {
        switch value {
        case 1: "first"
        case 2: "second"
        case 3: "third"
        case 4: "fourth"
        default: "\(value)th"
        }
    }

    private func step(
        _ name: String,
        _ action: MinecraftDeviceE2EStep.Action,
        x: CGFloat? = nil,
        y: CGFloat? = nil,
        seconds: TimeInterval? = nil,
        text: String? = nil
    ) -> MinecraftDeviceE2EStep {
        MinecraftDeviceE2EStep(name: name, action: action, x: x, y: y, endX: nil, endY: nil, seconds: seconds, text: text)
    }

    private func execute(
        _ step: MinecraftDeviceE2EStep,
        in minecraft: XCUIApplication,
        scenario: DeviceScenario,
        expectedSwordName: String
    ) throws {
        if step.action == .ocr {
            let expected: String?
            switch step.text {
            case "$EXPECTED_SWORD_NAME": expected = expectedSwordName
            case "$EXPECTED_BEHAVIOR_PACK": expected = scenario.behaviorPackName
            case "$EXPECTED_RESOURCE_PACK": expected = scenario.resourcePackName
            case "$EXPECTED_CRAFTED_ITEM_NAME": expected = scenario.expectedCraftedItemName
            default: expected = step.text
            }
            guard let expected, !expected.isEmpty else {
                throw ConfigurationError.missingText(step.name)
            }
            XCTAssertTrue(
                waitForRecognizedText(expected, timeout: 5),
                "OCR did not find '\(expected)' after \(step.name). Recalibrate this step if Minecraft's UI changed."
            )
        } else if step.action == .redstonePickaxeOutput {
            XCTAssertTrue(
                redstonePickaxeOutputIsVisible(),
                "The Redstone Pickaxe output slot did not contain the generated red pickaxe after its recipe was laid out."
            )
        } else {
            try performGesture(step, in: minecraft)
        }

        attach(step.name)
    }

    private func visionOrientation(for deviceOrientation: UIDeviceOrientation) -> CGImagePropertyOrientation {
        switch deviceOrientation {
        case .landscapeRight:
            return .left
        case .landscapeLeft:
            return .right
        case .portraitUpsideDown:
            return .down
        default:
            return .up
        }
    }

    private func performGesture(_ step: MinecraftDeviceE2EStep, in minecraft: XCUIApplication) throws {
        switch step.action {
        case .wait:
            Thread.sleep(forTimeInterval: step.seconds ?? 1)
        case .tap:
            guard let x = step.x, let y = step.y else {
                throw ConfigurationError.missingCoordinate(step.name)
            }
            minecraft.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
        case .drag:
            guard
                let x = step.x,
                let y = step.y,
                let endX = step.endX,
                let endY = step.endY
            else {
                throw ConfigurationError.missingCoordinate(step.name)
            }
            let start = minecraft.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
            let end = minecraft.coordinate(withNormalizedOffset: CGVector(dx: endX, dy: endY))
            start.press(forDuration: 0.1, thenDragTo: end)
        case .swipeUp:
            minecraft.swipeUp()
        case .type:
            guard let text = step.text else {
                throw ConfigurationError.missingText(step.name)
            }
            minecraft.typeText(text)
        case .keyText:
            guard let text = step.text else {
                throw ConfigurationError.missingText(step.name)
            }
            for character in text {
                minecraft.keys[String(character)].tap()
            }
            minecraft.buttons["Done"].tap()
        case .numericKeyText:
            guard let text = step.text else {
                throw ConfigurationError.missingText(step.name)
            }
            minecraft.keys["numbers"].tap()
            for character in text {
                minecraft.keys[String(character)].tap()
            }
            minecraft.buttons["Done"].tap()
        case .chatCommand:
            guard let text = step.text else {
                throw ConfigurationError.missingText(step.name)
            }
            sendChatCommand(text, in: minecraft)
        case .redstonePickaxeOutput:
            // Handled by `execute`, which inspects the output slot.
            break
        case .ocr:
            // Handled by `execute`, which hard-asserts OCR.
            break
        }
    }

    /// Opens Minecraft's chat/command input, types `text`, and sends it.
    /// Fresh worlds have no crafting table at spawn (unlike the old "My
    /// World" fixture, which had one manually placed), so the emerald-sword
    /// test uses this to `/tp` to a known position and `/setblock` a table
    /// in front of it instead of a physical place gesture. Coordinates and
    /// the keyboard-page quirks below were calibrated live — see
    /// docs/MINECRAFT_DEVICE_AUTOMATION.md.
    private func sendChatCommand(_ text: String, in minecraft: XCUIApplication) {
        minecraft.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.0325)).tap()
        Thread.sleep(forTimeInterval: 2)
        minecraft.coordinate(withNormalizedOffset: CGVector(dx: 0.495, dy: 0.935)).tap()
        Thread.sleep(forTimeInterval: 2)
        typeOnCommandKeyboard(text, in: minecraft)
        Thread.sleep(forTimeInterval: 1)
        minecraft.coordinate(withNormalizedOffset: CGVector(dx: 0.9275, dy: 0.434)).tap()
        Thread.sleep(forTimeInterval: 2)
    }

    /// Types `text` character-by-character on the iOS system keyboard,
    /// switching between its letters/numbers/symbols pages as needed.
    /// `XCUIElement.typeText` fails here ("no keyboard focus") because
    /// Minecraft's chat field is custom-rendered, not a real UITextField.
    /// Three quirks were confirmed live and are load-bearing:
    /// - `app.keys[string]` matches by *identifier*, not visible label: the
    ///   space key's identifier is "space" (label is literally " "), and
    ///   "^"/"~" have no matching identifier at all (iOS treats them as dead
    ///   keys for diacritic composition) — those two are tapped by their
    ///   calibrated pixel position on the symbols page instead.
    /// - iOS auto-reverts the numbers/symbols page to letters after a space
    ///   or after "^"/"~", so tracked keyboard-page state must follow that
    ///   revert or the next character's page-switch becomes a no-op.
    /// - Switching letters→symbols must go through the numbers page first,
    ///   with a short delay between the two sub-taps, or the second tap
    ///   lands before the page has actually changed.
    private func typeOnCommandKeyboard(_ text: String, in minecraft: XCUIApplication) {
        enum KeyboardPage { case letters, numbers, symbols }
        var currentPage = KeyboardPage.letters
        let toSymbolsOrNumbersToggle = CGVector(dx: 0.1435, dy: 0.8117)
        let toLettersToggle = CGVector(dx: 0.131, dy: 0.9004)
        let symbolsPageCoordinates: [Character: CGVector] = [
            "^": CGVector(dx: 0.6225, dy: 0.630),
            "~": CGVector(dx: 0.376, dy: 0.7165)
        ]

        func switchTo(_ page: KeyboardPage) {
            guard page != currentPage else { return }
            switch (currentPage, page) {
            case (.letters, .numbers):
                minecraft.keys["numbers"].tap()
            case (.letters, .symbols):
                minecraft.keys["numbers"].tap()
                usleep(500_000)
                minecraft.coordinate(withNormalizedOffset: toSymbolsOrNumbersToggle).tap()
            case (.numbers, .letters), (.symbols, .letters):
                minecraft.coordinate(withNormalizedOffset: toLettersToggle).tap()
            case (.numbers, .symbols), (.symbols, .numbers):
                minecraft.coordinate(withNormalizedOffset: toSymbolsOrNumbersToggle).tap()
            default:
                break
            }
            currentPage = page
            usleep(300_000)
        }

        for character in text {
            if character == " " {
                minecraft.keys["space"].tap()
                currentPage = .letters
            } else if let symbolCoordinate = symbolsPageCoordinates[character] {
                switchTo(.symbols)
                minecraft.coordinate(withNormalizedOffset: symbolCoordinate).tap()
                currentPage = .letters
                usleep(300_000)
            } else if character == "_" {
                switchTo(.symbols)
                minecraft.keys["_"].tap()
            } else if character.isLetter {
                switchTo(.letters)
                minecraft.keys[String(character)].tap()
            } else {
                switchTo(.numbers)
                minecraft.keys[String(character)].tap()
            }
        }
    }

    private func recognizedText() -> String {
        guard let image = XCUIScreen.main.screenshot().image.cgImage else {
            XCTFail("Could not create a CGImage for Minecraft OCR")
            return ""
        }

        let recognizedLines: [String] = minecraftOCROrientations.flatMap { orientation -> [String] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            do {
                try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
            } catch {
                XCTFail("Minecraft OCR failed: \(error)")
                return [String]()
            }

            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        }
        return recognizedLines.joined(separator: "\n")
    }

    /// Minecraft's custom crafting grid has no accessible output element. On
    /// the calibrated iPhone 16e, a craftable redstone pickaxe contributes a
    /// cluster of red pixels to its output slot; a blank slot does not.
    private func redstonePickaxeOutputIsVisible() -> Bool {
        guard let image = XCUIScreen.main.screenshot().image.cgImage else { return false }
        let width = image.width
        let height = image.height
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let pixels = context.data?.bindMemory(to: UInt8.self, capacity: width * height * 4) else { return false }

        let xRange = Int(CGFloat(width) * 0.18)..<Int(CGFloat(width) * 0.31)
        let yRange = Int(CGFloat(height) * 0.67)..<Int(CGFloat(height) * 0.75)
        var redPixels = 0
        for y in yRange {
            for x in xRange {
                let offset = ((y * width) + x) * 4
                let red = Int(pixels[offset])
                let green = Int(pixels[offset + 1])
                let blue = Int(pixels[offset + 2])
                if red > 140, red > green * 2, red > blue * 2 { redPixels += 1 }
            }
        }
        return redPixels >= 20
    }

    /// Minecraft ordinarily reports a landscape UI while XCUIScreen exposes a
    /// portrait pixel buffer, but result-bundle evidence from the iPhone 16e
    /// shows that some screens arrive upright. Search both rather than
    /// rejecting an active pack that is visibly present.
    private let minecraftOCROrientations: [CGImagePropertyOrientation] = [.left, .up]

    private func waitForRecognizedText(_ expected: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if recognizedText().localizedCaseInsensitiveContains(expected) {
                return true
            }
            usleep(500_000)
        } while Date() < deadline

        return false
    }

    private func loadConfiguration() throws -> MinecraftDeviceE2EConfiguration {
        guard let url = Bundle(for: Self.self).url(forResource: "MinecraftDeviceE2EConfig", withExtension: "json") else {
            throw ConfigurationError.missingResource
        }
        return try JSONDecoder().decode(MinecraftDeviceE2EConfiguration.self, from: Data(contentsOf: url))
    }

    private func waitForElement(_ identifier: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        app.descendants(matching: .any)[identifier].waitForExistence(timeout: timeout)
    }

    private func tapFirstExisting(
        _ candidates: [XCUIElement],
        in app: XCUIApplication,
        timeout: TimeInterval,
        description: String
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for candidate in candidates where candidate.exists && candidate.isHittable {
                candidate.tap()
                return
            }
            usleep(200_000)
        } while Date() < deadline

        attach("Failed to find \(description)")
        XCTFail("Could not find \(description) within \(timeout) seconds")
        throw ConfigurationError.unavailableElement(description)
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

        // The app tile is an operating-system share-sheet surface and has
        // changed accessibility roles between iOS releases. This coordinate
        // is calibrated to its visible centre on the connected iPhone 16e.
        let fallback = app.coordinate(withNormalizedOffset: CGVector(dx: 0.385, dy: 0.460))
        fallback.tap()
    }

    private func attachAccessibilityTree(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = "\(name) accessibility tree"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private struct MinecraftDeviceE2EConfiguration: Decodable {
    let enabled: Bool
    let expectedSwordName: String
    let steps: [MinecraftDeviceE2EStep]

    private enum CodingKeys: String, CodingKey {
        case enabled, expectedSwordName, steps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        expectedSwordName = try container.decode(String.self, forKey: .expectedSwordName)
        steps = try container.decode([MinecraftDeviceE2EStep].self, forKey: .steps)
    }
}

private struct MinecraftDeviceE2EStep: Decodable {
    enum Action: String, Decodable, Equatable {
        case wait
        case tap
        case drag
        case swipeUp
        case type
        case keyText
        /// Like `keyText`, but switches to the numbers keyboard page first —
        /// for fields (like World seed) that default to the letters page but
        /// only accept digits.
        case numericKeyText
        /// Opens Minecraft's chat/command input, types `text` (switching
        /// keyboard pages as needed), and sends it. Used to `/tp` and
        /// `/setblock` a crafting table into a fresh world, which has none
        /// at spawn (see docs/MINECRAFT_DEVICE_AUTOMATION.md).
        case chatCommand
        case redstonePickaxeOutput
        case ocr
    }

    let name: String
    let action: Action
    let x: CGFloat?
    let y: CGFloat?
    let endX: CGFloat?
    let endY: CGFloat?
    let seconds: TimeInterval?
    let text: String?
}

private enum ConfigurationError: LocalizedError {
    case missingResource
    case missingCoordinate(String)
    case missingText(String)
    case unavailableElement(String)

    var errorDescription: String? {
        switch self {
        case .missingResource:
            "MinecraftDeviceE2EConfig.json is missing from the UI-test bundle."
        case .missingCoordinate(let name):
            "The calibrated coordinate for '\(name)' is missing."
        case .missingText(let name):
            "The required text for '\(name)' is missing."
        case .unavailableElement(let description):
            "The expected UI element was unavailable: \(description)."
        }
    }
}
