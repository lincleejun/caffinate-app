import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("设置")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            Stepper("专注：\(state.focusMinutes) 分钟",
                    value: $state.focusMinutes, in: 1...120)
            Stepper("休息：\(state.restMinutes) 分钟",
                    value: $state.restMinutes, in: 1...60)

            Toggle("专注时自动防休眠", isOn: $state.autoCaffeinate)

            Toggle("专注时静音通知（联动系统 Focus）", isOn: $state.linkSystemFocus)
            if state.linkSystemFocus {
                Text("需在「快捷指令」中建立 “Caffinate Focus On” 与 “Caffinate Focus Off”")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Picker("防休眠自动关闭", selection: $state.autoOffHours) {
                Text("从不").tag(0.0)
                Text("1 小时").tag(1.0)
                Text("2 小时").tag(2.0)
                Text("4 小时").tag(4.0)
                Text("8 小时").tag(8.0)
            }

            if LoginItem.isAvailable {
                Toggle("登录时启动", isOn: $launchAtLogin)
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
