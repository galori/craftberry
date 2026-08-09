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
        dismissKeyboardIfPresent(in: app)

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
        dismissKeyboardIfPresent(in: app)

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

    func testDeterministicRedstoneBlockSetCanBuild() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-redstone-block-set"]
        app.launch()

        XCTAssertTrue(waitForElement("craftberry.state.editing", in: app, timeout: 8))

        let prompt = app.textViews["craftberry.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.tap()
        prompt.typeText("Generate a redstone block set crafted from redstone")
        dismissKeyboardIfPresent(in: app)

        app.buttons["craftberry.generate"].tap()
        if !waitForElement("craftberry.state.ready", in: app, timeout: 8) {
            if app.descendants(matching: .any)["craftberry.state.failed"].waitForExistence(timeout: 1) {
                XCTFail("Block set generation failed (ready not reached, failed state present): \(app.debugDescription)")
            } else {
                XCTFail("Block set generation failed (neither ready nor failed): \(app.debugDescription)")
            }
        }
        XCTAssertTrue(app.staticTexts["Redstone"].waitForExistence(timeout: 2))
    }

    func testShufflingExamplePromptsShowsDifferentSuggestions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        XCTAssertTrue(waitForElement("craftberry.state.editing", in: app, timeout: 8))

        let before = suggestionLabels(in: app)
        XCTAssertEqual(before.count, 3)

        app.buttons["craftberry.shuffleSuggestions"].tap()

        let after = suggestionLabels(in: app)
        XCTAssertEqual(after.count, 3)
        XCTAssertTrue(Set(before).isDisjoint(with: Set(after)))

        app.buttons["craftberry.suggestion.0"].tap()
        XCTAssertTrue(app.textViews["craftberry.prompt"].waitForExistence(timeout: 3))
        XCTAssertFalse((app.textViews["craftberry.prompt"].value as? String ?? "").isEmpty)
    }

    private func suggestionLabels(in app: XCUIApplication) -> [String] {
        (0..<3).compactMap { index in
            let button = app.buttons["craftberry.suggestion.\(index)"]
            guard button.waitForExistence(timeout: 3) else { return nil }
            return button.label
        }
    }

    private func waitForElement(_ identifier: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        app.descendants(matching: .any)[identifier].waitForExistence(timeout: timeout)
    }

    /// The keyboard's Done accessory button sits directly above the software keyboard, which
    /// otherwise overlaps and intercepts taps intended for the Generate button underneath it.
    private func dismissKeyboardIfPresent(in app: XCUIApplication) {
        let doneButton = app.buttons["craftberry.dismissKeyboard"]
        guard doneButton.waitForExistence(timeout: 2) else { return }
        doneButton.tap()
    }
}
