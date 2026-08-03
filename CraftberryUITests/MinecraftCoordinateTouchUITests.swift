import XCTest

/// A USB/XCTest proof that Bedrock accepts a device-level coordinate gesture.
///
/// This deliberately does not use accessibility lookup: Minecraft's Ore UI
/// exposes no useful accessibility elements. The coordinate is the centre of
/// the main-menu Play button on the iPhone 16e in landscape. It is normalized
/// to Minecraft's application frame, so it is not tied to a particular
/// mirrored-window size.
final class MinecraftCoordinateTouchUITests: XCTestCase {
    private let minecraftBundleID = "com.mojang.minecraftpe"
    private let mainMenuPlayButton = CGVector(dx: 0.500, dy: 0.443)

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMinecraftReceivesCoordinateTapOnPlay() throws {
        let minecraft = XCUIApplication(bundleIdentifier: minecraftBundleID)
        minecraft.launch()

        XCTAssertTrue(
            minecraft.wait(for: .runningForeground, timeout: 20),
            "Minecraft did not come to the foreground. Keep it installed, unlocked, and connected over USB."
        )

        // Minecraft renders its own loading screen, so becoming foreground is
        // not enough to establish that Ore UI is ready. On the physical 16e,
        // eight seconds covers a cold launch with margin and lands on the
        // deterministic main menu.
        sleep(8)

        attach("Before tapping Minecraft Play")
        minecraft.coordinate(withNormalizedOffset: mainMenuPlayButton).tap()

        sleep(2)
        attach("After tapping Minecraft Play")
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
