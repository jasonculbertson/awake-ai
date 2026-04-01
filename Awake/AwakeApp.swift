import SwiftUI

@main
struct AwakeApp: App {
    @StateObject private var viewModel = MenuBarViewModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverContentView()
                .environmentObject(viewModel)
        } label: {
            Image(systemName: viewModel.isAwake ? "sun.max.fill" : "moon.zzz")
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.window)
    }
}
