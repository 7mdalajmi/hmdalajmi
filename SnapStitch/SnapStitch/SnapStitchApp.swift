import SwiftUI
import UIKit

@main
struct SnapStitchApp: App {
    @StateObject private var viewModel = StitchViewModel()

    init() {
        // Navigation titles are drawn by UIKit, so they need the font set on the appearance proxy.
        let navBar = UINavigationBar.appearance()
        navBar.largeTitleTextAttributes = [.font: AppFont.uiFont(34, weight: .bold, textStyle: .largeTitle)]
        navBar.titleTextAttributes = [.font: AppFont.uiFont(17, weight: .bold, textStyle: .headline)]
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .font(Theme.body)
                .tint(Theme.accent)
        }
    }
}
