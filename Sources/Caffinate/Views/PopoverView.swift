import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var state: AppState
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Caffinate")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Theme.coffee)
                Spacer()
                Button {
                    withAnimation(.snappy) { showSettings.toggle() }
                } label: {
                    Image(systemName: showSettings ? "xmark.circle.fill" : "gearshape.fill")
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            if showSettings {
                SettingsView()
            } else {
                CaffeineCard()
                PomodoroCard()
            }

            HStack {
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(14)
        .frame(width: 280)
        .background(Theme.cream)
    }
}
