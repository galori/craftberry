import XCTest

/// A USB/XCTest proof that Bedrock accepts a device-level coordinate gesture.
///
/// This deliberately does not use accessibility lookup: Minecraft's Ore UI
/// exposes no useful accessibility elements. The initial coordinate is the
/// centre of the Creative inventory search field, calibrated on the iPhone
/// 16e while Minecraft is in landscape. It is normalized to Minecraft's
/// application frame, so it is not tied to a particular mirrored-window size.
final class MinecraftCoordinateTouchUITests: XCTestCase {
    private let minecraftBundleID = "com.mojang.minecraftpe"
    private let creativeSearchField = CGVector(dx: 0.265, dy: 0.150)

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMinecraftReceivesCoordinateTapInCreativeSearch() throws {
        let minecraft = XCUIApplication(bundleIdentifier: minecraftBundleID)
        minecraft.launch()

        XCTAssertTrue(
            minecraft.wait(for: .runningForeground, timeout: 20),
            "Minecraft did not come to the foreground. Keep it installed, unlocked, and connected over USB."
        )

        attach("Before XCTest coordinate tap")
        minecraft.coordinate(withNormalizedOffset: creativeSearchField).tap()

        // A focused search field opens Minecraft's on-screen keyboard. Give
        // the custom renderer one frame cycle before recording proof.
        sleep(1)
        attach("After XCTest coordinate tap")
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
