import Foundation

// MARK: - Request

/// One newline-delimited JSON object per TCP connection, as driven by
/// `scripts/minecraft-calibrate.sh`. Keeping the wire format to a single flat
/// struct rather than an enum with associated values preserves forward
/// compatibility: unknown fields are ignored and new commands can be added
/// without breaking older clients that only decode `command`.
struct MinecraftCalibrationRequest: Codable, Equatable {
    /// Canonical snake_case command name. The shell script translates kebab-case
    /// (`swipe-up`, `run-until`, etc.) to these values before sending.
    var command: String
    /// Target step identifier (`config:12`, `crafting:4`) or human-readable name
    /// for `run_until` / `select_step`.
    var target: String?
    var x: Double?
    var y: Double?
    var endX: Double?
    var endY: Double?
    var text: String?
    var seconds: Double?
    /// For `observe`: when true, include OCR text alongside the screenshot.
    var ocr: Bool?

    init(
        command: String,
        target: String? = nil,
        x: Double? = nil,
        y: Double? = nil,
        endX: Double? = nil,
        endY: Double? = nil,
        text: String? = nil,
        seconds: Double? = nil,
        ocr: Bool? = nil
    ) {
        self.command = command
        self.target = target
        self.x = x
        self.y = y
        self.endX = endX
        self.endY = endY
        self.text = text
        self.seconds = seconds
        self.ocr = ocr
    }
}

// MARK: - Response

struct MinecraftCalibrationStepInfo: Codable, Equatable {
    var id: String
    var name: String
    var action: String

    init(id: String, name: String, action: String) {
        self.id = id
        self.name = name
        self.action = action
    }

    init(from phased: MinecraftPhasedStep) {
        self.id = phased.id
        self.name = phased.name
        self.action = phased.action.debugDescription
    }
}

struct MinecraftCalibrationResultInfo: Codable, Equatable {
    var stepId: String
    var stepName: String
    var succeeded: Bool
    var failureReason: String?

    init(from result: MinecraftStepResult) {
        self.stepId = result.step.id
        self.stepName = result.step.name
        self.succeeded = result.succeeded
        self.failureReason = result.failureReason
    }

    init(stepId: String, stepName: String, succeeded: Bool, failureReason: String? = nil) {
        self.stepId = stepId
        self.stepName = stepName
        self.succeeded = succeeded
        self.failureReason = failureReason
    }
}

/// Every response echoes the run's scenario, phase, cursor, and execution result
/// so the CLI can render progress without a second round-trip. An error response
/// sets `success` to false and populates `error`; the state fields remain
/// present so the caller still knows where the cursor is.
struct MinecraftCalibrationResponse: Codable, Equatable {
    var success: Bool
    var error: String?

    // Run state — always present on success, also present on error when known.
    var scenario: String?
    var phase: String?
    /// Identifier of the current step (`config:12`) or nil when all steps are done.
    var cursor: String?
    var completedCount: Int?
    var totalCount: Int?
    var currentStep: MinecraftCalibrationStepInfo?
    var nextStep: MinecraftCalibrationStepInfo?
    var lastResult: MinecraftCalibrationResultInfo?

    // Optional bulk data
    var steps: [MinecraftCalibrationStepInfo]?

    // Optional observation
    var screenshotBase64: String?
    var recognizedText: String?

    init(
        success: Bool,
        error: String? = nil,
        scenario: String? = nil,
        phase: String? = nil,
        cursor: String? = nil,
        completedCount: Int? = nil,
        totalCount: Int? = nil,
        currentStep: MinecraftCalibrationStepInfo? = nil,
        nextStep: MinecraftCalibrationStepInfo? = nil,
        lastResult: MinecraftCalibrationResultInfo? = nil,
        steps: [MinecraftCalibrationStepInfo]? = nil,
        screenshotBase64: String? = nil,
        recognizedText: String? = nil
    ) {
        self.success = success
        self.error = error
        self.scenario = scenario
        self.phase = phase
        self.cursor = cursor
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.currentStep = currentStep
        self.nextStep = nextStep
        self.lastResult = lastResult
        self.steps = steps
        self.screenshotBase64 = screenshotBase64
        self.recognizedText = recognizedText
    }
}

// MARK: - Action debug description

extension MinecraftStep.Action {
    var debugDescription: String {
        switch self {
        case .wait(let s): "wait(\(s))"
        case .tap(let x, let y): "tap(\(x), \(y))"
        case .tapIfText(let x, let y, let text): "tapIfText(\(x), \(y); \(text))"
        case .tapTextRow(let x, let text): "tapTextRow(\(x); \(text))"
        case .tapUntilText(let x, let y, let fallbackX, let fallbackY, let text):
            "tapUntilText(\(x), \(y); fallback \(fallbackX), \(fallbackY); \(text))"
        case .drag(let x, let y, let endX, let endY): "drag(\(x), \(y) -> \(endX), \(endY))"
        case .swipeUp: "swipeUp"
        case .keyboardText(let t): "keyboardText(\(t))"
        case .numericKeyboardText(let t): "numericKeyboardText(\(t))"
        case .typeText(let t): "typeText(\(t))"
        case .chatCommand(let t): "chatCommand(\(t))"
        case .assertText(let t): "assertText(\(t))"
        case .assertPixels(let e): "assertPixels(\(e))"
        }
    }
}
