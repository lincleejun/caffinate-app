import SwiftUI

struct CaffeineCard: View {
    @EnvironmentObject var state: AppState
    @State private var axTrusted = CaffeineController.accessibilityTrusted

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "cup.and.saucer.fill")
                    .foregroundStyle(Theme.coffee)
                Text("咖啡因")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
            }

            Picker("", selection: Binding(
                get: { state.caffeine.mode },
                set: { state.caffeine.set($0) }
            )) {
                ForEach(CaffeineController.Mode.allCases) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(statusText)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

            if !axTrusted {
                Button {
                    CaffeineController.openAccessibilitySettings()
                } label: {
                    Label("增强档需授权「辅助功能」，点此前往", systemImage: "lock.shield")
                        .font(.caption)
                }
                .buttonStyle(.link)
                .tint(Theme.coffee)
            }

            if let err = state.caffeine.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .card()
        .onAppear { axTrusted = CaffeineController.accessibilityTrusted }
    }

    private var statusText: String {
        switch state.caffeine.mode {
        case .off: return "电脑按系统设置正常休眠"
        case .basic: return "已阻止熄屏与休眠"
        case .enhanced: return "已阻止熄屏 + 每 50 秒重置空闲计时"
        }
    }
}
