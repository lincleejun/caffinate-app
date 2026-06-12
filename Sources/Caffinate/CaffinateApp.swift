import SwiftUI

@main
struct CaffinateApp: App {
    var body: some Scene {
        MenuBarExtra {
            Text("Caffinate")
                .padding()
        } label: {
            Image(systemName: "cup.and.saucer")
        }
        .menuBarExtraStyle(.window)
    }
}
