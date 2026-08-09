import XCTest

enum MinecraftE2EPhase: String {
    case config
    case crafting
}

/// A `MinecraftStep` paired with a stable, run-local ID such as `config:12` or `crafting:4`.
///
/// The ID is derived from the step's position within its phase rather than stored in the source
/// JSON/compiler output, so a debugger console or remote controller can address "the step after
/// this one" across turns without the array-index churn that comes from editing steps upstream.
struct MinecraftPhasedStep: Equatable {
    let id: String
    let name: String
    let action: MinecraftStep.Action
}

extension Array where Element == MinecraftStep {
    func phased(as phase: MinecraftE2EPhase) -> [MinecraftPhasedStep] {
        enumerated().map { index, step in
            MinecraftPhasedStep(id: "\(phase.rawValue):\(index + 1)", name: step.name, action: step.action)
        }
    }
}

struct MinecraftStepResult {
    let step: MinecraftPhasedStep
    let succeeded: Bool
    let failureReason: String?

    static func success(_ step: MinecraftPhasedStep) -> MinecraftStepResult {
        MinecraftStepResult(step: step, succeeded: true, failureReason: nil)
    }

    static func failure(_ step: MinecraftPhasedStep, reason: String) -> MinecraftStepResult {
        MinecraftStepResult(step: step, succeeded: false, failureReason: reason)
    }
}

/// Executes a single step's gestures, keyboard input, commands, OCR, or pixel checks against a live
/// Minecraft app and reports what happened as a `MinecraftStepResult`.
///
/// Kept independent of `XCTestCase` — it never calls `XCTAssert`/`XCTFail` itself — so the same
/// executor can back both the production harness (which converts a failed result into an XCTest
/// failure) and an interactive controller that wants to know a step failed without ending the run.
final class MinecraftStepExecutor {
    private let commandKeyboard: MinecraftCommandKeyboard
    private let ocr: MinecraftOCRInspector
    private let pixels: MinecraftPixelInspector
    private let onIntermediateScreenshot: (String) -> Void

    init(
        commandKeyboard: MinecraftCommandKeyboard = MinecraftCommandKeyboard(),
        ocr: MinecraftOCRInspector = MinecraftOCRInspector(),
        pixels: MinecraftPixelInspector = MinecraftPixelInspector(),
        onIntermediateScreenshot: @escaping (String) -> Void = { _ in }
    ) {
        self.commandKeyboard = commandKeyboard
        self.ocr = ocr
        self.pixels = pixels
        self.onIntermediateScreenshot = onIntermediateScreenshot
    }

    func execute(_ step: MinecraftPhasedStep, in minecraft: XCUIApplication, resolve: (String) -> String) -> MinecraftStepResult {
        switch step.action {
        case .wait(let seconds):
            Thread.sleep(forTimeInterval: seconds)
            return .success(step)
        case .tap(let x, let y):
            minecraft.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
            return .success(step)
        case .drag(let x, let y, let endX, let endY):
            let start = minecraft.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
            let end = minecraft.coordinate(withNormalizedOffset: CGVector(dx: endX, dy: endY))
            // A fast synthesized flick (a plain press-then-drag) reads to Minecraft's custom UI
            // engine as a swipe-to-go-back gesture on some screens (confirmed live: it silently
            // bounced the Edit World pack-settings screen back to the world list instead of
            // scrolling). Slow velocity plus a brief hold at the end makes it land as a deliberate
            // scroll instead.
            start.press(forDuration: 0.2, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
            return .success(step)
        case .swipeUp:
            minecraft.swipeUp()
            return .success(step)
        case .typeText(let text):
            minecraft.typeText(text)
            return .success(step)
        case .keyboardText(let text):
            for character in text {
                minecraft.keyboardKey(String(character)).tap()
            }
            minecraft.buttons["Done"].tap()
            return .success(step)
        case .numericKeyboardText(let text):
            let numericPlane = minecraft.keyboardKey("numbers")
            guard numericPlane.waitForExistence(timeout: 3) else {
                return .failure(step, reason: "Could not find the keyboard's numeric-plane switch, so \(step.name) would type into the letters plane.")
            }
            numericPlane.tap()
            for character in text {
                minecraft.keyboardKey(String(character)).tap()
            }
            minecraft.buttons["Done"].tap()
            return .success(step)
        case .chatCommand(let text):
            return sendChatCommand(text, in: minecraft, step: step)
        case .assertText(let rawExpected):
            let expected = resolve(rawExpected)
            // Allow `|`-separated alternatives for dialogs that vary by Minecraft version/state
            // (e.g. the pack-activation warning alternates between "Using Add-Ons" and "Update world?").
            let alternatives = expected.split(separator: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let candidates = alternatives.isEmpty ? [expected] : alternatives
            var matched = false
            for candidate in candidates {
                if ocr.waitForRecognizedText(candidate, timeout: 3) {
                    matched = true
                    break
                }
            }
            // Fallback: try the full string as a single literal (covers legacy single-value configs).
            if !matched, candidates.count > 1, ocr.waitForRecognizedText(expected, timeout: 2) {
                matched = true
            }
            guard matched else {
                return .failure(step, reason: "OCR did not find '\(expected)' after \(step.name). Recalibrate this step if Minecraft's UI changed.")
            }
            return .success(step)
        case .assertPixels(let expectation):
            guard pixels.matches(expectation) else {
                return .failure(step, reason: "The expected pixel cluster was not visible after \(step.name).")
            }
            return .success(step)
        }
    }

    private func sendChatCommand(_ text: String, in minecraft: XCUIApplication, step: MinecraftPhasedStep) -> MinecraftStepResult {
        minecraft.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.0325)).tap()
        Thread.sleep(forTimeInterval: 2)
        onIntermediateScreenshot("Chat screen after tapping the chat button")
        minecraft.coordinate(withNormalizedOffset: CGVector(dx: 0.495, dy: 0.935)).tap()
        Thread.sleep(forTimeInterval: 2)
        onIntermediateScreenshot("Chat screen after focusing the command input field")
        // The command keyboard drives raw key elements, so a missing keyboard here would fail deep
        // inside key lookup with no indication of which tap missed. Check it up front instead.
        guard minecraft.keyboards.element.waitForExistence(timeout: 5) else {
            return .failure(step, reason: "The on-screen keyboard did not appear after focusing Minecraft's chat input, so the command could not be typed. Recalibrate the chat-input tap against the attached chat screenshots.")
        }
        // Per-key taps rather than typeText: Minecraft's chat field is custom-drawn and never reports
        // keyboard focus to the accessibility layer, so typeText fails with "Neither element nor any
        // descendant has keyboard focus" even while the software keyboard is plainly up.
        commandKeyboard.type(text, in: minecraft)
        Thread.sleep(forTimeInterval: 1)
        onIntermediateScreenshot("Chat input after typing the command")
        minecraft.coordinate(withNormalizedOffset: CGVector(dx: 0.9275, dy: 0.434)).tap()
        Thread.sleep(forTimeInterval: 2)
        return .success(step)
    }
}
