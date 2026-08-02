#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit
#if canImport(CraftberryCore)
import CraftberryCore
#endif

struct CreationView: View {
    @ObservedObject var viewModel: CreationViewModel
    @State private var shareItem: ShareItem?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.craftberryBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    appHeader
                    content
                    if isEditing {
                        composer
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .sheet(item: $shareItem) { item in
            ActivitySheet(url: item.url)
        }
    }

    private var appHeader: some View {
        HStack {
            Circle()
                .fill(Color.craftberrySurface)
                .frame(width: 34, height: 34)
                .overlay(Image(systemName: "cube.transparent").foregroundStyle(Color.craftberryMuted))
                .accessibilityHidden(true)

            Spacer()

            HStack(spacing: 8) {
                CraftberryMark(size: 24)
                Text("Craftberry")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            Spacer()

            Circle()
                .fill(Color.craftberrySurface)
                .frame(width: 34, height: 34)
                .overlay(Image(systemName: "person.fill").font(.caption).foregroundStyle(Color.craftberryMuted))
                .accessibilityLabel("Profile")
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .editing:
            welcome
        case .generating:
            progressState(
                title: "Crafting your add-on…",
                detail: "Turning your idea into a validated Bedrock project.",
                steps: ["Reading your idea", "Building the content graph", "Validating references"]
            )
        case .building:
            progressState(
                title: "Building your add-on…",
                detail: "Rendering assets and packaging your .mcaddon.",
                steps: ["Rendering project assets", "Writing Bedrock files", "Packaging the build"]
            )
        case .unsupported(let message), .failed(let message):
            messageState(message)
        case .ready(let project):
            resultCard(project, result: nil)
        case .built(let project, let result):
            resultCard(project, result: result)
        }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            CraftberryMark(size: 64)
                .shadow(color: Color.craftberryOrange.opacity(0.42), radius: 22, y: 10)
            Text("What should we\ncraft tonight?")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.top, 22)
            Text("Describe a custom Bedrock add-on in your own words")
                .font(.subheadline)
                .foregroundStyle(Color.craftberryMuted)
                .padding(.top, 8)

            VStack(spacing: 10) {
                PromptSuggestion("🗡️  A blue sword, 20 damage, crafted from diamonds") {
                    viewModel.prompt = "A blue sword, 20 damage, crafted from diamonds"
                }
                PromptSuggestion("✨  A purple sword named Starfall, crafted from amethyst") {
                    viewModel.prompt = "A purple sword named Starfall, crafted from amethyst"
                }
                PromptSuggestion("🔥  A red sword with 12 damage, crafted from blaze rods") {
                    viewModel.prompt = "A red sword with 12 damage, crafted from blaze rods"
                }
            }
            .padding(.top, 28)
            .padding(.horizontal, 22)
            Spacer()
        }
    }

    private var isEditing: Bool {
        if case .editing = viewModel.state { return true }
        return false
    }

    private func progressState(title: String, detail: String, steps: [String]) -> some View {
        VStack(spacing: 0) {
            Spacer()
            CraftingProgressIndicator()
            Text(title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.top, 38)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Color.craftberryMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 9)

            AnimatedProgressSteps(steps: steps)
            .padding(.top, 38)
            .padding(.horizontal, 44)
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private func messageState(_ message: String) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.craftberryOrange)
            Text("Let’s try another idea")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.craftberryMuted)
                .padding(.horizontal, 28)
            Button("Try again") { viewModel.reset() }
                .buttonStyle(CraftberrySecondaryButtonStyle())
                .padding(.horizontal, 36)
            Spacer()
        }
    }

    @ViewBuilder
    private func resultCard(_ project: AddOnProject, result: BedrockCompilationResult?) -> some View {
        if let summary = ProjectSummary(project: project) {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Button { viewModel.reset() } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                            .frame(width: 34, height: 34)
                            .background(Color.craftberrySurface, in: Circle())
                    }
                    .accessibilityLabel("Start over")
                    Spacer()
                    Text(result == nil ? "READY TO BUILD" : "BUILD COMPLETE")
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(Color.craftberryMuted)
                    Spacer()
                    Image(systemName: result == nil ? "hammer.fill" : "checkmark")
                        .frame(width: 34, height: 34)
                        .background(Color.craftberrySurface, in: Circle())
                        .foregroundStyle(Color.craftberryGold)
                }

                hero(summary.visualResource)

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.displayName)
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        Text(result == nil ? summary.collectionDescription : result!.artifact.fileName)
                            .font(.subheadline)
                            .foregroundStyle(Color.craftberryMuted)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("NEW")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.craftberryGold)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.craftberrySurface, in: Capsule())
                }

                HStack(spacing: 10) {
                    StatTile(value: "+\(summary.attackBonus)", label: "Damage", color: .craftberryOrange)
                    StatTile(value: summary.ingredient.displayName, label: "Recipe", color: .craftberryBlue)
                    StatTile(value: "\(summary.durability)", label: "Durability", color: .craftberryGold)
                }

                CraftingRecipePreview(ingredient: summary.ingredient)

                if let result {
                    Button {
                        shareItem = ShareItem(url: result.artifact.url)
                    } label: {
                        Label("Export .mcaddon", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(CraftberryPrimaryButtonStyle())

                    Text("Save or share this build artifact, then transfer it to a physical iPhone for Minecraft validation.")
                        .font(.footnote)
                        .foregroundStyle(Color.craftberryMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                } else {
                    Button("Build .mcaddon") { viewModel.buildArtifact(project) }
                        .buttonStyle(CraftberryPrimaryButtonStyle())
                }
            }
            .padding(24)
        }
        } else {
            messageState("The generated project has no supported previewable item.")
        }
    }

    private func hero(_ visualResource: VisualResource) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(colors: [Color.craftberryBlue.opacity(0.7), Color.craftberryBackground], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(uiImage: UIImage(data: PixelArtTextureRenderer.render(visualResource, pixelScale: 6)) ?? UIImage())
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 138, height: 138)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
    }

    private var composer: some View {
        VStack(spacing: 12) {
            HStack(alignment: .bottom, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    if viewModel.prompt.isEmpty {
                        Text("Describe your add-on…")
                            .foregroundStyle(Color.craftberryMuted)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $viewModel.prompt)
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(.white)
                        .frame(minHeight: 48, maxHeight: 92)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 3)
                        .accessibilityLabel("Add-on description")
                }
                Button {
                    Task { await viewModel.generate() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline.weight(.bold))
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(CraftberryRoundButtonStyle())
                .disabled(viewModel.isBusy || viewModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Generate add-on")
            }
            .padding(7)
            .background(Color.craftberrySurface, in: RoundedRectangle(cornerRadius: 25))

            if case .editing = viewModel.state {
                Text("Craftberry creates a Bedrock .mcaddon build artifact")
                    .font(.caption2)
                    .foregroundStyle(Color.craftberryMuted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(Color.craftberryBackground.opacity(0.96))
    }
}

private struct PromptSuggestion: View {
    let prompt: String
    let action: () -> Void
    init(_ prompt: String, action: @escaping () -> Void) {
        self.prompt = prompt
        self.action = action
    }

    var body: some View {
        Button(prompt, action: action)
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.craftberryText)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background(Color.craftberrySurface, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct CraftberryMark: View {
    let size: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3)
            .fill(LinearGradient(colors: [.craftberryGold, .craftberryOrange], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.13)
                    .fill(.white)
                    .frame(width: size * 0.32, height: size * 0.32)
                    .rotationEffect(.degrees(45))
            )
            .accessibilityHidden(true)
    }
}

private struct StatTile: View {
    let value: String
    let label: String
    let color: Color
    var body: some View {
        VStack(spacing: 5) {
            Text(value).font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.65)
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(Color.craftberryMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(Color.craftberrySurface, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct ProjectSummary {
    let visualResource: VisualResource
    let attackBonus: Int
    let durability: Int
    let ingredient: IngredientSummary
    let collectionDescription: String

    init?(project: AddOnProject) {
        guard let item = project.items.first,
              let visualResource = project.visualResources.first(where: { $0.id == item.visualResourceID }),
              let attackBonus = item.traits.combat?.attackBonus,
              let durability = item.traits.durability?.maximum,
              let ingredientReference = project.recipes.first?.ingredients["M"] else {
            return nil
        }
        self.visualResource = visualResource
        self.attackBonus = attackBonus
        self.durability = durability
        ingredient = IngredientSummary(reference: ingredientReference)
        let itemLabel = project.items.count == 1 ? "item" : "items"
        let recipeLabel = project.recipes.count == 1 ? "recipe" : "recipes"
        collectionDescription = "\(project.items.count) \(itemLabel) · \(project.recipes.count) \(recipeLabel)"
    }
}

private struct IngredientSummary {
    let identifier: String
    let displayName: String

    init(reference: ContentReference) {
        switch reference {
        case .vanilla(let identifier), .tag(let identifier):
            self.identifier = identifier
        case .generated(let id):
            identifier = id.rawValue
        }
        let path = identifier.split(separator: ":", maxSplits: 1).last.map(String.init) ?? identifier
        displayName = path.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var path: String {
        identifier.split(separator: ":", maxSplits: 1).last.map(String.init) ?? identifier
    }
}

private struct CraftingRecipePreview: View {
    let ingredient: IngredientSummary

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Crafting recipe")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("2 \(ingredient.displayName) + 1 Stick")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.craftberryMuted)
            }

            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { column in
                    VStack(spacing: 7) {
                        ForEach(0..<3, id: \.self) { row in
                            ingredientCell(row: row, column: column)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(Color.craftberrySurface, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Crafting recipe: two \(ingredient.displayName) and one stick in a vertical line")
    }

    @ViewBuilder
    private func ingredientCell(row: Int, column: Int) -> some View {
        let isMaterial = column == 1 && (row == 0 || row == 1)
        let isStick = column == 1 && row == 2

        RoundedRectangle(cornerRadius: 7)
            .fill(Color.craftberryRecipeSlot)
            .frame(width: 44, height: 44)
            .overlay {
                if isMaterial {
                    IngredientGlyph(ingredient: ingredient)
                } else if isStick {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.craftberryStick)
                        .frame(width: 6, height: 26)
                        .rotationEffect(.degrees(38))
                }
            }
    }
}

private struct IngredientGlyph: View {
    let ingredient: IngredientSummary

    var body: some View {
        switch ingredient.path {
        case "blaze_rod":
            Capsule()
                .fill(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
                .frame(width: 11, height: 29)
                .rotationEffect(.degrees(38))
        case "redstone":
            Image(systemName: "sparkles")
                .font(.title3.weight(.bold))
                .foregroundStyle(.red)
        case "quartz":
            Image(systemName: "triangle.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .rotationEffect(.degrees(180))
        case "amethyst_shard":
            Image(systemName: "triangle.fill")
                .font(.title3)
                .foregroundStyle(.purple)
                .rotationEffect(.degrees(180))
        case "iron_ingot", "gold_ingot", "netherite_ingot":
            RoundedRectangle(cornerRadius: 3)
                .fill(ingredient.color)
                .frame(width: 25, height: 13)
                .rotationEffect(.degrees(-8))
        case "lapis_lazuli":
            Circle()
                .fill(.blue)
                .frame(width: 20, height: 20)
        case "emerald":
            RoundedRectangle(cornerRadius: 4)
                .fill(.green)
                .frame(width: 20, height: 20)
                .rotationEffect(.degrees(45))
        case "diamond":
            Image(systemName: "diamond.fill")
                .font(.title3)
                .foregroundStyle(Color.craftberryBlue)
        default:
            Image(systemName: "cube.fill")
                .font(.title3)
                .foregroundStyle(Color.craftberryMuted)
        }
    }
}

private struct CraftingProgressIndicator: View {
    @State private var isSpinning = false

    var body: some View {
        ZStack {
            Circle().stroke(Color.craftberrySurface, lineWidth: 3).frame(width: 148, height: 148)
            Circle()
                .trim(from: 0.05, to: 0.67)
                .stroke(Color.craftberryOrange, style: .init(lineWidth: 3, lineCap: .round))
                .frame(width: 148, height: 148)
                .rotationEffect(.degrees(isSpinning ? 360 : 0))
            CraftberryMark(size: 82)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                isSpinning = true
            }
        }
        .accessibilityLabel("Generation in progress")
    }
}

private struct AnimatedProgressSteps: View {
    let steps: [String]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.05)) { timeline in
            let activeIndex = Int(timeline.date.timeIntervalSinceReferenceDate / 1.05) % steps.count

            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 12) {
                        StepMarker(state: markerState(index: index, activeIndex: activeIndex))
                        Text(step)
                            .font(.subheadline.weight(index == activeIndex ? .bold : .regular))
                            .foregroundStyle(index == activeIndex ? .white : Color.craftberryMuted)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: activeIndex)
        }
    }

    private func markerState(index: Int, activeIndex: Int) -> StepMarker.State {
        if index < activeIndex { return .complete }
        if index == activeIndex { return .active }
        return .upcoming
    }
}

private struct StepMarker: View {
    enum State { case complete, active, upcoming }
    let state: State

    var body: some View {
        Group {
            switch state {
            case .complete:
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.craftberryBackground)
                    .frame(width: 22, height: 22)
                    .background(Color.craftberryGold, in: Circle())
            case .active:
                Circle()
                    .stroke(Color.craftberryOrange, lineWidth: 2)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().fill(Color.craftberryOrange).frame(width: 8, height: 8))
            case .upcoming:
                Circle()
                    .stroke(Color.craftberrySurface, lineWidth: 2)
                    .frame(width: 22, height: 22)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct CraftberryPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(LinearGradient(colors: [.craftberryGold, .craftberryOrange], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private struct CraftberrySecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.craftberrySurface, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct CraftberryRoundButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(LinearGradient(colors: [.craftberryGold, .craftberryOrange], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private extension Color {
    static let craftberryBackground = Color(red: 0.075, green: 0.079, blue: 0.095)
    static let craftberrySurface = Color(red: 0.118, green: 0.125, blue: 0.15)
    static let craftberryText = Color(red: 0.87, green: 0.875, blue: 0.9)
    static let craftberryMuted = Color(red: 0.54, green: 0.55, blue: 0.61)
    static let craftberryGold = Color(red: 0.95, green: 0.61, blue: 0.22)
    static let craftberryOrange = Color(red: 0.86, green: 0.29, blue: 0.13)
    static let craftberryBlue = Color(red: 0.36, green: 0.61, blue: 0.98)
    static let craftberryRecipeSlot = Color(red: 0.08, green: 0.085, blue: 0.105)
    static let craftberryStick = Color(red: 0.55, green: 0.33, blue: 0.16)
}

private extension IngredientSummary {
    var color: Color {
        switch path {
        case "diamond": .craftberryBlue
        case "emerald": .green
        case "iron_ingot": .gray
        case "gold_ingot": .craftberryGold
        case "netherite_ingot": .purple
        case "amethyst_shard": .purple
        case "blaze_rod": .orange
        case "redstone": .red
        case "lapis_lazuli": .blue
        case "quartz": .white
        default: .craftberryMuted
        }
    }
}

private struct ActivitySheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
#endif
