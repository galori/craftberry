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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Make a Minecraft sword")
                        .font(.largeTitle.bold())
                    Text("Describe one colorful sword. Craftberry turns it into a Bedrock add-on you can open on this iPhone.")
                        .foregroundStyle(.secondary)

                    TextEditor(text: $viewModel.prompt)
                        .frame(minHeight: 120)
                        .padding(12)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel("Sword description")

                    Button {
                        Task { await viewModel.generate() }
                    } label: {
                        Label("Generate sword", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(viewModel.isBusy)

                    result
                }
                .padding()
            }
            .navigationTitle("Craftberry")
        }
        .sheet(item: $shareItem) { item in
            ActivitySheet(url: item.url)
        }
    }

    @ViewBuilder
    private var result: some View {
        switch viewModel.state {
        case .editing:
            Label("Try: “Create a blue sword with +20 attack bonus crafted from diamonds.”", systemImage: "lightbulb")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .generating:
            ProgressView("Understanding your sword…")
                .frame(maxWidth: .infinity, alignment: .leading)
        case .packaging:
            ProgressView("Packaging your add-on…")
                .frame(maxWidth: .infinity, alignment: .leading)
        case .unsupported(let message), .failed(let message):
            messageCard(message, color: .orange)
        case .ready(let sword):
            swordCard(sword, artifact: nil)
        case .packaged(let sword, let artifact):
            swordCard(sword, artifact: artifact)
        }
    }

    private func swordCard(_ sword: SwordSpec, artifact: BedrockAddOnArtifact?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                if let image = UIImage(data: SwordTextureRenderer.render(sword)) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading) {
                    Text(sword.displayName).font(.title2.bold())
                    Text("\(sword.color.rawValue.capitalized) sword")
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent("Attack bonus", value: "+\(sword.attackBonus)")
            LabeledContent("Durability", value: "\(sword.durability)")
            LabeledContent("Recipe", value: "2 \(sword.craftingIngredient.displayName) + 1 Stick")

            if let artifact {
                Button {
                    shareItem = ShareItem(url: artifact.url)
                } label: {
                    Label("Open in Minecraft", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Text("Choose Minecraft in the share sheet. Then enable the behavior pack in a world and use \(artifact.giveCommand) if needed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Button("Create Add-On") { viewModel.package(sword) }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }

            Button("Start over") { viewModel.reset() }
                .frame(maxWidth: .infinity)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func messageCard(_ message: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
            Button("Try again") { viewModel.reset() }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct ActivitySheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
#endif
