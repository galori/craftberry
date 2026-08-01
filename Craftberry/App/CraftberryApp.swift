#if canImport(SwiftUI)
import SwiftUI

@main
struct CraftberryApp: App {
    var body: some Scene {
        WindowGroup {
            CreationView(
                viewModel: CreationViewModel(
                    apiKey: Bundle.main.object(forInfoDictionaryKey: "OpenAIAPIKey") as? String ?? ""
                )
            )
        }
    }
}
#endif
