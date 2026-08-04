import XCTest

/// Drives Safari — never Craftberry — to download a `.mcaddon` served by
/// `scripts/minecraft-import.sh` and hand it off to Minecraft's own "Open in
/// Minecraft" import. This is leg 1 of physical-device Minecraft validation;
/// leg 2 (activating the pack in a world and confirming it in-game) runs
/// separately via `scripts/minecraft-mirror-drive.sh` since Minecraft's own
/// UI is not accessibility-navigable (see AGENTS.md).
///
/// Every identifier here was calibrated against a live physical device this
/// session (iOS 26.6 / this Safari + Files build) by dumping the real
/// accessibility tree at each step rather than guessing — see the inline
/// comments at each step for what was actually observed and why. One race
/// remains unresolved: tapping Safari's address bar intermittently leaves
/// the resolved text field without real keyboard focus, a widely-reported
/// XCUITest/Safari flake that several different fixes here couldn't fully
/// eliminate. scripts/minecraft-import.sh retries the whole `xcodebuild
/// test` invocation a few times to absorb it rather than trying to make this
/// one step perfectly deterministic.
private struct ElementNotFound: Error {}

private struct ImportConfig: Decodable {
    let mcaddonURL: String
    let displayName: String
}

final class MinecraftHandoffUITests: XCTestCase {
    private let minecraftBundleID = "com.mojang.minecraftpe"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDownloadsAndHandsOffToMinecraft() throws {
        // `xcodebuild test`'s TEST_RUNNER_ environment-variable forwarding is
        // reliable for the simulator but does not reach the on-device test
        // runner app, so scripts/minecraft-import.sh writes the real values
        // into this bundled resource before building instead.
        guard let configURL = Bundle(for: Self.self).url(forResource: "MinecraftImportConfig", withExtension: "json"),
              let configData = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(ImportConfig.self, from: configData) else {
            XCTFail("Could not read MinecraftImportConfig.json from the test bundle")
            return
        }
        let urlString = config.mcaddonURL

        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.terminate()
        safari.launch()

        try openURL(urlString, in: safari)
        attach(name: "After navigating to \(urlString) (\(config.displayName))")

        try confirmDownload(in: safari)
        attach(name: "After confirming download")

        // Safari's own Downloads UI on this iOS version is either absent from
        // the standard menus (confirmed: no Downloads entry in the "More"
        // menu or the Bookmarks/Reading List/History sidebar) or a transient
        // HUD that disappears before an accessibility snapshot can catch it.
        // Files is standard, stable UIKit and always has a Downloads
        // location, so drive that instead of chasing Safari's own UI further.
        let fileNameHint = URL(string: urlString)?.lastPathComponent ?? "mcaddon"

        // Deleting the downloaded file from Files/iCloud Drive is best-effort
        // device hygiene, not part of this test's acceptance signal: it must
        // run whether the test above passes or fails, and a cleanup hiccup
        // must never affect this test's own pass/fail result. Without this,
        // repeated runs pile up stale downloads — 273 stale items had
        // already accumulated in Downloads from prior manual use before this
        // existed (see `openDownloadedFile` below). Mirrors the same
        // teardown pattern in MinecraftEmeraldSwordE2EUITests.
        addTeardownBlock { [self] in
            deleteDownloadedFile(matching: fileNameHint)
        }

        let files = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
        try openDownloadedFile(in: files, matching: fileNameHint)
        attach(name: "After opening downloaded file in Files")

        try handOffToMinecraft(in: files)
        attach(name: "After tapping Minecraft handoff")

        let minecraft = XCUIApplication(bundleIdentifier: minecraftBundleID)
        XCTAssertTrue(
            minecraft.wait(for: .runningForeground, timeout: 20),
            "Minecraft did not come to the foreground after the handoff; the pack import likely did not complete."
        )
    }

    private func openURL(_ urlString: String, in safari: XCUIApplication) throws {
        // Safari's address bar has a well-known XCUITest flake: tapping it
        // sometimes leaves whatever "textField" resolves as
        // .firstMatch/"Address"/"URL" without real keyboard focus ("Neither
        // element nor any descendant has keyboard focus"), and typeText()
        // can't be retried in-process because a synthesis failure aborts the
        // test directly via XCTFail rather than throwing. Live experiments
        // this session (fixed delays, double-taps, waiting for the keyboard,
        // narrowing/widening the candidate identifiers) all still hit it
        // intermittently — this looks like the same class of issue widely
        // reported for Safari's URL bar specifically, not something fixable
        // by better element targeting alone. scripts/minecraft-import.sh
        // retries the whole `xcodebuild test` invocation a few times instead
        // of trying to eliminate the race here.
        let addressBarCandidates = [
            safari.buttons["URL"],
            safari.otherElements["URL"],
            safari.textFields["Address"],
            safari.textFields["URL"]
        ]
        let addressBar = try tapFirstExisting(addressBarCandidates, timeout: 10, description: "Safari address bar")

        let addressField = safari.textFields.firstMatch
        XCTAssertTrue(addressField.waitForExistence(timeout: 5), "Address text field did not appear after tapping \(addressBar)")
        addressField.tap()
        XCTAssertTrue(
            safari.keyboards.element.waitForExistence(timeout: 5),
            "Keyboard did not appear after tapping the address field"
        )
        addressField.typeText(urlString)
        addressField.typeText("\n")
    }

    private func confirmDownload(in safari: XCUIApplication) throws {
        // Safari shows a "Do you want to download <file>?" confirmation
        // sheet before a non-renderable file type (like .mcaddon) actually
        // downloads; confirmed via screenshot on a live device.
        let downloadCandidates = [
            safari.buttons["Download"],
            safari.alerts.buttons["Download"],
            safari.sheets.buttons["Download"]
        ]
        _ = try tapFirstExisting(downloadCandidates, timeout: 10, description: "Download confirmation dialog")
    }

    private func openDownloadedFile(in files: XCUIApplication, matching fileNameHint: String) throws {
        files.terminate()
        files.launch()

        // A prior run that failed mid-flow can leave a stale QuickLook
        // preview overlay presented (confirmed live: its dimming overlay was
        // still in the tree and made the file grid underneath permanently
        // non-hittable). Dismiss it before doing anything else.
        if let doneButton = firstExisting([files.buttons["QLOverlayDoneButtonAccessibilityIdentifier"]], timeout: 2) {
            doneButton.tap()
        }
        dumpTree("Files app after launch", in: files)

        // Files resumes whatever folder was last browsed (observed: it opened
        // straight into an old "iCloud Drive/craftberry" folder from prior
        // manual use). Backing out just one level landed in an unrelated
        // "iCloud Drive/Downloads" folder (273 stale items) rather than the
        // true root-level Downloads location, so back out fully to the root
        // Locations list (no BackButton left) rather than stopping on the
        // first "Downloads"-labeled cell.
        for _ in 0..<6 {
            guard let back = firstExisting([files.buttons["BackButton"]], timeout: 3) else {
                break
            }
            back.tap()
            usleep(500_000)
        }
        dumpTree("Files app after backing out to root", in: files)

        // Files' resumed state is inconsistent across runs: sometimes backing
        // out to the true root lands on the Locations list (Downloads still
        // needs a tap), other times it resumes directly inside the real
        // Downloads folder (confirmed live: the just-downloaded file was
        // already visible with no "Downloads" cell present). Only tap if a
        // Downloads location cell is actually there.
        let downloadsCandidates = [
            files.staticTexts["Downloads"],
            files.buttons["Downloads"],
            files.cells["Downloads"],
            files.cells.staticTexts["Downloads"]
        ]
        if let downloadsLocation = firstExisting(downloadsCandidates, timeout: 3) {
            downloadsLocation.tap()
            dumpTree("Files app after opening Downloads", in: files)
        }

        // Predicate-based .containing()/.matching() queries against these
        // grid cells report exists == true but never isHittable, confirmed
        // live (polled for 10s while "Find the ... Cell" kept succeeding).
        // Files' cell identifiers are exactly "<filename>, mcaddon", so use
        // direct exact-identifier lookups instead, matching every other
        // successful tap in this test.
        let fileCandidates = [
            files.cells["\(fileNameHint), mcaddon"],
            files.staticTexts[fileNameHint]
        ]
        _ = try tapFirstExisting(fileCandidates, timeout: 10, description: "Downloaded .mcaddon file in Files app")
        dumpTree("Files app after tapping the file", in: files)
    }

    private func handOffToMinecraft(in app: XCUIApplication) throws {
        // QuickLook exposes a direct "Open in Minecraft" button
        // (QLOverlayOpenInButtonAccessibilityIdentifier) once iOS resolves a
        // handler for the file type — confirmed live in a leftover overlay
        // from a prior run, alongside QLOverlayDefaultActionButtonAccessibilityIdentifier
        // ("Share") as the general share-sheet fallback. No need to go
        // through Actions Menu / the share sheet at all.
        let openInCandidates = [
            app.buttons["QLOverlayOpenInButtonAccessibilityIdentifier"],
            app.buttons["Minecraft"],
            app.collectionViews.buttons["Minecraft"],
            app.staticTexts["Minecraft"]
        ]
        _ = try tapFirstExisting(openInCandidates, timeout: 10, description: "Minecraft Open In button")
    }

    /// Best-effort cleanup: deletes the just-downloaded `.mcaddon` from Files
    /// so repeated runs of this test don't accumulate stale downloads. Never
    /// calls `XCTFail` — unlike `tapFirstExisting`, every lookup here uses
    /// the non-fatal `firstExisting` and simply logs and returns if a step
    /// can't be completed, since a cleanup hiccup must not affect this
    /// test's own pass/fail result.
    private func deleteDownloadedFile(matching fileNameHint: String) {
        let files = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
        files.terminate()
        files.launch()

        if let doneButton = firstExisting([files.buttons["QLOverlayDoneButtonAccessibilityIdentifier"]], timeout: 2) {
            doneButton.tap()
        }

        for _ in 0..<6 {
            guard let back = firstExisting([files.buttons["BackButton"]], timeout: 3) else { break }
            back.tap()
            usleep(500_000)
        }

        let downloadsCandidates = [
            files.staticTexts["Downloads"],
            files.buttons["Downloads"],
            files.cells["Downloads"],
            files.cells.staticTexts["Downloads"]
        ]
        if let downloadsLocation = firstExisting(downloadsCandidates, timeout: 3) {
            downloadsLocation.tap()
        }

        let fileCandidates = [
            files.cells["\(fileNameHint), mcaddon"],
            files.staticTexts[fileNameHint]
        ]
        guard let fileCell = firstExisting(fileCandidates, timeout: 10) else {
            attach(name: "Cleanup: could not find downloaded file '\(fileNameHint)' to delete (logged only, not failing the test)")
            return
        }

        fileCell.press(forDuration: 1.0)

        // Confirmed live: a file downloaded via Safari's Downloads shows
        // "Remove Download" in its context menu, not "Delete" — the latter
        // is Files' generic destructive action for files it owns outright,
        // but a Downloads entry is a placeholder over the Safari download,
        // so its removal action is named differently. Check for it first.
        let deleteMenuCandidates = [
            files.buttons["Remove Download"],
            files.menuItems["Remove Download"],
            files.buttons["Delete"],
            files.menuItems["Delete"],
            files.collectionViews.buttons["Delete"]
        ]
        guard let deleteButton = firstExisting(deleteMenuCandidates, timeout: 5) else {
            attach(name: "Cleanup: could not find a removal action in the context menu for '\(fileNameHint)' (logged only, not failing the test)")
            return
        }
        deleteButton.tap()

        // Some iOS versions show a further confirmation ("Delete" in an
        // alert); others delete immediately. Tap it if present; otherwise
        // this is a harmless no-op since the file is already gone.
        let confirmCandidates = [
            files.alerts.buttons["Delete"],
            files.sheets.buttons["Delete"]
        ]
        if let confirmButton = firstExisting(confirmCandidates, timeout: 3) {
            confirmButton.tap()
        }

        attach(name: "Cleanup: deleted downloaded file '\(fileNameHint)' from Files")
    }

    private func dumpTree(_ label: String, in app: XCUIApplication) {
        print("=== ACCESSIBILITY TREE \(label) ===")
        print(app.debugDescription)
        print("=== END ACCESSIBILITY TREE (\(label)) ===")
    }

    private func firstExisting(_ candidates: [XCUIElement], timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for candidate in candidates where candidate.exists && candidate.isHittable {
                return candidate
            }
            usleep(200_000)
        } while Date() < deadline
        return nil
    }

    @discardableResult
    private func tapFirstExisting(_ candidates: [XCUIElement], timeout: TimeInterval, description: String) throws -> XCUIElement {
        if let element = firstExisting(candidates, timeout: timeout) {
            element.tap()
            return element
        }

        attach(name: "Failed to find: \(description)")
        XCTFail("None of the candidate elements for '\(description)' appeared within \(timeout)s")
        throw ElementNotFound()
    }

    private func attach(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
