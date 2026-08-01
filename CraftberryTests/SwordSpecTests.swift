import XCTest
#if canImport(CraftberryCore)
@testable import CraftberryCore
#else
@testable import Craftberry
#endif

final class SwordSpecTests: XCTestCase {
    func testIdentifierUsesNamespaceAndSanitizedName() throws {
        let identifier = BedrockIdentifier.make(displayName: "Blue! Sword", suffix: "a1b2c3")

        XCTAssertEqual(identifier.rawValue, "craftberry:blue_sword_a1b2c3")
    }

    func testIdentifierFallsBackWhenNameHasNoSupportedCharacters() throws {
        let identifier = BedrockIdentifier.make(displayName: "⚔️", suffix: "a1b2c3")

        XCTAssertEqual(identifier.rawValue, "craftberry:custom_sword_a1b2c3")
    }

    func testSpecificationRejectsOutOfRangeDamage() throws {
        XCTAssertThrowsError(
            try SwordSpec(
                displayName: "Too Strong",
                color: .blue,
                attackBonus: 31,
                durability: 500,
                craftingIngredient: .diamond
            )
        )
    }

    func testDecodedSpecificationRejectsOutOfRangeDurability() throws {
        let data = Data("""
        {"displayName":"Broken Sword","color":"blue","attackBonus":10,"durability":2,"craftingIngredient":"diamond"}
        """.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(SwordSpec.self, from: data))
    }
}
