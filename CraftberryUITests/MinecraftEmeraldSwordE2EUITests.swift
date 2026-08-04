import Vision
import XCTest

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

    func testCraftberryEmeraldSwordCanBeImportedActivatedAndCrafted() throws {
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

        // Deactivating the imported packs is best-effort device hygiene, not
        // part of this test's acceptance signal: it must run whether the
        // test above passes or fails, and a cleanup hiccup must never turn a
        // successful crafting run into a reported failure (or mask a real
        // one). Register it as soon as `minecraft` exists so it still runs
        // if a later assertion throws.
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
            case .removeIfUniquelyActive:
                guard let label = step.text, let removeButtonX = step.x else {
                    attach("Cleanup step '\(step.name)' is missing text/x; skipping")
                    return
                }
                guard let rowY = uniqueActiveRowNormalizedY(matching: label) else {
                    attach("Cleanup step '\(step.name)': could not uniquely locate '\(label)' in the visible Active list (0 or multiple matches) — skipped rather than guessing which row to remove.")
                    return
                }
                // Bundle the Remove tap with Minecraft's "Hold on!" removal
                // confirmation here, rather than as separate config steps: a
                // separate confirm step would blindly tap the dialog's
                // position even when no row was uniquely found above (no Remove
                // tap happened), risking an unrelated tap on the Active list.
                minecraft.coordinate(withNormalizedOffset: CGVector(dx: removeButtonX, dy: rowY)).tap()
                Thread.sleep(forTimeInterval: 3)
                minecraft.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.704)).tap()
                Thread.sleep(forTimeInterval: 3)
            default:
                try performGesture(step, in: minecraft)
            }
        } catch {
            attach("Cleanup step '\(step.name)' failed: \(error) (logged only, not failing the test)")
        }

        attach("\(step.name) (cleanup)")
    }

    /// Locates the single Active-tab row whose recognized text contains
    /// `text`, returning its vertical center as a normalized XCUICoordinate
    /// offset. Returns nil (skip, don't guess) unless exactly one row matches,
    /// since Minecraft's Active pack list doesn't reliably order newly
    /// auto-activated resource packs at a fixed rank (unlike manually
    /// activated behavior packs — see docs/MINECRAFT_DEVICE_AUTOMATION.md).
    private func uniqueActiveRowNormalizedY(matching text: String) -> CGFloat? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        guard let image = XCUIScreen.main.screenshot().image.cgImage else { return nil }
        guard (try? VNImageRequestHandler(cgImage: image, orientation: .left).perform([request])) != nil else {
            return nil
        }

        let matches = (request.results ?? []).filter {
            $0.topCandidates(1).first?.string.localizedCaseInsensitiveContains(text) ?? false
        }
        guard matches.count == 1, let box = matches.first?.boundingBox else { return nil }

        // Vision's boundingBox uses a bottom-left origin in the
        // orientation-corrected image; XCUICoordinate's normalized offset
        // uses a top-left origin.
        let centerY = box.origin.y + box.size.height / 2
        return 1 - centerY
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
        case .ocr, .removeIfUniquelyActive:
            // Handled by callers (`execute` hard-asserts OCR; `executeCleanupStep`
            // soft-checks OCR and owns the whole removeIfUniquelyActive flow).
            break
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
        case ocr
        /// Cleanup-only: taps the Remove button (at fixed column `x`) for the
        /// Active-tab row whose label uniquely matches `text`, then confirms
        /// Minecraft's "Hold on!" removal dialog — but only if exactly one
        /// matching row is visible. Skips (and logs) rather than guessing
        /// when zero or multiple rows match, since resource packs don't
        /// reliably insert newly-activated entries at a fixed position (see
        /// docs/MINECRAFT_DEVICE_AUTOMATION.md).
        case removeIfUniquelyActive
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
