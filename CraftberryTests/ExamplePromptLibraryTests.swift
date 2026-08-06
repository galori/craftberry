#if canImport(UIKit)
import XCTest
@testable import Craftberry

final class ExamplePromptLibraryTests: XCTestCase {
    func testLibraryIsLargeEnoughToFeelFresh() {
        XCTAssertGreaterThanOrEqual(ExamplePromptLibrary.all.count, 30)
    }

    func testPromptTextIsUniqueAndPresentable() {
        var seen = Set<String>()
        for prompt in ExamplePromptLibrary.all {
            XCTAssertFalse(prompt.emoji.isEmpty, "\(prompt.text) is missing an emoji")
            XCTAssertFalse(prompt.text.isEmpty)
            XCTAssertLessThanOrEqual(prompt.text.count, 72, "\(prompt.text) is too long for one suggestion row")
            XCTAssertTrue(seen.insert(prompt.text).inserted, "Duplicate prompt: \(prompt.text)")
        }
    }

    /// Every suggested prompt must stay inside the active capability profile, so tapping one
    /// never lands the user in `.unsupported`.
    func testEveryPromptNamesASupportedVanillaMaterial() {
        for prompt in ExamplePromptLibrary.all {
            let text = prompt.text.lowercased()
            XCTAssertTrue(
                Self.materialKeywords.contains { text.contains($0) },
                "\(prompt.text) does not name a material the profile supports"
            )
        }
    }

    func testEverySupportedMaterialIsSuggestedAtLeastOnce() {
        let corpus = ExamplePromptLibrary.all.map { $0.text.lowercased() }
        for keyword in Self.materialKeywords {
            XCTAssertTrue(
                corpus.contains { $0.contains(keyword) },
                "No example prompt exercises \(keyword)"
            )
        }
    }

    /// Guards the AGENTS.md rule that new capabilities bring new example prompts with them.
    func testEachSupportedProjectKindIsWellRepresented() {
        let corpus = ExamplePromptLibrary.all.map { $0.text.lowercased() }
        let toolSets = corpus.filter { $0.contains("tool set") }
        let weaponSets = corpus.filter { $0.contains("weapon set") }
        let armorSets = corpus.filter { $0.contains("armor set") }
        let ingotSets = corpus.filter { $0.contains("ingot") }
        XCTAssertGreaterThanOrEqual(toolSets.count, 4)
        XCTAssertGreaterThanOrEqual(weaponSets.count, 4)
        XCTAssertGreaterThanOrEqual(armorSets.count, 4)
        XCTAssertGreaterThanOrEqual(ingotSets.count, 4)
    }

    func testSelectionReturnsTheRequestedNumberOfDistinctPrompts() {
        var generator = SeededGenerator(seed: 7)
        let selection = ExamplePromptLibrary.selection(count: 3, using: &generator)
        XCTAssertEqual(selection.count, 3)
        XCTAssertEqual(Set(selection.map(\.id)).count, 3)
    }

    func testSelectionNeverRepeatsThePromptsAlreadyOnScreen() {
        var generator = SeededGenerator(seed: 99)
        var current = ExamplePromptLibrary.selection(count: 3, using: &generator)
        for _ in 0..<40 {
            let next = ExamplePromptLibrary.selection(count: 3, excluding: current, using: &generator)
            XCTAssertTrue(Set(next.map(\.id)).isDisjoint(with: Set(current.map(\.id))))
            current = next
        }
    }

    func testSelectionIsDeterministicForAGivenGeneratorSeed() {
        var first = SeededGenerator(seed: 2026)
        var second = SeededGenerator(seed: 2026)
        XCTAssertEqual(
            ExamplePromptLibrary.selection(count: 3, using: &first).map(\.id),
            ExamplePromptLibrary.selection(count: 3, using: &second).map(\.id)
        )
    }

    func testSelectionFallsBackToTheFullLibraryWhenExclusionsLeaveTooFew() {
        var generator = SeededGenerator(seed: 1)
        let selection = ExamplePromptLibrary.selection(
            count: 3,
            excluding: ExamplePromptLibrary.all,
            using: &generator
        )
        XCTAssertEqual(selection.count, 3)
    }

    /// Derived from the profile catalog so a newly supported material immediately fails
    /// `testEverySupportedMaterialIsSuggestedAtLeastOnce` until prompts are added for it.
    private static let materialKeywords: [String] = GeneratedVanillaItemCatalog.materialSources
        .compactMap { identifier in
            identifier
                .replacingOccurrences(of: "minecraft:", with: "")
                .split(separator: "_")
                .first
                .map(String.init)
        }
        .sorted()
}

/// SplitMix64 — small, deterministic, and dependency-free.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
#endif
