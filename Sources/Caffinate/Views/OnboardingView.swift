import SwiftUI

/// 首启引导：在 popover 内展示一次，介绍能力并把可选权限/联动一次配好。
struct OnboardingView: View {
    @EnvironmentObject var state: AppState
    private var axTrusted: Bool { CaffeineController.accessibilityTrusted }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to Caffinate ☕🍅")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Theme.coffee)
                Text("Keep-awake + pomodoro, lives in the menu bar, also driven by the caf CLI.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            row(icon: "cup.and.saucer.fill", title: "Three keep-awake modes",
                desc: "Basic blocks display/system sleep; Enhanced also resets the idle timer, needs Accessibility.") {
                if !axTrusted {
                    Button("Grant Accessibility") { CaffeineController.openAccessibilitySettings() }
                        .buttonStyle(.link).font(.caption).tint(Theme.coffee)
                } else {
                    Text("Accessibility granted ✓").font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }

            row(icon: "timer", title: "Pomodoro + history",
                desc: "25/5 adjustable, countdown in the menu bar; runs are logged automatically, view below or with caf history.") {
                EmptyView()
            }

            row(icon: "moon.fill", title: "Link system Focus while focusing (optional)",
                desc: "Auto-enables Do Not Disturb while focusing. Set up Shortcuts first — see README.") {
                Toggle("Enable linking", isOn: $state.linkSystemFocus)
                    .font(.caption).toggleStyle(.switch).controlSize(.mini)
            }

            Button {
                state.didOnboard = true
            } label: {
                Text("Get started")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.coffee)
            .controlSize(.large)
        }
        .padding(14)
        .frame(width: 280)
        .background(Theme.cream)
    }

    @ViewBuilder
    private func row<Action: View>(icon: String, title: String, desc: String,
                                   @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(Theme.coffee)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).foregroundStyle(Theme.textPrimary)
                Text(desc).font(.caption2).foregroundStyle(Theme.textSecondary)
                action()
            }
        }
    }
}
