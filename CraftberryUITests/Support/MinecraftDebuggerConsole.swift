import XCTest

/// A live handle into a paused Minecraft E2E run, meant to be driven from LLDB while attached to
/// the running test process — this harness's `binding.irb`.
///
/// The harness calls `beforeStep`/`afterStep` around every step; each hits an `@inline(never)`
/// checkpoint method. Setting an Xcode breakpoint on a checkpoint (e.g.
/// `MinecraftDebuggerConsole.beforeStepCheckpoint`) pauses the run there. From LLDB's `expr`
/// prompt, `MinecraftDebuggerConsole.current` reaches this instance to inspect Minecraft
/// (`recognizedText()`, `screenshot()`), poke at it (`tap`, `drag`, `swipeUp`, `keyboardText`,
/// `numericKeyboardText`, `chatCommand`, `wait`), or drive the plan itself (`runCurrentStep`,
/// `skipCurrentStep`) before `continue` resumes the harness.
final class MinecraftDebuggerConsole {
    /// The console for whichever run is currently paused at a checkpoint. Only one calibration
    /// run is ever live at a time, so a single static slot is enough for LLDB to find it without
    /// threading a handle through the call stack the debugger stopped in.
    static var current: MinecraftDebuggerConsole?

    private let app: XCUIApplication
    private let executor: MinecraftStepExecutor
    private let ocr: MinecraftOCRInspector
    private let resolve: (String) -> String
    private let onScreenshot: () -> String

    private(set) var currentStep: MinecraftPhasedStep?
    private(set) var isCurrentStepExecuted = false
    private(set) var lastResult: MinecraftStepResult?

    init(
        app: XCUIApplication,
        executor: MinecraftStepExecutor,
        ocr: MinecraftOCRInspector = MinecraftOCRInspector(),
        resolve: @escaping (String) -> String,
        onScreenshot: @escaping () -> String
    ) {
        self.app = app
        self.executor = executor
        self.ocr = ocr
        self.resolve = resolve
        self.onScreenshot = onScreenshot
    }

    // MARK: - Harness integration

    /// Marks `step` as the pending step and hits the before-step checkpoint. If a human/agent ran
    /// or skipped it from LLDB while paused there, returns that result so the harness does not run
    /// it again; otherwise returns nil and the harness runs it automatically.
    func beforeStep(_ step: MinecraftPhasedStep) -> MinecraftStepResult? {
        currentStep = step
        isCurrentStepExecuted = false
        lastResult = nil
        beforeStepCheckpoint()
        return isCurrentStepExecuted ? lastResult : nil
    }

    @inline(never)
    private func beforeStepCheckpoint() {}

    /// Records the step's outcome (automatic or manual) and hits the after-step checkpoint so a
    /// human/agent can inspect the result before the harness moves on to the next step.
    func afterStep(_ result: MinecraftStepResult) {
        lastResult = result
        afterStepCheckpoint()
    }

    @inline(never)
    private func afterStepCheckpoint() {}

    // MARK: - LLDB-callable commands

    @discardableResult
    func runCurrentStep() -> MinecraftStepResult? {
        guard let step = currentStep, !isCurrentStepExecuted else { return nil }
        let result = executor.execute(step, in: app, resolve: resolve)
        isCurrentStepExecuted = true
        lastResult = result
        return result
    }

    func skipCurrentStep() {
        guard let step = currentStep, !isCurrentStepExecuted else { return }
        isCurrentStepExecuted = true
        lastResult = .success(step)
    }

    @discardableResult
    func tap(_ x: Double, _ y: Double) -> MinecraftStepResult {
        runAdHoc(.tap(x: CGFloat(x), y: CGFloat(y)))
    }

    @discardableResult
    func drag(_ x: Double, _ y: Double, _ endX: Double, _ endY: Double) -> MinecraftStepResult {
        runAdHoc(.drag(x: CGFloat(x), y: CGFloat(y), endX: CGFloat(endX), endY: CGFloat(endY)))
    }

    @discardableResult
    func swipeUp() -> MinecraftStepResult {
        runAdHoc(.swipeUp)
    }

    @discardableResult
    func keyboardText(_ text: String) -> MinecraftStepResult {
        runAdHoc(.keyboardText(text))
    }

    @discardableResult
    func numericKeyboardText(_ text: String) -> MinecraftStepResult {
        runAdHoc(.numericKeyboardText(text))
    }

    @discardableResult
    func chatCommand(_ text: String) -> MinecraftStepResult {
        runAdHoc(.chatCommand(text))
    }

    func wait(_ seconds: Double) {
        Thread.sleep(forTimeInterval: seconds)
    }

    func recognizedText() -> String {
        ocr.recognizedText()
    }

    @discardableResult
    func screenshot() -> String {
        onScreenshot()
    }

    /// Ad hoc console actions (nudging a coordinate, probing a stuck screen) are deliberately not
    /// tied to `currentStep`/`isCurrentStepExecuted` — they're exploratory, not the plan, and must
    /// never cause the harness to think the current step already ran.
    private func runAdHoc(_ action: MinecraftStep.Action) -> MinecraftStepResult {
        let step = MinecraftPhasedStep(id: "debugger:adhoc", name: "Debugger console action", action: action)
        return executor.execute(step, in: app, resolve: resolve)
    }
}
