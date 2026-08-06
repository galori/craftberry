import XCTest

enum MinecraftE2EError: LocalizedError {
    case missingResource
    case unavailableElement(String)

    var errorDescription: String? {
        switch self {
        case .missingResource:
            "MinecraftDeviceE2EConfig.json is missing from the UI-test bundle."
        case .unavailableElement(let description):
            "The expected UI element was unavailable: \(description)."
        }
    }
}

extension XCTestCase {
    func waitForAppElement(_ identifier: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        app.descendants(matching: .any)[identifier].waitForExistence(timeout: timeout)
    }

    @discardableResult
    func tapFirstHittable(
        _ candidates: [XCUIElement],
        timeout: TimeInterval,
        description: String
    ) throws -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for candidate in candidates where candidate.exists && candidate.isHittable {
                candidate.tap()
                return candidate
            }
            usleep(200_000)
        } while Date() < deadline

        attachScreenshot("Failed to find \(description)")
        XCTFail("Could not find \(description) within \(timeout) seconds")
        throw MinecraftE2EError.unavailableElement(description)
    }

    func attachAccessibilityTree(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = "\(name) accessibility tree"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
