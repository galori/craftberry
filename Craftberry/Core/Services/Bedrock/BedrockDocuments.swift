import Foundation

struct ManifestDocument: Encodable {
    let formatVersion: Int
    let header: Header
    let modules: [Module]
    let dependencies: [Dependency]?

    struct Header: Encodable {
        let name: String
        let description: String
        let uuid: String
        let version: [Int]
        let minimumEngineVersion: [Int]

        enum CodingKeys: String, CodingKey {
            case name, description, uuid, version
            case minimumEngineVersion = "min_engine_version"
        }
    }

    struct Module: Encodable {
        let type: String
        let uuid: String
        let version: [Int]
    }

    struct Dependency: Encodable {
        let uuid: String
        let version: [Int]
    }

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case header, modules, dependencies
    }
}

struct ItemDocument: Encodable {
    let formatVersion: String
    let item: Item

    struct Item: Encodable {
        let description: Description
        let components: Components
    }

    struct Description: Encodable {
        let identifier: String
        let menuCategory: MenuCategory

        enum CodingKeys: String, CodingKey {
            case identifier
            case menuCategory = "menu_category"
        }
    }

    struct MenuCategory: Encodable {
        let category: String
        let group: String
    }

    struct Components: Encodable {
        let displayName: DisplayName
        let icon: Icon
        let maximumStackSize: Int
        let handEquipped: HandEquipped
        let damage: Damage?
        let durability: Durability?
        let wearable: Wearable?
        let food: Food?
        let fuel: Fuel?

        enum CodingKeys: String, CodingKey {
            case displayName = "minecraft:display_name"
            case icon = "minecraft:icon"
            case maximumStackSize = "minecraft:max_stack_size"
            case handEquipped = "minecraft:hand_equipped"
            case damage = "minecraft:damage"
            case durability = "minecraft:durability"
            case wearable = "minecraft:wearable"
            case food = "minecraft:food"
            case fuel = "minecraft:fuel"
        }
    }

    struct DisplayName: Encodable { let value: String }
    struct Icon: Encodable { let textures: [String: String] }
    struct HandEquipped: Encodable { let value: Bool }
    struct Damage: Encodable { let value: Int }

    struct Wearable: Encodable {
        let slot: String
        let protection: Int
    }

    struct Food: Encodable {
        let nutrition: Int
        let saturationModifier: String
        let canAlwaysEat: Bool?

        enum CodingKeys: String, CodingKey {
            case nutrition
            case saturationModifier = "saturation_modifier"
            case canAlwaysEat = "can_always_eat"
        }
    }

    struct Fuel: Encodable {
        let duration: Double
    }

    struct Durability: Encodable {
        let maximumDurability: Int
        let damageChance: DamageChance

        enum CodingKeys: String, CodingKey {
            case maximumDurability = "max_durability"
            case damageChance = "damage_chance"
        }
    }

    struct DamageChance: Encodable {
        let min: Int
        let max: Int
    }

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case item = "minecraft:item"
    }
}

struct ShapedRecipeDocument: Encodable {
    let formatVersion: String
    let recipe: Recipe

    struct Recipe: Encodable {
        let description: Description
        let tags: [String]
        let pattern: [String]
        let key: [String: Ingredient]
        let result: Result
        let unlock: [Ingredient]
    }

    struct Description: Encodable { let identifier: String }

    struct Ingredient: Encodable {
        let item: String?
        let tag: String?

        init(item: String) {
            self.item = item
            tag = nil
        }

        init(tag: String) {
            item = nil
            self.tag = tag
        }
    }

    struct Result: Encodable {
        let item: String
        let count: Int
    }

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case recipe = "minecraft:recipe_shaped"
    }
}

struct ShapelessRecipeDocument: Encodable {
    let formatVersion: String
    let recipe: Recipe

    struct Recipe: Encodable {
        let description: ShapedRecipeDocument.Description
        let tags: [String]
        let ingredients: [ShapedRecipeDocument.Ingredient]
        let result: ShapedRecipeDocument.Result
        let unlock: [ShapedRecipeDocument.Ingredient]
    }

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case recipe = "minecraft:recipe_shapeless"
    }
}

struct ItemTextureDocument: Encodable {
    let resourcePackName: String
    let textureData: [String: Texture]

    struct Texture: Encodable { let textures: String }

    enum CodingKeys: String, CodingKey {
        case resourcePackName = "resource_pack_name"
        case textureData = "texture_data"
    }
}

struct AttachableDocument: Encodable {
    let formatVersion: String
    let attachable: Attachable

    struct Attachable: Encodable {
        let description: Description
    }

    struct Description: Encodable {
        let identifier: String
        let materials: [String: String]
        let textures: [String: String]
        let geometry: [String: String]
        let scripts: Scripts
        let renderControllers: [String]

        enum CodingKeys: String, CodingKey {
            case identifier, materials, textures, geometry, scripts
            case renderControllers = "render_controllers"
        }
    }

    struct Scripts: Encodable {
        let parentSetup: String

        enum CodingKeys: String, CodingKey {
            case parentSetup = "parent_setup"
        }
    }

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case attachable = "minecraft:attachable"
    }
}

enum BedrockDocumentEncoder {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(value)
        data.append(10)
        return data
    }
}
