import SwiftUI
import UIKit

/// Monochrome palette: matte black and charcoal surfaces, white ink. No hues anywhere in the UI.
enum Theme {
    // Surfaces, darkest to lightest.
    static let backgroundUI = UIColor(white: 0.055, alpha: 1)   // #0E0E0E matte black
    static let surfaceUI = UIColor(white: 0.090, alpha: 1)      // #171717 charcoal
    static let elevatedUI = UIColor(white: 0.130, alpha: 1)     // #212121 raised charcoal
    static let hairlineUI = UIColor(white: 1, alpha: 0.09)

    // Ink.
    static let inkUI = UIColor(white: 0.95, alpha: 1)           // #F2F2F2 soft white
    static let inkSecondaryUI = UIColor(white: 1, alpha: 0.60)
    static let inkTertiaryUI = UIColor(white: 1, alpha: 0.38)

    static let background = Color(backgroundUI)
    static let surface = Color(surfaceUI)
    static let elevated = Color(elevatedUI)
    static let hairline = Color(hairlineUI)
    static let ink = Color(inkUI)
    static let inkSecondary = Color(inkSecondaryUI)
    static let inkTertiary = Color(inkTertiaryUI)

    /// UIKit chrome that SwiftUI modifiers don't reach.
    static func applyAppearance() {
        let bar = UINavigationBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = backgroundUI
        bar.shadowColor = hairlineUI
        bar.titleTextAttributes = [.foregroundColor: inkUI]
        bar.largeTitleTextAttributes = [.foregroundColor: inkUI]
        UINavigationBar.appearance().standardAppearance = bar
        UINavigationBar.appearance().scrollEdgeAppearance = bar
        UINavigationBar.appearance().compactAppearance = bar

        let toolbar = UIToolbarAppearance()
        toolbar.configureWithOpaqueBackground()
        toolbar.backgroundColor = backgroundUI
        toolbar.shadowColor = hairlineUI
        UIToolbar.appearance().standardAppearance = toolbar
        UIToolbar.appearance().scrollEdgeAppearance = toolbar
    }
}

extension View {
    /// Root styling for every window: forced dark, white tint, matte black background.
    func monochromeTheme() -> some View {
        self
            .preferredColorScheme(.dark)
            .tint(Theme.ink)
            .background(Theme.background.ignoresSafeArea())
    }
}
