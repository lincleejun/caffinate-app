import SwiftUI

struct PomodoroCard: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Theme.tomato.opacity(0.12), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: state.phase == .idle ? 0 : state.progress)
                    .stroke(
                        AngularGradient(
                            colors: [Theme.tomato, Theme.tomatoDark],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: state.progress)

                VStack(spacing: 2) {
                    Text(state.phase == .idle ? "\(state.focusMinutes):00" : state.timeText)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    Text(phaseLabel)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 150, height: 150)

            controls
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private var phaseLabel: String {
        switch state.phase {
        case .idle: return "准备就绪"
        case .focus: return state.isPaused ? "专注 · 已暂停" : "专注中"
        case .rest: return state.isPaused ? "休息 · 已暂停" : "休息中"
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 10) {
            if state.phase == .idle {
                Button {
                    state.startFocus()
                } label: {
                    Label("开始专注", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.tomato)
                .controlSize(.large)
            } else {
                Button {
                    state.isPaused ? state.resume() : state.pause()
                } label: {
                    Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.tomato)
                .controlSize(.large)

                Button {
                    state.reset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Theme.coffee)
                .controlSize(.large)
            }
        }
    }
}
