import Foundation

public enum CompilationIssueSeverity: String, Codable, Equatable, Sendable {
    case warning
    case error
}

public struct CompilationIssue: Codable, Equatable, Sendable {
    public let severity: CompilationIssueSeverity
    public let code: String
    public let path: String
    public let message: String

    public init(severity: CompilationIssueSeverity, code: String, path: String, message: String) {
        self.severity = severity
        self.code = code
        self.path = path
        self.message = message
    }
}

public struct CompilationReport: Codable, Equatable, Sendable {
    public let profileID: String
    public let issues: [CompilationIssue]
    public let emittedFiles: [String]

    public init(profileID: String, issues: [CompilationIssue] = [], emittedFiles: [String] = []) {
        self.profileID = profileID
        self.issues = issues
        self.emittedFiles = emittedFiles
    }

    public var errors: [CompilationIssue] { issues.filter { $0.severity == .error } }
    public var warnings: [CompilationIssue] { issues.filter { $0.severity == .warning } }
    public var isSuccessful: Bool { errors.isEmpty }
}

public enum AddOnProjectValidator {
    public static func validate(_ project: AddOnProject, profile: BedrockContentProfile) -> CompilationReport {
        var issues: [CompilationIssue] = []
        if project.schemaVersion != 1 && project.schemaVersion != 2 && project.schemaVersion != AddOnProject.currentSchemaVersion {
            issues.append(
                CompilationIssue(
                    severity: .error,
                    code: "unsupported_project_schema_version",
                    path: "schemaVersion",
                    message: "Project schema version \(project.schemaVersion) requires an explicit migration."
                )
            )
        }
        if project.targetProfileID != profile.id {
            issues.append(
                CompilationIssue(
                    severity: .error,
                    code: "incompatible_profile",
                    path: "targetProfileID",
                    message: "Project targets \(project.targetProfileID), not \(profile.id); migrate it before compiling."
                )
            )
        }
        if !isValidIdentifierSegment(project.namespace) {
            issues.append(
                CompilationIssue(
                    severity: .error,
                    code: "invalid_namespace",
                    path: "namespace",
                    message: "Namespaces may contain only lowercase ASCII letters, numbers, underscores, hyphens, and periods."
                )
            )
        }
        appendDuplicateUUIDIssue(project.packUUIDs, to: &issues)
        appendDuplicateIssues(
            values: project.items.map(\.id),
            code: "duplicate_item_id",
            path: "content.items",
            noun: "item",
            to: &issues
        )
        appendDuplicateIssues(
            values: project.allRecipeIDs,
            code: "duplicate_recipe_id",
            path: "content.recipes",
            noun: "recipe",
            to: &issues
        )
        appendDuplicateIssues(
            values: project.visualResources.map(\.id),
            code: "duplicate_visual_resource_id",
            path: "content.visualResources",
            noun: "visual resource",
            to: &issues
        )
        let itemIDs = Set(project.items.map(\.id))
        let visualResourceIDs = Set(project.visualResources.map(\.id))
        let visualResourceKinds = project.visualResources.reduce(into: [ContentID: VisualResourceKind]()) { kinds, resource in
            kinds[resource.id] = resource.kind
        }
        validateContentIDs(project, issues: &issues)
        for item in project.items {
            let itemPath = "content.items.\(item.id.rawValue)"
            if item.displayName.contains("\n") || item.displayName.contains("\r") {
                issues.append(
                    CompilationIssue(
                        severity: .error,
                        code: "invalid_localization_value",
                        path: "\(itemPath).displayName",
                        message: "Item display names cannot contain line breaks."
                    )
                )
            }
            if !item.menuGroup.hasPrefix("minecraft:") {
                issues.append(
                    CompilationIssue(
                        severity: .error,
                        code: "invalid_menu_group",
                        path: "\(itemPath).menuGroup",
                        message: "Item menu groups must use a namespace-prefixed identifier."
                    )
                )
            }
            if !visualResourceIDs.contains(item.visualResourceID) {
                issues.append(
                    CompilationIssue(
                        severity: .error,
                        code: "missing_visual_resource",
                        path: "\(itemPath).visualResourceID",
                        message: "Item references missing visual resource \(item.visualResourceID.rawValue)."
                    )
                )
            }
            if let combat = item.traits.combat, !(1...30).contains(combat.attackBonus) {
                issues.append(
                    CompilationIssue(
                        severity: .error,
                        code: "invalid_attack_bonus",
                        path: "\(itemPath).traits.combat.attackBonus",
                        message: "Item attack bonuses must be between 1 and 30."
                    )
                )
            }
            if item.traits.combat != nil, !profile.supportedItemTraits.contains(.combat) {
                appendUnsupportedTrait(.combat, itemPath: itemPath, profile: profile, issues: &issues)
            }
            if let durability = item.traits.durability, durability.maximum < 1 {
                issues.append(
                    CompilationIssue(
                        severity: .error,
                        code: "invalid_durability",
                        path: "\(itemPath).traits.durability.maximum",
                        message: "Item durability must be at least 1."
                    )
                )
            }
            if item.traits.durability != nil, !profile.supportedItemTraits.contains(.durability) {
                appendUnsupportedTrait(.durability, itemPath: itemPath, profile: profile, issues: &issues)
            }
            if item.traits.handEquipped, !profile.supportedItemTraits.contains(.handEquipped) {
                appendUnsupportedTrait(.handEquipped, itemPath: itemPath, profile: profile, issues: &issues)
            }
            if let armor = item.traits.armor {
                if !(0...20).contains(armor.protection) {
                    issues.append(
                        CompilationIssue(
                            severity: .error,
                            code: "invalid_armor_protection",
                            path: "\(itemPath).traits.armor.protection",
                            message: "Armor protection must be between 0 and 20."
                        )
                    )
                }
                let layerKind = visualResourceKinds[armor.layerResourceID]
                if layerKind != .armorLayerOne && layerKind != .armorLayerTwo {
                    issues.append(
                        CompilationIssue(
                            severity: .error,
                            code: "missing_armor_layer_resource",
                            path: "\(itemPath).traits.armor.layerResourceID",
                            message: "Armor item references missing or invalid armor layer resource \(armor.layerResourceID.rawValue)."
                        )
                    )
                }
                if !profile.supportedItemTraits.contains(.armor) {
                    appendUnsupportedTrait(.armor, itemPath: itemPath, profile: profile, issues: &issues)
                }
            }
            if !(1...64).contains(item.traits.maximumStackSize) {
                issues.append(
                    CompilationIssue(
                        severity: .error,
                        code: "invalid_stack_size",
                        path: "\(itemPath).traits.maximumStackSize",
                        message: "Item stack sizes must be between 1 and 64."
                    )
                )
            }
        }
        for recipe in project.recipes {
            let recipePath = "content.recipes.\(recipe.id.rawValue)"
            if recipe.pattern.isEmpty || recipe.pattern.count > 3 {
                issues.append(
                    CompilationIssue(
                        severity: .error,
                        code: "recipe_pattern_height",
                        path: "\(recipePath).pattern",
                        message: "Shaped recipes require one through three rows."
                    )
                )
            }
            if recipe.pattern.contains(where: { $0.count > 3 }) {
                issues.append(
                    CompilationIssue(
                        severity: .error,
                        code: "recipe_pattern_width",
                        path: "\(recipePath).pattern",
                        message: "Shaped recipe rows may contain at most three columns."
                    )
                )
            }
            if !(1...64).contains(recipe.result.count) {
                issues.append(
                    CompilationIssue(
                        severity: .error,
                        code: "recipe_result_count",
                        path: "\(recipePath).result.count",
                        message: "Recipe result counts must be between 1 and 64."
                    )
                )
            }
            if recipe.unlock.isEmpty {
                issues.append(
                    CompilationIssue(
                        severity: .error,
                        code: "recipe_unlock_required",
                        path: "\(recipePath).unlock",
                        message: "Recipes in this profile require at least one unlock condition."
                    )
                )
            }
            let usedSymbols = Set(recipe.pattern.flatMap { $0.filter { !$0.isWhitespace }.map(String.init) })
            for symbol in usedSymbols.subtracting(recipe.ingredients.keys).sorted() {
                issues.append(
                    CompilationIssue(
                        severity: .error,
                        code: "undefined_recipe_symbol",
                        path: "\(recipePath).pattern",
                        message: "Recipe pattern uses key \(symbol), but no ingredient defines it."
                    )
                )
            }
            for symbol in Set(recipe.ingredients.keys).subtracting(usedSymbols).sorted() {
                issues.append(
                    CompilationIssue(
                        severity: .error,
                        code: "unused_recipe_symbol",
                        path: "\(recipePath).ingredients.\(symbol)",
                        message: "Recipe key \(symbol) is not used in its pattern."
                    )
                )
            }
            validate(
                recipe.result.item,
                path: "\(recipePath).result",
                itemIDs: itemIDs,
                profile: profile,
                issues: &issues
            )
            for (symbol, reference) in recipe.ingredients.sorted(by: { $0.key < $1.key }) {
                validate(
                    reference,
                    path: "content.recipes.\(recipe.id.rawValue).ingredients.\(symbol)",
                    itemIDs: itemIDs,
                    profile: profile,
                    issues: &issues
                )
            }
            for (index, reference) in recipe.unlock.enumerated() {
                validate(
                    reference,
                    path: "content.recipes.\(recipe.id.rawValue).unlock.\(index)",
                    itemIDs: itemIDs,
                    profile: profile,
                    issues: &issues
                )
            }
        }
        for recipe in project.shapelessRecipes {
            let recipePath = "content.recipes.\(recipe.id.rawValue)"
            if !(1...9).contains(recipe.ingredients.count) {
                issues.append(CompilationIssue(severity: .error, code: "shapeless_recipe_ingredient_count", path: "\(recipePath).ingredients", message: "Shapeless recipes require one through nine ingredients."))
            }
            validateRecipeResult(recipe.result, recipePath: recipePath, itemIDs: itemIDs, profile: profile, issues: &issues)
            validateUnlock(recipe.unlock, recipePath: recipePath, itemIDs: itemIDs, profile: profile, issues: &issues)
            for (index, reference) in recipe.ingredients.enumerated() {
                validate(reference, path: "\(recipePath).ingredients.\(index)", itemIDs: itemIDs, profile: profile, issues: &issues)
            }
        }
        if hasRecipeDependencyCycle(project.recipes, project.shapelessRecipes) {
            issues.append(
                CompilationIssue(
                    severity: .error,
                    code: "recipe_dependency_cycle",
                    path: "content.recipes",
                    message: "Generated item recipes contain a dependency cycle."
                )
            )
        }
        return CompilationReport(profileID: profile.id, issues: issues)
    }

    private static func hasRecipeDependencyCycle(_ recipes: [ShapedRecipeDefinition], _ shapelessRecipes: [ShapelessRecipeDefinition]) -> Bool {
        var dependencies: [ContentID: Set<ContentID>] = [:]
        for recipe in recipes {
            guard case .generated(let resultID) = recipe.result.item else { continue }
            let generatedIngredients = recipe.ingredients.values.reduce(into: Set<ContentID>()) { ids, reference in
                if case .generated(let id) = reference { ids.insert(id) }
            }
            dependencies[resultID, default: []].formUnion(generatedIngredients)
        }
        for recipe in shapelessRecipes {
            guard case .generated(let resultID) = recipe.result.item else { continue }
            let generatedIngredients = recipe.ingredients.reduce(into: Set<ContentID>()) { ids, reference in
                if case .generated(let id) = reference { ids.insert(id) }
            }
            dependencies[resultID, default: []].formUnion(generatedIngredients)
        }

        var visiting = Set<ContentID>()
        var visited = Set<ContentID>()

        func visit(_ id: ContentID) -> Bool {
            if visiting.contains(id) { return true }
            if visited.contains(id) { return false }
            visiting.insert(id)
            for dependency in dependencies[id, default: []] where visit(dependency) {
                return true
            }
            visiting.remove(id)
            visited.insert(id)
            return false
        }

        return dependencies.keys.sorted { $0.rawValue < $1.rawValue }.contains(where: visit)
    }

    private static func validateRecipeResult(_ result: RecipeResult, recipePath: String, itemIDs: Set<ContentID>, profile: BedrockContentProfile, issues: inout [CompilationIssue]) {
        if !(1...64).contains(result.count) {
            issues.append(CompilationIssue(severity: .error, code: "recipe_result_count", path: "\(recipePath).result.count", message: "Recipe result counts must be between 1 and 64."))
        }
        validate(result.item, path: "\(recipePath).result", itemIDs: itemIDs, profile: profile, issues: &issues)
    }

    private static func validateUnlock(_ unlock: [ContentReference], recipePath: String, itemIDs: Set<ContentID>, profile: BedrockContentProfile, issues: inout [CompilationIssue]) {
        if unlock.isEmpty { issues.append(CompilationIssue(severity: .error, code: "recipe_unlock_required", path: "\(recipePath).unlock", message: "Recipes in this profile require at least one unlock condition.")) }
        for (index, reference) in unlock.enumerated() { validate(reference, path: "\(recipePath).unlock.\(index)", itemIDs: itemIDs, profile: profile, issues: &issues) }
    }

    private static func validate(
        _ reference: ContentReference,
        path: String,
        itemIDs: Set<ContentID>,
        profile: BedrockContentProfile,
        issues: inout [CompilationIssue]
    ) {
        switch reference {
        case .generated(let id) where !itemIDs.contains(id):
            issues.append(
                CompilationIssue(
                    severity: .error,
                    code: "missing_generated_reference",
                    path: path,
                    message: "Reference points to missing generated item \(id.rawValue)."
                )
            )
        case .vanilla(let identifier) where !profile.vanillaItemIdentifiers.contains(identifier):
            issues.append(
                CompilationIssue(
                    severity: .error,
                    code: "unsupported_vanilla_reference",
                    path: path,
                    message: "Vanilla item \(identifier) is not in profile \(profile.id)."
                )
            )
        case .tag(let identifier) where !profile.vanillaItemTags.contains(identifier):
            issues.append(
                CompilationIssue(
                    severity: .error,
                    code: "unsupported_vanilla_tag",
                    path: path,
                    message: "Vanilla tag \(identifier) is not in profile \(profile.id)."
                )
            )
        default:
            break
        }
    }

    private static func appendDuplicateIssues(
        values: [ContentID],
        code: String,
        path: String,
        noun: String,
        to issues: inout [CompilationIssue]
    ) {
        var seen = Set<ContentID>()
        for value in values where !seen.insert(value).inserted {
            issues.append(
                CompilationIssue(
                    severity: .error,
                    code: code,
                    path: path,
                    message: "Duplicate \(noun) identifier: \(value.rawValue)."
                )
            )
        }
    }

    private static func appendDuplicateUUIDIssue(
        _ packUUIDs: PackUUIDs,
        to issues: inout [CompilationIssue]
    ) {
        let values = [
            packUUIDs.behaviorHeader,
            packUUIDs.behaviorModule,
            packUUIDs.resourceHeader,
            packUUIDs.resourceModule
        ]
        guard Set(values).count != values.count else { return }
        issues.append(
            CompilationIssue(
                severity: .error,
                code: "duplicate_pack_uuid",
                path: "packUUIDs",
                message: "Every pack header and module must have a distinct UUID."
            )
        )
    }

    private static func validateContentIDs(
        _ project: AddOnProject,
        issues: inout [CompilationIssue]
    ) {
        let values: [(path: String, id: ContentID)] =
            project.items.map { ("content.items.\($0.id.rawValue).id", $0.id) }
            + project.recipes.map { ("content.recipes.\($0.id.rawValue).id", $0.id) }
            + project.shapelessRecipes.map { ("content.recipes.\($0.id.rawValue).id", $0.id) }
            + project.visualResources.map { ("content.visualResources.\($0.id.rawValue).id", $0.id) }
        for value in values where !isValidIdentifierSegment(value.id.rawValue) {
            issues.append(
                CompilationIssue(
                    severity: .error,
                    code: "invalid_content_id",
                    path: value.path,
                    message: "Content identifiers may contain only lowercase ASCII letters, numbers, underscores, hyphens, and periods."
                )
            )
        }
    }

    private static func isValidIdentifierSegment(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 97...122, 48...57, 95:
                true
            case 45, 46:
                true
            default:
                false
            }
        }
    }

    private static func appendUnsupportedTrait(
        _ trait: ItemTraitKind,
        itemPath: String,
        profile: BedrockContentProfile,
        issues: inout [CompilationIssue]
    ) {
        issues.append(
            CompilationIssue(
                severity: .error,
                code: "unsupported_item_trait",
                path: "\(itemPath).traits.\(trait.rawValue)",
                message: "Profile \(profile.id) does not support the \(trait.rawValue) item trait."
            )
        )
    }
}
