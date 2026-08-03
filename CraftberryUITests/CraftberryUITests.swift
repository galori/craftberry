import XCTest

final class CraftberryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDeterministicSwordBuildCanOpenShareSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        XCTAssertTrue(waitForElement("craftberry.state.editing", in: app, timeout: 8))

        let prompt = app.textViews["craftberry.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.tap()
        prompt.typeText("A cyan sword, 14 damage, crafted from diamonds")

        app.buttons["craftberry.generate"].tap()
        XCTAssertTrue(waitForElement("craftberry.state.generating", in: app, timeout: 3))
        XCTAssertTrue(waitForElement("craftberry.state.ready", in: app, timeout: 8))

        app.buttons["craftberry.build"].tap()
        XCTAssertTrue(waitForElement("craftberry.state.building", in: app, timeout: 3))
        XCTAssertTrue(waitForElement("craftberry.state.built", in: app, timeout: 8))

        app.buttons["craftberry.export"].tap()
        XCTAssertTrue(waitForElement("ActivityListView", in: app, timeout: 8))

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Craftberry share sheet"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForElement(_ identifier: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        app.descendants(matching: .any)[identifier].waitForExistence(timeout: timeout)
    }
}
