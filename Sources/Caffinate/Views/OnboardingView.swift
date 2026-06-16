import SwiftUI

/// 首启引导：在 popover 内展示一次，介绍能力并把可选权限/联动一次配好。
struct OnboardingView: View {
    @EnvironmentObject var state: AppState
    private var axTrusted: Bool { CaffeineController.accessibilityTrusted }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("欢迎使用 Caffinate ☕🍅")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Theme.coffee)
                Text("防休眠 + 番茄钟,菜单栏常驻,也能用 caf 命令行控制。")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            row(icon: "cup.and.saucer.fill", title: "防休眠三档",
                desc: "基础挡熄屏/休眠;增强额外重置系统空闲,需「辅助功能」授权。") {
                if !axTrusted {
                    Button("去授权辅助功能") { CaffeineController.openAccessibilitySettings() }
                        .buttonStyle(.link).font(.caption).tint(Theme.coffee)
                } else {
                    Text("辅助功能已授权 ✓").font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }

            row(icon: "timer", title: "番茄钟 + 历史",
                desc: "25/5 可调,菜单栏显示倒计时;运行历史自动记录,可在下方与 caf history 查看。") {
                EmptyView()
            }

            row(icon: "moon.fill", title: "专注时联动系统 Focus(可选)",
                desc: "专注时自动开系统勿扰静音通知。需先在「快捷指令」建好,详见 README。") {
                Toggle("开启联动", isOn: $state.linkSystemFocus)
                    .font(.caption).toggleStyle(.switch).controlSize(.mini)
            }

            Button {
                state.didOnboard = true
            } label: {
                Text("开始使用")
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
