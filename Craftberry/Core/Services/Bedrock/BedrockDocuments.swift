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
        let language: String?
        let entry: String?

        init(type: String, uuid: String, version: [Int], language: String? = nil, entry: String? = nil) {
            self.type = type
            self.uuid = uuid
            self.version = version
            self.language = language
            self.entry = entry
        }
    }

    struct Dependency: Encodable {
        var uuid: String?
        var version: [Int]
        var moduleName: String?

        init(uuid: String, version: [Int]) {
            self.uuid = uuid
            self.version = version
            self.moduleName = nil
        }

        init(moduleName: String, version: String) {
            uuid = nil
            self.moduleName = moduleName
            self.version = version.split(separator: ".").compactMap { Int($0) }
            _versionString = version
        }

        private var _versionString: String?

        enum CodingKeys: String, CodingKey { case uuid, version, moduleName = "module_name" }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if let uuid { try container.encode(uuid, forKey: .uuid) }
            if let moduleName { try container.encode(moduleName, forKey: .moduleName) }
            if let raw = _versionString {
                try container.encode(raw, forKey: .version)
            } else {
                try container.encode(version, forKey: .version)
            }
        }
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

struct FurnaceRecipeDocument: Encodable {
    let formatVersion: String
    let recipe: Recipe

    struct Recipe: Encodable {
        let description: ShapedRecipeDocument.Description
        let tags: [String]
        let input: InputValue
        let output: String
        let unlock: [ShapedRecipeDocument.Ingredient]

        enum CodingKeys: String, CodingKey { case description, tags, input, output, unlock }
    }

    enum InputValue: Encodable {
        case item(String)
        case tag(String)

        func encode(to encoder: Encoder) throws {
            switch self {
            case .item(let value):
                var container = encoder.singleValueContainer()
                try container.encode(value)
            case .tag(let value):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(value, forKey: .tag)
            }
        }

        enum CodingKeys: String, CodingKey { case tag }
    }

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case recipe = "minecraft:recipe_furnace"
    }
}

struct SmithingTrimRecipeDocument: Encodable {
    let formatVersion: String
    let recipe: Recipe

    struct Recipe: Encodable {
        let description: ShapedRecipeDocument.Description
        let tags: [String]
        let template: IngredientValue
        let base: IngredientValue
        let addition: IngredientValue

        enum CodingKeys: String, CodingKey { case description, tags, template, base, addition }
    }

    enum IngredientValue: Encodable {
        case item(String)
        case tag(String)

        func encode(to encoder: Encoder) throws {
            switch self {
            case .item(let value):
                var container = encoder.singleValueContainer()
                try container.encode(value)
            case .tag(let value):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(value, forKey: .tag)
            }
        }

        enum CodingKeys: String, CodingKey { case tag }
    }

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case recipe = "minecraft:recipe_smithing_trim"
    }
}

struct SmithingTransformRecipeDocument: Encodable {
    let formatVersion: String
    let recipe: Recipe

    struct Recipe: Encodable {
        let description: ShapedRecipeDocument.Description
        let tags: [String]
        let template: IngredientValue
        let base: IngredientValue
        let addition: IngredientValue
        let result: String

        enum CodingKeys: String, CodingKey { case description, tags, template, base, addition, result }
    }

    enum IngredientValue: Encodable {
        case item(String)
        case tag(String)

        func encode(to encoder: Encoder) throws {
            switch self {
            case .item(let value):
                var container = encoder.singleValueContainer()
                try container.encode(value)
            case .tag(let value):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(value, forKey: .tag)
            }
        }

        enum CodingKeys: String, CodingKey { case tag }
    }

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case recipe = "minecraft:recipe_smithing_transform"
    }
}

struct BrewingMixRecipeDocument: Encodable {
    let formatVersion: String
    let recipe: Recipe

    struct Recipe: Encodable {
        let description: ShapedRecipeDocument.Description
        let tags: [String]
        let input: String
        let reagent: String
        let output: String

        enum CodingKeys: String, CodingKey { case description, tags, input, reagent, output }
    }

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case recipe = "minecraft:recipe_brewing_mix"
    }
}

struct BrewingContainerRecipeDocument: Encodable {
    let formatVersion: String
    let recipe: Recipe

    struct Recipe: Encodable {
        let description: ShapedRecipeDocument.Description
        let tags: [String]
        let input: String
        let reagent: String
        let output: String

        enum CodingKeys: String, CodingKey { case description, tags, input, reagent, output }
    }

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case recipe = "minecraft:recipe_brewing_container"
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

struct BlockDocument: Encodable {
    let formatVersion: String
    let block: Block

    struct Block: Encodable {
        let description: Description
        let components: Components
        let permutations: [Permutation]?

        struct Permutation: Encodable {
            let condition: String
            let components: [String: Int]?

            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(condition, forKey: .condition)
                if let components { try c.encode(components, forKey: .components) }
            }

            enum CodingKeys: String, CodingKey { case condition, components }
        }
    }

    struct Description: Encodable {
        let identifier: String
        let menuCategory: MenuCategory?
        let states: [String: StateValue]?

        struct StateValue: Encodable {
            let values: RangeValue

            struct RangeValue: Encodable {
                let min: Int
                let max: Int
            }
        }
    }

    struct MenuCategory: Encodable {
        let category: String
        let group: String
    }

    struct Components: Encodable {
        let destroyTime: Double
        let mapColor: MapColor
        let lightDampening: Int
        let loot: String

        enum CodingKeys: String, CodingKey {
            case destroyTime = "minecraft:destroy_time"
            case mapColor = "minecraft:map_color"
            case lightDampening = "minecraft:light_dampening"
            case loot = "minecraft:loot"
        }
    }

    struct MapColor: Encodable {
        let color: String
    }

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case block = "minecraft:block"
    }
}

struct EntityDocument: Encodable {
    let formatVersion: String
    let entity: Entity
    struct Entity: Encodable {
        let description: Description
        let componentGroups: [String: ComponentGroup]
        let components: Components
        enum CodingKeys: String, CodingKey { case description; case componentGroups = "component_groups"; case components }
    }
    struct Description: Encodable {
        let identifier: String
        let isSpawnable: Bool
        let isSummonable: Bool
        let spawnCategory: String
        enum CodingKeys: String, CodingKey { case identifier; case isSpawnable = "is_spawnable"; case isSummonable = "is_summonable"; case spawnCategory = "spawn_category" }
    }
    struct ComponentGroup: Encodable {
        let isBaby: EmptyComponent?
        let scale: Scale?
        let ageable: Ageable?
        let experienceReward: ExperienceReward?
        let loot: Loot?
        let breedable: Breedable?
        enum CodingKeys: String, CodingKey { case isBaby = "minecraft:is_baby"; case scale = "minecraft:scale"; case ageable = "minecraft:ageable"; case experienceReward = "minecraft:experience_reward"; case loot = "minecraft:loot"; case breedable = "minecraft:breedable" }
    }
    struct EmptyComponent: Encodable {}
    struct Scale: Encodable { let value: Double }
    struct Ageable: Encodable { let duration: Int; let feedItems: [String]; let growUp: GrowUp; enum CodingKeys: String, CodingKey { case duration; case feedItems = "feed_items"; case growUp = "grow_up" } }
    struct GrowUp: Encodable { let event: String; let target: String }
    struct ExperienceReward: Encodable { let onDeath: String; enum CodingKeys: String, CodingKey { case onDeath = "on_death" } }
    struct Loot: Encodable { let table: String }
    struct Breedable: Encodable { let requireTame: Bool; let breedsWith: [String: EmptyComponent]; let breedItems: [String]; enum CodingKeys: String, CodingKey { case requireTame = "require_tame"; case breedsWith = "breeds_with"; case breedItems = "breed_items" } }
    struct Components: Encodable {
        let typeFamily: TypeFamily
        let breathable: Breathable
        let collisionBox: CollisionBox
        let nameable: EmptyComponent
        let health: Health
        let movement: Movement
        let physics: EmptyComponent
        let pushable: Pushable
        let scale: Scale
        enum CodingKeys: String, CodingKey { case typeFamily = "minecraft:type_family"; case breathable = "minecraft:breathable"; case collisionBox = "minecraft:collision_box"; case nameable = "minecraft:nameable"; case health = "minecraft:health"; case movement = "minecraft:movement"; case physics = "minecraft:physics"; case pushable = "minecraft:pushable"; case scale = "minecraft:scale" }
    }
    struct TypeFamily: Encodable { let family: [String] }
    struct Breathable: Encodable { let totalSupply: Int; let suffocateTime: Int; enum CodingKeys: String, CodingKey { case totalSupply = "total_supply"; case suffocateTime = "suffocate_time" } }
    struct CollisionBox: Encodable { let width: Double; let height: Double }
    struct Health: Encodable { let value: Int; let max: Int }
    struct Movement: Encodable { let value: Double }
    struct Pushable: Encodable { let isPushable: Bool; let isPushableByPiston: Bool; enum CodingKeys: String, CodingKey { case isPushable = "is_pushable"; case isPushableByPiston = "is_pushable_by_piston" } }
    enum CodingKeys: String, CodingKey { case formatVersion = "format_version"; case entity = "minecraft:entity" }
}
struct SpawnRuleDocument: Encodable {
    let formatVersion: String
    let spawnRules: SpawnRules
    struct SpawnRules: Encodable { let description: Description; let conditions: [Condition]; enum CodingKeys: String, CodingKey { case description; case conditions } }
    struct Description: Encodable { let identifier: String; let populationControl: String; enum CodingKeys: String, CodingKey { case identifier; case populationControl = "population_control" } }
    struct Condition: Encodable { let spawnsOnSurface: EmptyComponent; let spawnsOnBlockFilter: String; let brightnessFilter: BrightnessFilter; let weight: Weight; let herd: Herd; let biomeFilter: BiomeFilter; enum CodingKeys: String, CodingKey { case spawnsOnSurface = "minecraft:spawns_on_surface"; case spawnsOnBlockFilter = "minecraft:spawns_on_block_filter"; case brightnessFilter = "minecraft:brightness_filter"; case weight = "minecraft:weight"; case herd = "minecraft:herd"; case biomeFilter = "minecraft:biome_filter" } }
    struct EmptyComponent: Encodable {}
    struct BrightnessFilter: Encodable { let min: Int; let max: Int; let adjustForWeather: Bool; enum CodingKeys: String, CodingKey { case min; case max; case adjustForWeather = "adjust_for_weather" } }
    struct Weight: Encodable { let `default`: Int; enum CodingKeys: String, CodingKey { case `default` = "default" } }
    struct Herd: Encodable { let minSize: Int; let maxSize: Int; enum CodingKeys: String, CodingKey { case minSize = "min_size"; case maxSize = "max_size" } }
    struct BiomeFilter: Encodable { let test: String; let `operator`: String; let value: String }
    enum CodingKeys: String, CodingKey { case formatVersion = "format_version"; case spawnRules = "minecraft:spawn_rules" }
}
struct ClientEntityDocument: Encodable {
    let formatVersion: String
    let clientEntity: ClientEntity
    struct ClientEntity: Encodable { let description: Description }
    struct Description: Encodable { let identifier: String; let materials: [String: String]; let textures: [String: String]; let geometry: [String: String]; let renderControllers: [String]; let spawnEgg: SpawnEgg; enum CodingKeys: String, CodingKey { case identifier; case materials; case textures; case geometry; case renderControllers = "render_controllers"; case spawnEgg = "spawn_egg" } }
    struct SpawnEgg: Encodable { let texture: String }
    enum CodingKeys: String, CodingKey { case formatVersion = "format_version"; case clientEntity = "minecraft:client_entity" }
}
struct LootTableDocument: Encodable {
    let pools: [Pool]

    struct Pool: Encodable {
        let rolls: Int
        let entries: [Entry]
    }

    struct Entry: Encodable {
        let type: String
        let name: String
        let weight: Int
    }
}

struct TerrainTextureDocument: Encodable {
    let resourcePackName: String
    let textureName: String
    let padding: Int
    let numMipLevels: Int
    let textureData: [String: Texture]

    struct Texture: Encodable {
        let textures: String
    }

    enum CodingKeys: String, CodingKey {
        case resourcePackName = "resource_pack_name"
        case textureName = "texture_name"
        case padding
        case numMipLevels = "num_mip_levels"
        case textureData = "texture_data"
    }
}

struct BlocksDocument: Encodable {
    let entries: [String: Entry]

    struct Entry: Encodable {
        let textures: String
        let sound: String
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(entries)
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
