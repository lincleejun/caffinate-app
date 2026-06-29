import SwiftUI

@main
struct CaffinateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()
    @StateObject private var updater = UpdaterModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(state)
                .environmentObject(updater)
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
