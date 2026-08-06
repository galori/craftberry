import Foundation

public struct RecipeBook: Equatable, Sendable {
    public let rows: [RecipeBookRow]

    public init(project: AddOnProject) {
        let itemsByID = Dictionary(uniqueKeysWithValues: project.items.map { ($0.id, $0) })
        let visualsByID = Dictionary(uniqueKeysWithValues: project.visualResources.map { ($0.id, $0) })
        let shapedByResult = Dictionary(uniqueKeysWithValues: project.recipes.compactMap { recipe -> (ContentID, RecipeBookRecipe)? in
            guard case .generated(let id) = recipe.result.item else { return nil }
            return (id, .shaped(recipe))
        })
        let shapelessByResult = Dictionary(uniqueKeysWithValues: project.shapelessRecipes.compactMap { recipe -> (ContentID, RecipeBookRecipe)? in
            guard case .generated(let id) = recipe.result.item else { return nil }
            return (id, .shapeless(recipe))
        })
        rows = project.items.compactMap { item in
            let recipe = shapedByResult[item.id] ?? shapelessByResult[item.id]
            return RecipeBookRow(
                item: item,
                visualResource: visualsByID[item.visualResourceID],
                recipe: recipe,
                summary: Self.summary(for: item, recipe: recipe, itemsByID: itemsByID)
            )
        }
    }

    private static func summary(for item: ItemDefinition, recipe: RecipeBookRecipe?, itemsByID: [ContentID: ItemDefinition]) -> String {
        guard let recipe else { return "No crafting recipe" }
        switch recipe {
        case .shaped(let shaped):
            let references = shaped.pattern.flatMap { line in
                line.compactMap { shaped.ingredients[String($0)] }
            }
            let counts = ingredientCounts(references)
            return ingredientSentence(counts: counts, itemsByID: itemsByID) + " -> \(item.displayName)"
        case .shapeless(let shapeless):
            let counts = ingredientCounts(shapeless.ingredients)
            return ingredientSentence(counts: counts, itemsByID: itemsByID) + " -> \(item.displayName)"
        }
    }

    private static func ingredientCounts(_ references: [ContentReference]) -> [(ContentReference, Int)] {
        var ordered: [(ContentReference, Int)] = []
        for reference in references {
            if let index = ordered.firstIndex(where: { $0.0 == reference }) {
                ordered[index].1 += 1
            } else {
                ordered.append((reference, 1))
            }
        }
        return ordered
    }

    private static func ingredientSentence(counts: [(ContentReference, Int)], itemsByID: [ContentID: ItemDefinition]) -> String {
        counts.map { reference, count in
            let name = IngredientLabel(reference: reference, itemsByID: itemsByID).displayName
            return count == 1 ? name : "\(count) \(name)"
        }.joined(separator: " + ")
    }
}

public struct RecipeBookRow: Equatable, Sendable, Identifiable {
    public var id: ContentID { item.id }
    public let item: ItemDefinition
    public let visualResource: VisualResource?
    public let recipe: RecipeBookRecipe?
    public let summary: String

    public var categoryLabel: String {
        switch item.menuCategory {
        case .equipment: "Equipment"
        case .items: "Item"
        }
    }
}

public enum RecipeBookRecipe: Equatable, Sendable {
    case shaped(ShapedRecipeDefinition)
    case shapeless(ShapelessRecipeDefinition)

    public var result: RecipeResult {
        switch self {
        case .shaped(let recipe): recipe.result
        case .shapeless(let recipe): recipe.result
        }
    }

    public var ingredientReferences: [ContentReference] {
        switch self {
        case .shaped(let recipe): Array(recipe.ingredients.values)
        case .shapeless(let recipe): recipe.ingredients
        }
    }

    public func gridReferences() -> [ContentReference?] {
        switch self {
        case .shaped(let recipe):
            return (0..<3).flatMap { row in
                (0..<3).map { column -> ContentReference? in
                    guard row < recipe.pattern.count else { return nil }
                    let line = Array(recipe.pattern[row])
                    guard column < line.count else { return nil }
                    return recipe.ingredients[String(line[column])]
                }
            }
        case .shapeless(let recipe):
            return (0..<9).map { index in
                index < recipe.ingredients.count ? recipe.ingredients[index] : nil
            }
        }
    }
}

public struct IngredientLabel: Equatable, Sendable {
    public let identifier: String
    public let displayName: String

    public init(reference: ContentReference, itemsByID: [ContentID: ItemDefinition] = [:]) {
        switch reference {
        case .vanilla(let identifier), .tag(let identifier):
            self.identifier = identifier
            let path = identifier.split(separator: ":", maxSplits: 1).last.map(String.init) ?? identifier
            self.displayName = path.replacingOccurrences(of: "_", with: " ").capitalized
        case .generated(let id):
            self.identifier = id.rawValue
            self.displayName = itemsByID[id]?.displayName ?? id.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    public var path: String {
        identifier.split(separator: ":", maxSplits: 1).last.map(String.init) ?? identifier
    }
}
