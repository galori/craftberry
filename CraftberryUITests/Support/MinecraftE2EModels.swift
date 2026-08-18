import CoreGraphics
import Foundation

struct MinecraftE2EConfiguration: Decodable {
    let enabled: Bool
    let steps: [MinecraftStep]
}

struct MinecraftStep: Equatable {
    enum Action: Equatable {
        case wait(seconds: TimeInterval)
        case tap(x: CGFloat, y: CGFloat)
        case tapTextRow(x: CGFloat, text: String)
        case tapUntilText(x: CGFloat, y: CGFloat, fallbackX: CGFloat, fallbackY: CGFloat, text: String)
        case drag(x: CGFloat, y: CGFloat, endX: CGFloat, endY: CGFloat)
        case swipeUp
        case keyboardText(String)
        case numericKeyboardText(String)
        case typeText(String)
        case chatCommand(String)
        case assertText(String)
        case assertPixels(MinecraftPixelExpectation)
    }

    let name: String
    let action: Action
}

extension MinecraftStep: Decodable {
    private enum CodingKeys: String, CodingKey {
        case name, action, x, y, fallbackX, fallbackY, endX, endY, seconds, text, pixelExpectation
    }

    private enum LegacyAction: String, Decodable {
        case wait, tap, tapTextRow, tapUntilText, drag, swipeUp, type, keyText
        case numericKeyText, chatCommand, redstonePickaxeOutput, ocr
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        switch try container.decode(LegacyAction.self, forKey: .action) {
        case .wait:
            action = .wait(seconds: try container.decodeIfPresent(TimeInterval.self, forKey: .seconds) ?? 1)
        case .tap:
            action = .tap(
                x: try container.require(CGFloat.self, forKey: .x, stepName: name),
                y: try container.require(CGFloat.self, forKey: .y, stepName: name)
            )
        case .tapTextRow:
            action = .tapTextRow(
                x: try container.require(CGFloat.self, forKey: .x, stepName: name),
                text: try container.require(String.self, forKey: .text, stepName: name)
            )
        case .tapUntilText:
            action = .tapUntilText(
                x: try container.require(CGFloat.self, forKey: .x, stepName: name),
                y: try container.require(CGFloat.self, forKey: .y, stepName: name),
                fallbackX: try container.require(CGFloat.self, forKey: .fallbackX, stepName: name),
                fallbackY: try container.require(CGFloat.self, forKey: .fallbackY, stepName: name),
                text: try container.require(String.self, forKey: .text, stepName: name)
            )
        case .drag:
            action = .drag(
                x: try container.require(CGFloat.self, forKey: .x, stepName: name),
                y: try container.require(CGFloat.self, forKey: .y, stepName: name),
                endX: try container.require(CGFloat.self, forKey: .endX, stepName: name),
                endY: try container.require(CGFloat.self, forKey: .endY, stepName: name)
            )
        case .swipeUp:
            action = .swipeUp
        case .type:
            action = .typeText(try container.require(String.self, forKey: .text, stepName: name))
        case .keyText:
            action = .keyboardText(try container.require(String.self, forKey: .text, stepName: name))
        case .numericKeyText:
            action = .numericKeyboardText(try container.require(String.self, forKey: .text, stepName: name))
        case .chatCommand:
            action = .chatCommand(try container.require(String.self, forKey: .text, stepName: name))
        case .ocr:
            action = .assertText(try container.require(String.self, forKey: .text, stepName: name))
        case .redstonePickaxeOutput:
            action = .assertPixels(.redstonePickaxeOutput)
        }
    }
}

extension KeyedDecodingContainer {
    func require<T: Decodable>(_ type: T.Type, forKey key: Key, stepName: String) throws -> T {
        guard let value = try decodeIfPresent(type, forKey: key) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Step '\(stepName)' is missing required payload '\(key.stringValue)'."
            )
        }
        return value
    }
}

struct MinecraftE2EScenario {
    let launchArgument: String
    let prompt: String
    let projectName: String
    let expectedCraftedItemName: String
    let behaviorPackName: String
    let resourcePackName: String
    let craftingPlan: MinecraftCraftingPlan
}

enum MinecraftWorldGameMode: String {
    case creative
    case survival
}

struct MinecraftCraftingPlan {
    var recipes: [Recipe]
    var finalHotbarTap: MinecraftCoordinate?

    struct Recipe {
        let outputName: String
        let ingredients: [IngredientPlacement]
        let beforePickupVerification: Verification?
        let afterPickupVerification: Verification?
        let outputDestination: MinecraftCoordinate
        let shouldResetTableAfterPickup: Bool
    }

    struct IngredientPlacement {
        let searchText: String
        let resultColumn: Int
        let destinations: [MinecraftCraftingSlot]
    }

    enum Verification: Equatable {
        case text(String)
        case pixels(MinecraftPixelExpectation)
    }
}

struct MinecraftCoordinate: Equatable {
    let x: CGFloat
    let y: CGFloat
}

enum MinecraftCraftingSlot: CaseIterable {
    case topLeft, topCenter, topRight
    case middleLeft, middleCenter, middleRight
    case bottomLeft, bottomCenter, bottomRight
}

enum MinecraftPixelExpectation: Equatable {
    case redstonePickaxeOutput
    case redCluster(xRange: ClosedRange<CGFloat>, yRange: ClosedRange<CGFloat>, minimumCount: Int)
}
