import SwiftUI

struct CaffeineCard: View {
    @EnvironmentObject var state: AppState

    // 每次重渲染实时取值，授权后提示即时消失
    private var axTrusted: Bool { CaffeineController.accessibilityTrusted }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "cup.and.saucer.fill")
                    .foregroundStyle(Theme.coffee)
                Text("Caffeine")
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
                    Label("Enhanced mode needs Accessibility — open Settings", systemImage: "lock.shield")
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
    }

    private var statusText: String {
        switch state.caffeine.mode {
        case .off: return String(localized: "Sleeps normally per system settings")
        case .basic: return String(localized: "Display sleep & system sleep blocked")
        case .enhanced: return String(localized: "Sleep blocked + idle timer reset every 50s")
        }
    }
}
