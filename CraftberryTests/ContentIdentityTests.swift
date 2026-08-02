import XCTest
#if canImport(CraftberryCore)
@testable import CraftberryCore
#else
@testable import Craftberry
#endif

final class ContentIdentityTests: XCTestCase {
    func testIdentifierUsesNamespaceAndSanitizedName() {
        let identifier = BedrockIdentifier.make(displayName: "Blue! Sword", suffix: "a1b2c3")

        XCTAssertEqual(identifier.rawValue, "craftberry:blue_sword_a1b2c3")
    }

    func testIdentifierFallsBackToAGenericItemName() {
        let identifier = BedrockIdentifier.make(displayName: "⚔️", suffix: "a1b2c3")

        XCTAssertEqual(identifier.rawValue, "craftberry:custom_item_a1b2c3")
    }
}
