import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            Stepper("Focus: \(state.focusMinutes) min",
                    value: $state.focusMinutes, in: 1...120)
            Stepper("Break: \(state.restMinutes) min",
                    value: $state.restMinutes, in: 1...60)

            Toggle("Auto keep-awake while focusing", isOn: $state.autoCaffeinate)

            Toggle("Silence notifications while focusing (link system Focus)", isOn: $state.linkSystemFocus)
            if state.linkSystemFocus {
                Text("Create “Caffinate Focus On” and “Caffinate Focus Off” in the Shortcuts app")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Picker("Auto-disable keep-awake", selection: $state.autoOffHours) {
                Text("Never").tag(0.0)
                Text("1 hour").tag(1.0)
                Text("2 hours").tag(2.0)
                Text("4 hours").tag(4.0)
                Text("8 hours").tag(8.0)
            }

            if LoginItem.isAvailable {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        if !LoginItem.set(enabled: on) {
                            launchAtLogin = LoginItem.isEnabled
                        }
                    }
            }
        }
        .font(.callout)
        .foregroundStyle(Theme.textPrimary)
        .card()
    }
}
