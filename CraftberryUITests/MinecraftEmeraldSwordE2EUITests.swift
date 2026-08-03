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

    func testCraftberryEmeraldSwordCanBeImportedActivatedAndCrafted() throws {
        let configuration = try loadConfiguration()
        guard configuration.enabled else {
            throw XCTSkip("This is a physical-device acceptance test. Calibrate and enable MinecraftDeviceE2EConfig.json before running it on the dedicated iPhone.")
        }

        let craftberry = XCUIApplication()
        craftberry.launchArguments = ["--ui-testing", "--ui-testing-emerald-sword"]
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

        // Minecraft's share extension imports both nested .mcpack files from
        // the exported .mcaddon. This is deliberately the app's export path,
        // rather than the standalone Safari fixture path.
        try tapFirstExisting(
            [
                craftberry.buttons["Minecraft"],
                craftberry.collectionViews.buttons["Minecraft"],
                craftberry.staticTexts["Minecraft"]
            ],
            in: craftberry,
            timeout: 12,
            description: "Minecraft in Craftberry's export share sheet"
        )

        let minecraft = XCUIApplication(bundleIdentifier: minecraftBundleID)
        XCTAssertTrue(
            minecraft.wait(for: .runningForeground, timeout: 30),
            "Minecraft did not open after exporting the .mcaddon from Craftberry."
        )
        attach("Minecraft after importing Craftberry's Emerald Test Sword")

        for step in configuration.steps {
            try execute(step, in: minecraft, expectedSwordName: configuration.expectedSwordName)
        }
    }

    private func execute(
        _ step: MinecraftDeviceE2EStep,
        in minecraft: XCUIApplication,
        expectedSwordName: String
    ) throws {
        switch step.action {
        case .wait:
            Thread.sleep(forTimeInterval: step.seconds ?? 1)
        case .tap:
            guard let x = step.x, let y = step.y else {
                throw ConfigurationError.missingCoordinate(step.name)
            }
            minecraft.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
        case .type:
            guard let text = step.text else {
                throw ConfigurationError.missingText(step.name)
            }
            minecraft.typeText(text)
        case .ocr:
            let expected = step.text == "$EXPECTED_SWORD_NAME" ? expectedSwordName : step.text
            guard let expected, !expected.isEmpty else {
                throw ConfigurationError.missingText(step.name)
            }
            XCTAssertTrue(
                recognizedText().localizedCaseInsensitiveContains(expected),
                "OCR did not find '\(expected)' after \(step.name). Recalibrate this step if Minecraft's UI changed."
            )
        }

        attach(step.name)
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
            try VNImageRequestHandler(cgImage: image).perform([request])
        } catch {
            XCTFail("Minecraft OCR failed: \(error)")
            return ""
        }

        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
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
}

private struct MinecraftDeviceE2EStep: Decodable {
    enum Action: String, Decodable {
        case wait
        case tap
        case type
        case ocr
    }

    let name: String
    let action: Action
    let x: CGFloat?
    let y: CGFloat?
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
