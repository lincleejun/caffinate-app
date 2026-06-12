import Foundation

/// 番茄钟纯状态机。不持有 Timer——由外部按秒调用 tick(_:)，因此可同步测试。
public final class PomodoroEngine {
    public enum Phase: Equatable {
        case idle, focus, rest
    }

    public private(set) var phase: Phase = .idle
    public private(set) var remaining: TimeInterval = 0
    public private(set) var isPaused = false

    public var focusDuration: TimeInterval
    public var restDuration: TimeInterval

    /// 一个阶段（focus/rest）走完时回调，参数为刚结束的阶段。
    public var onPhaseEnd: ((Phase) -> Void)?

    public init(focusDuration: TimeInterval = 25 * 60, restDuration: TimeInterval = 5 * 60) {
        self.focusDuration = focusDuration
        self.restDuration = restDuration
    }

    public var isRunning: Bool { phase != .idle && !isPaused }

    public func startFocus() {
        phase = .focus
        remaining = focusDuration
        isPaused = false
    }

    public func pause() {
        guard phase != .idle else { return }
        isPaused = true
    }

    public func resume() {
        guard phase != .idle else { return }
        isPaused = false
    }

    public func reset() {
        phase = .idle
        remaining = 0
        isPaused = false
    }

    public func tick(_ seconds: TimeInterval = 1) {
        guard isRunning else { return }
        remaining -= seconds
        if remaining <= 0 {
            let ended = phase
            switch ended {
            case .focus:
                phase = .rest
                remaining = restDuration
            case .rest, .idle:
                reset()
            }
            onPhaseEnd?(ended)
        }
    }

    /// 0...1，圆环进度
    public var progress: Double {
        guard phase != .idle else { return 0 }
        let total = phase == .focus ? focusDuration : restDuration
        guard total > 0 else { return 0 }
        return 1 - max(0, remaining) / total
    }
}
