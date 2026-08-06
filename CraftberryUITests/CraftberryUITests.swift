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

    func testDeterministicRedstoneToolSetCanBuild() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-redstone-tool-set"]
        app.launch()

        XCTAssertTrue(waitForElement("craftberry.state.editing", in: app, timeout: 8))

        let prompt = app.textViews["craftberry.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.tap()
        prompt.typeText("Generate a redstone tool set crafted from redstone")

        app.buttons["craftberry.generate"].tap()
        XCTAssertTrue(waitForElement("craftberry.state.ready", in: app, timeout: 8))
        XCTAssertTrue(app.staticTexts["Redstone"].waitForExistence(timeout: 2))
        XCTAssertTrue(waitForElement("craftberry.recipeBook", in: app, timeout: 2))
        XCTAssertTrue(app.staticTexts["6"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Items"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Recipes"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Redstone Sword"].waitForExistence(timeout: 2))
        app.staticTexts["Redstone Sword"].tap()
        XCTAssertTrue(waitForElement("craftberry.recipeDetail.redstone_uitest_sword", in: app, timeout: 3))
        XCTAssertTrue(app.staticTexts["2 Redstone Ingot + Stick -> Redstone Sword"].waitForExistence(timeout: 2))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(waitForElement("craftberry.state.ready", in: app, timeout: 3))

        app.buttons["craftberry.build"].tap()
        XCTAssertTrue(waitForElement("craftberry.state.built", in: app, timeout: 10))
    }

    private func waitForElement(_ identifier: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        app.descendants(matching: .any)[identifier].waitForExistence(timeout: timeout)
    }
}
