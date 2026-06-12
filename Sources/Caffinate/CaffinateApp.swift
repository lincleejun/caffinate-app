import SwiftUI

@main
struct CaffinateApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(state)
        } label: {
            if let title = state.menuBarTitle {
                Text(title)
            } else {
                Image(systemName: state.caffeine.mode == .off
                      ? "cup.and.saucer" : "cup.and.saucer.fill")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
