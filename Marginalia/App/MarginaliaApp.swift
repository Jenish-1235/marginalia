import SwiftUI

@main
struct MarginaliaApp: App {
    @State private var app = AppEnvironment.live()

    init() {
        Theme.applyAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .monochromeTheme()
        }
    }
}
