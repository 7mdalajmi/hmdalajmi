import SwiftUI

@main
struct SnapStitchApp: App {
    @StateObject private var viewModel = StitchViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
    }
}
