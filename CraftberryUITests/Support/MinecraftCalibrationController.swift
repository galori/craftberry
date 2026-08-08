import CoreGraphics
import Foundation
import ImageIO
import XCTest

/// Drives a precomputed `[MinecraftPhasedStep]` plan one step at a time, as
/// directed by the JSON controller on the Mac. All UI work is delegated to the
/// injected executors so the controller itself is testable without a live
/// `XCUIApplication`.
final class MinecraftCalibrationController {
    let scenarioId: String
    let allSteps: [MinecraftPhasedStep]

    private(set) var cursor: Int = 0
    private(set) var lastResult: MinecraftStepResult?

    private let executePlanned: (MinecraftPhasedStep) -> MinecraftStepResult
    private let executeAdHoc: (MinecraftStep.Action) -> MinecraftStepResult
    private let screenshotBase64Provider: () -> String?
    private let recognizedTextProvider: () -> String?

    init(
        scenarioId: String,
        allSteps: [MinecraftPhasedStep],
        executePlanned: @escaping (MinecraftPhasedStep) -> MinecraftStepResult,
        executeAdHoc: @escaping (MinecraftStep.Action) -> MinecraftStepResult,
        screenshotBase64Provider: @escaping () -> String? = { nil },
        recognizedTextProvider: @escaping () -> String? = { nil }
    ) {
        self.scenarioId = scenarioId
        self.allSteps = allSteps
        self.executePlanned = executePlanned
        self.executeAdHoc = executeAdHoc
        self.screenshotBase64Provider = screenshotBase64Provider
        self.recognizedTextProvider = recognizedTextProvider
    }

    /// Convenience for the live device: wraps a real `MinecraftStepExecutor`.
    convenience init(
        scenario: MinecraftE2EScenario,
        configSteps: [MinecraftStep],
        craftingPlan: MinecraftCraftingPlan,
        compiler: MinecraftCraftingPlanCompiler = MinecraftCraftingPlanCompiler(),
        app: XCUIApplication,
        executor: MinecraftStepExecutor,
        resolve: @escaping (String) -> String
    ) {
        let phasedConfig = configSteps.phased(as: .config)
        let phasedCrafting = compiler.compile(craftingPlan).phased(as: .crafting)
        let all = phasedConfig + phasedCrafting
        let scenarioId = scenario.launchArgument

        // Placed in a convenience init so the stored closures capture the
        // executor/app/resolve without the caller having to wire them.
        self.init(
            scenarioId: scenarioId,
            allSteps: all,
            executePlanned: { step in
                // XCTest interactions must happen on the main thread.
                if Thread.isMainThread {
                    return executor.execute(step, in: app, resolve: resolve)
                } else {
                    var result: MinecraftStepResult!
                    DispatchQueue.main.sync {
                        result = executor.execute(step, in: app, resolve: resolve)
                    }
                    return result
                }
            },
            executeAdHoc: { action in
                let adhoc = MinecraftPhasedStep(id: "calibration:adhoc", name: "Calibration ad hoc", action: action)
                if Thread.isMainThread {
                    return executor.execute(adhoc, in: app, resolve: resolve)
                } else {
                    var result: MinecraftStepResult!
                    DispatchQueue.main.sync {
                        result = executor.execute(adhoc, in: app, resolve: resolve)
                    }
                    return result
                }
            },
            screenshotBase64Provider: {
                // Capture and base64-encode the current screen. Must run on main.
                var base64: String?
                let block = {
                    guard let cgImage = XCUIScreen.main.screenshot().image.cgImage else { return }
                    // Encode as PNG via ImageIO to avoid UIKit dependency in tests.
                    let data = NSMutableData()
                    guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil) else { return }
                    CGImageDestinationAddImage(dest, cgImage, nil)
                    guard CGImageDestinationFinalize(dest) else { return }
                    base64 = (data as Data).base64EncodedString()
                }
                if Thread.isMainThread {
                    block()
                } else {
                    DispatchQueue.main.sync { block() }
                }
                return base64
            },
            recognizedTextProvider: {
                var text: String?
                let block = { text = MinecraftOCRInspector().recognizedText() }
                if Thread.isMainThread {
                    block()
                } else {
                    DispatchQueue.main.sync { block() }
                }
                return text
            }
        )
    }

    // MARK: - Request handling

    func handle(_ request: MinecraftCalibrationRequest) -> MinecraftCalibrationResponse {
        switch request.command {
        case "status":
            return response(success: true)
        case "list_steps", "list-steps":
            return response(success: true, includeSteps: true)
        case "observe":
            return response(success: true, includeScreenshot: true, includeOCR: request.ocr ?? false)
        case "step":
            return handleStep(includeScreenshot: false, includeOCR: false)
        case "run_until", "run-until":
            guard let target = request.target, !target.isEmpty else {
                return errorResponse("run_until requires a target step id or name")
            }
            return handleRunUntil(target: target)
        case "mark_complete", "mark-complete":
            return handleMarkComplete()
        case "select_step", "select-step":
            guard let target = request.target, !target.isEmpty else {
                return errorResponse("select_step requires a target step id or name")
            }
            return handleSelectStep(target: target)
        case "tap":
            guard let x = request.x, let y = request.y else {
                return errorResponse("tap requires x and y")
            }
            return handleAdHoc(.tap(x: CGFloat(x), y: CGFloat(y)))
        case "drag":
            guard let x = request.x, let y = request.y, let endX = request.endX, let endY = request.endY else {
                return errorResponse("drag requires x, y, endX, endY")
            }
            return handleAdHoc(.drag(x: CGFloat(x), y: CGFloat(y), endX: CGFloat(endX), endY: CGFloat(endY)))
        case "swipe_up", "swipe-up":
            return handleAdHoc(.swipeUp)
        case "keyboard_text", "keyboard-text":
            guard let text = request.text else {
                return errorResponse("keyboard_text requires text")
            }
            return handleAdHoc(.keyboardText(text))
        case "numeric_keyboard_text", "numeric-keyboard-text":
            guard let text = request.text else {
                return errorResponse("numeric_keyboard_text requires text")
            }
            return handleAdHoc(.numericKeyboardText(text))
        case "chat_command", "chat-command":
            guard let text = request.text else {
                return errorResponse("chat_command requires text")
            }
            return handleAdHoc(.chatCommand(text))
        case "wait":
            guard let seconds = request.seconds else {
                return errorResponse("wait requires seconds")
            }
            Thread.sleep(forTimeInterval: seconds)
            // wait is ad-hoc: never advances cursor.
            return response(success: true)
        default:
            return errorResponse("unknown command '\(request.command)'")
        }
    }

    // MARK: - Command implementations

    private func handleStep(includeScreenshot: Bool, includeOCR: Bool) -> MinecraftCalibrationResponse {
        guard cursor < allSteps.count else {
            return errorResponse("all steps already completed")
        }
        let step = allSteps[cursor]
        let result = executePlanned(step)
        lastResult = result
        if result.succeeded {
            cursor += 1
            return response(success: true, includeScreenshot: includeScreenshot, includeOCR: includeOCR)
        } else {
            // Failure retains cursor so the operator can retry or inspect.
            return response(success: false, error: result.failureReason, includeScreenshot: includeScreenshot, includeOCR: includeOCR)
        }
    }

    private func handleRunUntil(target: String) -> MinecraftCalibrationResponse {
        guard let targetIndex = index(of: target) else {
            return errorResponse("no step matching '\(target)'")
        }
        if cursor >= allSteps.count {
            return errorResponse("all steps already completed")
        }
        if targetIndex < cursor {
            return errorResponse("target '\(target)' is behind the current cursor \(currentCursorId() ?? "done")")
        }
        if targetIndex == cursor {
            // Already at target: stop before it, do nothing.
            return response(success: true)
        }
        // Run until just before target, stopping immediately on failure.
        while cursor < targetIndex {
            let step = allSteps[cursor]
            let result = executePlanned(step)
            lastResult = result
            if !result.succeeded {
                return response(success: false, error: result.failureReason)
            }
            cursor += 1
        }
        return response(success: true)
    }

    private func handleMarkComplete() -> MinecraftCalibrationResponse {
        guard cursor < allSteps.count else {
            return errorResponse("all steps already completed")
        }
        let step = allSteps[cursor]
        lastResult = .success(step)
        cursor += 1
        return response(success: true)
    }

    private func handleSelectStep(target: String) -> MinecraftCalibrationResponse {
        guard let targetIndex = index(of: target) else {
            return errorResponse("no step matching '\(target)'")
        }
        // Explicitly does not restore Minecraft UI state — cursor only.
        cursor = targetIndex
        // lastResult is left as-is; the selected step has not been executed.
        return response(success: true)
    }

    private func handleAdHoc(_ action: MinecraftStep.Action) -> MinecraftCalibrationResponse {
        let result = executeAdHoc(action)
        lastResult = result
        // Never advances cursor, even on success.
        if result.succeeded {
            return response(success: true)
        } else {
            return response(success: false, error: result.failureReason)
        }
    }

    // MARK: - Helpers

    private func index(of target: String) -> Int? {
        // Exact id match first, then name.
        if let byId = allSteps.firstIndex(where: { $0.id == target }) {
            return byId
        }
        return allSteps.firstIndex(where: { $0.name == target })
    }

    private func currentCursorId() -> String? {
        guard cursor < allSteps.count else { return nil }
        return allSteps[cursor].id
    }

    private func phaseForCursor() -> String? {
        guard cursor < allSteps.count else {
            // All done — report last phase or nil.
            return allSteps.last?.id.components(separatedBy: ":").first
        }
        return allSteps[cursor].id.components(separatedBy: ":").first
    }

    private func response(
        success: Bool,
        error: String? = nil,
        includeSteps: Bool = false,
        includeScreenshot: Bool = false,
        includeOCR: Bool = false
    ) -> MinecraftCalibrationResponse {
        let current = cursor < allSteps.count ? MinecraftCalibrationStepInfo(from: allSteps[cursor]) : nil
        let next: MinecraftCalibrationStepInfo? = {
            let nextIndex = cursor + 1
            guard nextIndex < allSteps.count else { return nil }
            return MinecraftCalibrationStepInfo(from: allSteps[nextIndex])
        }()
        return MinecraftCalibrationResponse(
            success: success,
            error: error,
            scenario: scenarioId,
            phase: phaseForCursor(),
            cursor: currentCursorId(),
            completedCount: cursor,
            totalCount: allSteps.count,
            currentStep: current,
            nextStep: next,
            lastResult: lastResult.map { MinecraftCalibrationResultInfo(from: $0) },
            steps: includeSteps ? allSteps.map { MinecraftCalibrationStepInfo(from: $0) } : nil,
            screenshotBase64: includeScreenshot ? screenshotBase64Provider() : nil,
            recognizedText: includeOCR ? recognizedTextProvider() : nil
        )
    }

    private func errorResponse(_ message: String) -> MinecraftCalibrationResponse {
        var r = response(success: false, error: message)
        // Preserve state fields even on error.
        return r
    }
}
