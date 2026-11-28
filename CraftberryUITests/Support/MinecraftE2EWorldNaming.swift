import Foundation

enum MinecraftE2EWorldNaming {
    static func name(for scenario: MinecraftE2EScenario, gameMode: MinecraftWorldGameMode) -> String {
        "\(scenario.projectName) (\(gameMode.rawValue.capitalized))"
    }

    static func rowTap(for scenario: MinecraftE2EScenario, gameMode: MinecraftWorldGameMode) -> MinecraftStep {
        MinecraftStep(
            name: "Open imported \(name(for: scenario, gameMode: gameMode)) world by matching its title and game mode",
            action: .tapTextRowWithContext(
                x: 0.16,
                title: scenario.projectName,
                context: gameMode.rawValue.capitalized
            )
        )
    }
}
