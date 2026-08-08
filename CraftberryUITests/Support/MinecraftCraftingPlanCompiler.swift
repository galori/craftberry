import Foundation

struct MinecraftCraftingPlanCompiler {
    var layout = MinecraftCalibratedLayout()

    func compile(_ plan: MinecraftCraftingPlan) -> [MinecraftStep] {
        plan.recipes.enumerated().flatMap { index, recipe in
            compile(
                recipe,
                shouldClearSearchAtStart: index > 0,
                isLastRecipe: index == plan.recipes.indices.last,
                finalHotbarTap: plan.finalHotbarTap
            )
        }
    }

    private func compile(
        _ recipe: MinecraftCraftingPlan.Recipe,
        shouldClearSearchAtStart: Bool,
        isLastRecipe: Bool,
        finalHotbarTap: MinecraftCoordinate?
    ) -> [MinecraftStep] {
        var steps: [MinecraftStep] = []
        if shouldClearSearchAtStart, let firstIngredient = recipe.ingredients.first {
            steps.append(.tap("Clear \(firstIngredient.searchText) search", layout.creativeSearchClearButton))
        }
        for (ingredientIndex, ingredient) in recipe.ingredients.enumerated() {
            if ingredientIndex > 0 {
                steps.append(.tap("Clear \(ingredient.searchText) search", layout.creativeSearchClearButton))
            }
            steps.append(.tap("Search Creative inventory for \(ingredient.searchText)", layout.creativeSearchField))
            steps.append(MinecraftStep(name: "Type \(ingredient.searchText) search", action: .keyboardText(ingredient.searchText)))
            steps.append(MinecraftStep(name: "Wait for \(ingredient.searchText) search results", action: .wait(seconds: 4)))

            let source = layout.creativeResult(column: ingredient.resultColumn)
            for (destinationIndex, slot) in ingredient.destinations.enumerated() {
                steps.append(.tap("Pick \(ordinal(destinationIndex + 1)) \(ingredient.searchText) stack", source))
                steps.append(.tap("Place \(ingredient.searchText) in \(slot.displayName) recipe slot", layout.craftingSlot(slot)))
            }
        }

        steps.append(MinecraftStep(name: "Wait for \(recipe.outputName) output", action: .wait(seconds: 4)))
        if let verification = recipe.beforePickupVerification {
            steps.append(step(for: verification, name: "Confirm \(recipe.outputName) output is visible"))
        }
        steps.append(.tap("Take \(recipe.outputName) output", layout.craftingOutput))
        // Taking the output drops it straight into the hotbar, and Minecraft renders an item's name
        // only in the tooltip raised by tapping that hotbar slot — nothing on the crafting screen
        // spells the name out. So the name assertion has to come after the hotbar tap, not before
        steps.append(.tap("Select \(recipe.outputName) in the hotbar", recipe.outputDestination))
        // The tooltip appears after the hotbar tap and fades after ~1s. Give the UI a moment
        // to raise it before OCR polls — confirmed live that redstone armor/boots need the tap
        // to show the name, and without a brief pause the 0.5s poll can miss the transient text.
        steps.append(MinecraftStep(name: "Wait for \(recipe.outputName) tooltip to appear", action: .wait(seconds: 0.8)))
        if let verification = recipe.afterPickupVerification {
            steps.append(step(for: verification, name: "Confirm crafted \(recipe.outputName)"))
            // While the tooltip is up it swallows the next tap: confirmed live that closing the
            // crafting table immediately after reading the tooltip only dismissed the tooltip, left
            // the table open, and so left the previous recipe's leftover stacks sitting in the grid
            // to corrupt the next recipe. Let it fade before anything else is tapped.
            steps.append(MinecraftStep(name: "Wait for the \(recipe.outputName) tooltip to fade", action: .wait(seconds: 2)))
        }

        if recipe.shouldResetTableAfterPickup {
            steps += resetCraftingTableSteps()
        } else {
            steps.append(.tap("Close crafting interface", layout.closeCraftingTable))
            steps.append(MinecraftStep(name: "Wait for the creative HUD", action: .wait(seconds: 2)))
            if isLastRecipe, let finalHotbarTap {
                steps.append(.tap("Select crafted \(recipe.outputName) in the HUD hotbar", finalHotbarTap))
            }
        }

        return steps
    }

    private func step(for verification: MinecraftCraftingPlan.Verification, name: String) -> MinecraftStep {
        switch verification {
        case .text(let text):
            MinecraftStep(name: name, action: .assertText(text))
        case .pixels(let expectation):
            MinecraftStep(name: name, action: .assertPixels(expectation))
        }
    }

    private func resetCraftingTableSteps() -> [MinecraftStep] {
        [
            .tap("Close crafting table to return recipe inputs", layout.closeCraftingTable),
            MinecraftStep(name: "Wait for leftover recipe inputs to return to inventory", action: .wait(seconds: 2)),
            .tap("Reopen crafting table for the next recipe", layout.reopenCraftingTable),
            MinecraftStep(name: "Wait for crafting table to reopen", action: .wait(seconds: 4)),
            MinecraftStep(name: "Confirm crafting table reopened for the next recipe", action: .assertText("Crafting"))
        ]
    }

    private func ordinal(_ value: Int) -> String {
        switch value {
        case 1: "first"
        case 2: "second"
        case 3: "third"
        case 4: "fourth"
        default: "\(value)th"
        }
    }
}

private extension MinecraftStep {
    static func tap(_ name: String, _ coordinate: MinecraftCoordinate) -> MinecraftStep {
        MinecraftStep(name: name, action: .tap(x: coordinate.x, y: coordinate.y))
    }
}

private extension MinecraftCraftingSlot {
    var displayName: String {
        switch self {
        case .topLeft: "top-left"
        case .topCenter: "top-center"
        case .topRight: "top-right"
        case .middleLeft: "middle-left"
        case .middleCenter: "middle-center"
        case .middleRight: "middle-right"
        case .bottomLeft: "bottom-left"
        case .bottomCenter: "bottom-center"
        case .bottomRight: "bottom-right"
        }
    }
}
