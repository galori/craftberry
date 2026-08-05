import Vision
import XCTest
import UIKit

/// Physical-device acceptance for the complete Craftberry-to-Bedrock loop.
///
/// The Craftberry and import portions are deterministic. Minecraft's Ore UI
/// does not expose accessibility elements, so the in-world portion is driven
/// by calibrated normalized coordinates from `MinecraftDeviceE2EConfig.json`.
/// Keep that file disabled until its coordinates have been calibrated against
/// the target iPhone and the existing creative world (see
/// docs/MINECRAFT_DEVICE_AUTOMATION.md). This prevents a normal UI-test run
/// from mutating Minecraft state.
final class MinecraftEmeraldSwordE2EUITests: XCTestCase {
    private let minecraftBundleID = "com.mojang.minecraftpe"

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

    func testStorageTrashControlLocatorFindsControlAfterStorageReflows() throws {
        for expectedY in [CGFloat(0.75), CGFloat(0.89)] {
            let size = CGSize(width: 1_000, height: 500)
            let format = UIGraphicsImageRendererFormat()
            format.opaque = true
            format.preferredRange = .standard
            let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.black.setFill()
                context.fill(CGRect(origin: .zero, size: size))

                let barHeight = size.height * 0.08
                let barY = size.height * expectedY - barHeight / 2
                UIColor(white: 0.25, alpha: 1).setFill()
                context.fill(CGRect(x: size.width * 0.30, y: barY, width: size.width * 0.40, height: barHeight))

                UIColor(white: 0.78, alpha: 1).setFill()
                context.fill(CGRect(x: size.width * 0.44, y: barY, width: size.width * 0.056, height: barHeight))
            }

            let locatedY = try XCTUnwrap(
                StorageTrashControlLocator.normalizedY(in: image, normalizedX: 0.468)
            )
            XCTAssertEqual(locatedY, expectedY, accuracy: 0.01)
        }
    }

    func testKeyboardTextStepDecodesText() throws {
        let data = Data(
            #"{"name":"Search for emerald","action":"keyText","text":"emerald"}"#.utf8
        )

        let step = try JSONDecoder().decode(MinecraftDeviceE2EStep.self, from: data)

        XCTAssertEqual(step.action, .keyText)
        XCTAssertEqual(step.text, "emerald")
    }

    func testConfigurationDecodesCleanupStepsWhenPresent() throws {
        let data = Data(#"""
        {
          "enabled": false,
          "expectedSwordName": "Emerald Test Sword",
          "steps": [],
          "cleanupSteps": [
            {"name": "Deactivate the behavior pack", "action": "tap", "x": 0.5, "y": 0.5}
          ]
        }
        """#.utf8)

        let configuration = try JSONDecoder().decode(MinecraftDeviceE2EConfiguration.self, from: data)

        XCTAssertEqual(configuration.cleanupSteps.count, 1)
        XCTAssertEqual(configuration.cleanupSteps.first?.name, "Deactivate the behavior pack")
    }

    func testConfigurationDefaultsCleanupStepsToEmptyWhenAbsent() throws {
        let data = Data(#"""
        {
          "enabled": false,
          "expectedSwordName": "Emerald Test Sword",
          "steps": []
        }
        """#.utf8)

        let configuration = try JSONDecoder().decode(MinecraftDeviceE2EConfiguration.self, from: data)

        XCTAssertTrue(configuration.cleanupSteps.isEmpty)
    }

    func testStorageCleanupActionsDecodeTheirLabelsAndTapColumns() throws {
        let tapData = Data(
            #"{"name":"Expand Resource Packs","action":"tapRecognizedRow","text":"Resource Packs","x":0.5}"#.utf8
        )
        let deleteData = Data(
            #"{"name":"Delete test pack","action":"deleteIfUniquelyStored","text":"Emerald Test Sword Resources","x":0.5,"endX":0.468}"#.utf8
        )
        let deleteAllData = Data(
            #"{"name":"Delete all test packs","action":"deleteAllStored","text":"Emerald Test Sword Resources","x":0.5,"endX":0.468}"#.utf8
        )

        let tap = try JSONDecoder().decode(MinecraftDeviceE2EStep.self, from: tapData)
        let delete = try JSONDecoder().decode(MinecraftDeviceE2EStep.self, from: deleteData)
        let deleteAll = try JSONDecoder().decode(MinecraftDeviceE2EStep.self, from: deleteAllData)

        XCTAssertEqual(tap.action, .tapRecognizedRow)
        XCTAssertEqual(tap.text, "Resource Packs")
        XCTAssertEqual(tap.x, 0.5)
        XCTAssertEqual(delete.action, .deleteIfUniquelyStored)
        XCTAssertEqual(delete.text, "Emerald Test Sword Resources")
        XCTAssertEqual(delete.x, 0.5)
        XCTAssertEqual(delete.endX, 0.468)
        XCTAssertEqual(deleteAll.action, .deleteAllStored)
        XCTAssertEqual(deleteAll.text, "Emerald Test Sword Resources")
        XCTAssertEqual(deleteAll.x, 0.5)
        XCTAssertEqual(deleteAll.endX, 0.468)
    }

    func testDeviceConfigurationVerifiesBothPacksAreActiveBeforeWorldLaunch() throws {
        let configuration = try loadConfiguration()

        let stackingWarningStep = try XCTUnwrap(configuration.steps.first { $0.name == "Accept the add-on stacking warning" })
        XCTAssertEqual(stackingWarningStep.x, 0.5)
        XCTAssertEqual(stackingWarningStep.y, 0.705)
        XCTAssertEqual(
            configuration.steps.first { $0.name == "Confirm the behavior pack is active" }?.text,
            "Emerald Test Sword Behavior"
        )
        XCTAssertEqual(
            configuration.steps.first { $0.name == "Confirm the dependent resource pack is active" }?.text,
            "Emerald Test Sword Resources"
        )

        let playIndex = try XCTUnwrap(
            configuration.steps.firstIndex { $0.name == "Launch My World locally in creative mode" }
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

    func testDeviceConfigurationTargetsStorageDisclosureArrowsAndScrollsExpandedPackLists() throws {
        let configuration = try loadConfiguration()
        let cleanup = configuration.cleanupSteps

        let expandWorldsIndex = try XCTUnwrap(
            cleanup.firstIndex { $0.name == "Expand the Worlds storage row" }
        )
        XCTAssertEqual(cleanup[expandWorldsIndex].x, 0.85)

        let collapseWorldsIndex = try XCTUnwrap(
            cleanup.firstIndex { $0.name == "Collapse the Worlds storage category" }
        )
        XCTAssertEqual(cleanup[collapseWorldsIndex].x, 0.85)

        let expandResourceIndex = try XCTUnwrap(
            cleanup.firstIndex { $0.name == "Expand the Resource Packs storage category" }
        )
        XCTAssertEqual(cleanup[expandResourceIndex].action, .tap)
        XCTAssertEqual(cleanup[expandResourceIndex].x, 0.85)
        XCTAssertEqual(cleanup[expandResourceIndex].y, 0.855)
        XCTAssertEqual(
            cleanup[expandResourceIndex + 2].name,
            "Scroll to the expanded Resource Packs list"
        )
        XCTAssertEqual(cleanup[expandResourceIndex + 2].action, .drag)

        let collapseResourceIndex = try XCTUnwrap(
            cleanup.firstIndex { $0.name == "Collapse the Resource Packs storage category" }
        )
        XCTAssertEqual(cleanup[collapseResourceIndex].x, 0.85)
        XCTAssertEqual(cleanup[collapseResourceIndex].text, "source Packs")

        let expandBehaviorIndex = try XCTUnwrap(
            cleanup.firstIndex { $0.name == "Expand the Behavior Packs storage category" }
        )
        XCTAssertEqual(cleanup[expandBehaviorIndex].action, .tapRecognizedRow)
        XCTAssertEqual(cleanup[expandBehaviorIndex].x, 0.85)
        XCTAssertEqual(
            cleanup[expandBehaviorIndex + 2].name,
            "Scroll to the expanded Behavior Packs list"
        )
        XCTAssertEqual(cleanup[expandBehaviorIndex + 2].action, .drag)
    }

    func testCraftberryEmeraldSwordCanBeImportedActivatedAndCrafted() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This is a physical-device Minecraft acceptance test; it requires Minecraft installed on the dedicated iPhone.")
        #else
        let configuration = try loadConfiguration()
        guard configuration.enabled else {
            throw XCTSkip("This is a physical-device acceptance test. Calibrate and enable MinecraftDeviceE2EConfig.json before running it on the dedicated iPhone.")
        }

        let craftberry = XCUIApplication()
        craftberry.launchArguments = [
            "--ui-testing",
            "--ui-testing-emerald-sword",
            "--ui-testing-fresh-pack-identity"
        ]
        craftberry.launch()
        XCTAssertTrue(waitForElement("craftberry.state.editing", in: craftberry, timeout: 8))

        let prompt = craftberry.textViews["craftberry.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.tap()
        prompt.typeText("Create an Emerald Test Sword crafted from emeralds")

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
            craftberry.staticTexts["Emerald Test Sword"].waitForExistence(timeout: 2),
            "The deterministic device fixture did not generate the expected nonstandard-material sword."
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

        // Deleting the freshly created world is best-effort device hygiene,
        // not part of this test's acceptance signal: it must run whether the
        // test above passes or fails, and a cleanup hiccup must never turn a
        // successful crafting run into a reported failure (or mask a real
        // one). Register it as soon as `minecraft` exists so it still runs
        // if a later assertion throws. Deleting the whole world (rather than
        // deactivating packs one at a time) already clears every active-pack
        // reference, so there is nothing pack-specific left to clean up.
        addTeardownBlock { [self] in
            for step in configuration.cleanupSteps {
                executeCleanupStep(step, in: minecraft)
            }
        }

        XCTAssertTrue(
            minecraft.wait(for: .runningForeground, timeout: 30),
            "Minecraft did not open after exporting the .mcaddon from Craftberry."
        )
        Thread.sleep(forTimeInterval: 5)
        attach("Minecraft after importing Craftberry's Emerald Test Sword")
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
        attach("Minecraft cold launch after importing Craftberry's Emerald Test Sword")

        for step in configuration.steps {
            try execute(step, in: minecraft, expectedSwordName: configuration.expectedSwordName)
        }
        #endif
    }

    private func execute(
        _ step: MinecraftDeviceE2EStep,
        in minecraft: XCUIApplication,
        expectedSwordName: String
    ) throws {
        if step.action == .ocr {
            let expected = step.text == "$EXPECTED_SWORD_NAME" ? expectedSwordName : step.text
            guard let expected, !expected.isEmpty else {
                throw ConfigurationError.missingText(step.name)
            }
            XCTAssertTrue(
                waitForRecognizedText(expected, timeout: 5),
                "OCR did not find '\(expected)' after \(step.name). Recalibrate this step if Minecraft's UI changed."
            )
        } else {
            try performGesture(step, in: minecraft)
        }

        attach(step.name)
    }

    /// Runs a post-test cleanup step (deactivating an imported pack) without
    /// affecting the acceptance test's own pass/fail result. Any failure —
    /// a missing coordinate, an OCR miss, an unexpected screen — is captured
    /// as a screenshot and logged only. This is deliberately not the same
    /// code path as `execute`, which uses hard `XCTAssert`s: cleanup must
    /// never turn a successful crafting run into a reported failure, or mask
    /// a real one, per the "not an automated verification step" requirement.
    private func executeCleanupStep(_ step: MinecraftDeviceE2EStep, in minecraft: XCUIApplication) {
        do {
            switch step.action {
            case .ocr:
                guard let expected = step.text, !expected.isEmpty else {
                    attach("Cleanup step '\(step.name)' has no expected OCR text; skipping check")
                    return
                }
                if !waitForRecognizedText(expected, timeout: 5) {
                    attach("Cleanup step '\(step.name)': OCR did not find '\(expected)' (logged only, not failing the test)")
                }
            case .tapRecognizedRow:
                guard let label = step.text, let tapX = step.x else {
                    attach("Cleanup step '\(step.name)' is missing text/x; skipping")
                    return
                }
                guard let rowY = uniqueRecognizedRowNormalizedY(matching: label) else {
                    attach("Cleanup step '\(step.name)': could not uniquely locate '\(label)'; skipping rather than guessing")
                    return
                }
                minecraft.coordinate(withNormalizedOffset: CGVector(dx: tapX, dy: rowY)).tap()
            case .deleteIfUniquelyStored:
                guard
                    let label = step.text,
                    let rowX = step.x,
                    let deleteX = step.endX
                else {
                    attach("Cleanup step '\(step.name)' is missing text/row/delete coordinates; skipping")
                    return
                }
                guard let rowY = uniqueRecognizedRowNormalizedY(matching: label) else {
                    attach("Cleanup step '\(step.name)': could not uniquely locate '\(label)'; skipping rather than deleting an unknown entry")
                    return
                }
                minecraft.coordinate(withNormalizedOffset: CGVector(dx: rowX, dy: rowY)).tap()
                Thread.sleep(forTimeInterval: 2)
                attach("\(step.name) - selected matched Storage entry")
                guard let deleteY = StorageTrashControlLocator.normalizedY(
                    in: XCUIScreen.main.screenshot().image,
                    normalizedX: deleteX
                ) else {
                    attach("Cleanup step '\(step.name)' could not locate the selected trash control; skipping")
                    return
                }
                minecraft.coordinate(withNormalizedOffset: CGVector(dx: deleteX, dy: deleteY)).tap()
                Thread.sleep(forTimeInterval: 2)
                minecraft.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.635)).tap()
                Thread.sleep(forTimeInterval: 3)
                if !waitForRecognizedRowCount(below: 1, matching: label, timeout: 5) {
                    attach("Cleanup step '\(step.name)' did not remove the matched Storage entry")
                }
            case .deleteAllStored:
                guard
                    let label = step.text,
                    let rowX = step.x,
                    let deleteX = step.endX
                else {
                    attach("Cleanup step '\(step.name)' is missing text/row/delete coordinates; skipping")
                    return
                }

                // Every generated test pack uses this explicit test-only
                // display name. Recover from interrupted earlier runs by
                // deleting matching rows one at a time until none remain.
                // The cap prevents an OCR/navigation bug from looping
                // forever or expanding deletion beyond the visible matches.
                var deletedCount = 0
                for _ in 0..<12 {
                    let matchesBeforeDeletion = recognizedRowNormalizedYs(matching: label)
                    guard let rowY = matchesBeforeDeletion.min() else { break }
                    minecraft.coordinate(withNormalizedOffset: CGVector(dx: rowX, dy: rowY)).tap()
                    Thread.sleep(forTimeInterval: 2)
                    attach("\(step.name) - selected matching Storage entry \(deletedCount + 1)")
                    guard let deleteY = StorageTrashControlLocator.normalizedY(
                        in: XCUIScreen.main.screenshot().image,
                        normalizedX: deleteX
                    ) else {
                        attach("Cleanup step '\(step.name)' could not locate the selected trash control; stopping")
                        break
                    }
                    minecraft.coordinate(withNormalizedOffset: CGVector(dx: deleteX, dy: deleteY)).tap()
                    Thread.sleep(forTimeInterval: 2)
                    minecraft.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.635)).tap()
                    Thread.sleep(forTimeInterval: 3)
                    guard waitForRecognizedRowCount(
                        below: matchesBeforeDeletion.count,
                        matching: label,
                        timeout: 5
                    ) else {
                        attach("Cleanup step '\(step.name)' did not remove matching Storage entry \(deletedCount + 1); stopping")
                        break
                    }
                    deletedCount += 1
                }

                if deletedCount == 0 {
                    attach("Cleanup step '\(step.name)': found no stored pack matching '\(label)'")
                }
            default:
                try performGesture(step, in: minecraft)
            }
        } catch {
            attach("Cleanup step '\(step.name)' failed: \(error) (logged only, not failing the test)")
        }

        attach("\(step.name) (cleanup)")
    }

    /// Returns the normalized vertical center of exactly one OCR match.
    /// Cleanup must never guess: zero or duplicate labels cause the caller to
    /// skip the mutation and leave screenshot evidence instead.
    private func uniqueRecognizedRowNormalizedY(matching text: String) -> CGFloat? {
        let matches = recognizedRowNormalizedYs(matching: text)
        guard matches.count == 1 else { return nil }
        return matches[0]
    }

    private func recognizedRowNormalizedYs(matching text: String) -> [CGFloat] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        guard let image = XCUIScreen.main.screenshot().image.cgImage else { return [] }
        let orientation = visionOrientation(for: XCUIDevice.shared.orientation)
        guard (try? VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])) != nil else {
            return []
        }

        return (request.results ?? []).compactMap {
            guard $0.topCandidates(1).first?.string.localizedCaseInsensitiveContains(text) == true else {
                return nil
            }
            let box = $0.boundingBox
            return 1 - (box.origin.y + box.size.height / 2)
        }
    }

    private func waitForRecognizedRowCount(
        below previousCount: Int,
        matching text: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if recognizedRowNormalizedYs(matching: text).count < previousCount {
                return true
            }
            usleep(500_000)
        } while Date() < deadline
        return false
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
        case .ocr, .tapRecognizedRow, .deleteIfUniquelyStored, .deleteAllStored:
            // Handled by callers (`execute` hard-asserts OCR; `executeCleanupStep`
            // soft-checks OCR).
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
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        guard let image = XCUIScreen.main.screenshot().image.cgImage else {
            XCTFail("Could not create a CGImage for Minecraft OCR")
            return ""
        }

        do {
            // Minecraft reports a landscape interface while XCUIScreen emits
            // a portrait pixel buffer. Vision needs the matching orientation
            // to recognize visible Ore UI text such as world and pack names.
            try VNImageRequestHandler(cgImage: image, orientation: .left).perform([request])
        } catch {
            XCTFail("Minecraft OCR failed: \(error)")
            return ""
        }

        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

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
    let cleanupSteps: [MinecraftDeviceE2EStep]

    private enum CodingKeys: String, CodingKey {
        case enabled, expectedSwordName, steps, cleanupSteps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        expectedSwordName = try container.decode(String.self, forKey: .expectedSwordName)
        steps = try container.decode([MinecraftDeviceE2EStep].self, forKey: .steps)
        cleanupSteps = try container.decodeIfPresent([MinecraftDeviceE2EStep].self, forKey: .cleanupSteps) ?? []
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
        case ocr
        /// Cleanup-only: taps the row whose OCR label uniquely matches `text`
        /// at the configured `x` column. Skips when the match is ambiguous.
        case tapRecognizedRow
        /// Cleanup-only: uniquely locates a Storage entry, selects it, then
        /// uses Minecraft's trash and confirmation controls to delete it.
        case deleteIfUniquelyStored
        /// Cleanup-only: repeatedly deletes every visible Storage entry whose
        /// label matches the configured test-pack display name.
        case deleteAllStored
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

/// Locates Minecraft Storage's selected trash tile from its rendered pixels.
/// The tile is light gray and is bracketed horizontally by the dark action
/// bar, unlike the full-width light category headers and dialog buttons.
private enum StorageTrashControlLocator {
    static func normalizedY(in image: UIImage, normalizedX: CGFloat) -> CGFloat? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let uprightImage = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }

        guard let cgImage = uprightImage.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        guard
            width > 0,
            height > 0,
            cgImage.bitsPerPixel == 32,
            let pixelData = cgImage.dataProvider?.data,
            let pixels = CFDataGetBytePtr(pixelData)
        else { return nil }
        let bytesPerRow = cgImage.bytesPerRow

        func luminance(atNormalizedX x: CGFloat, row: Int) -> CGFloat {
            let column = min(width - 1, max(0, Int(x * CGFloat(width - 1))))
            let offset = row * bytesPerRow + column * 4
            return (
                CGFloat(pixels[offset]) * 0.2126
                    + CGFloat(pixels[offset + 1]) * 0.7152
                    + CGFloat(pixels[offset + 2]) * 0.0722
            )
        }

        let tileSamples = Array(stride(from: normalizedX - 0.022, through: normalizedX + 0.022, by: 0.005))
        let adjacentSamples = [normalizedX - 0.06, normalizedX + 0.06]
        var matchingRows: [Int] = []

        for row in Int(CGFloat(height) * 0.15)..<Int(CGFloat(height) * 0.98) {
            let brightTileFraction = CGFloat(tileSamples.filter {
                luminance(atNormalizedX: $0, row: row) >= 165
            }.count) / CGFloat(tileSamples.count)
            let adjacentIsDark = adjacentSamples.allSatisfy {
                luminance(atNormalizedX: $0, row: row) <= 120
            }
            if brightTileFraction >= 0.5, adjacentIsDark {
                matchingRows.append(row)
            }
        }

        guard !matchingRows.isEmpty else { return nil }
        let mergeGap = max(2, Int(CGFloat(height) * 0.012))
        var clusters: [[Int]] = [[matchingRows[0]]]
        for row in matchingRows.dropFirst() {
            if row - clusters[clusters.count - 1].last! <= mergeGap {
                clusters[clusters.count - 1].append(row)
            } else {
                clusters.append([row])
            }
        }

        guard let cluster = clusters.max(by: { $0.count < $1.count }),
              let first = cluster.first,
              let last = cluster.last
        else { return nil }
        return CGFloat(first + last) / 2 / CGFloat(height)
    }
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
