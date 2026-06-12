import AppKit
import Combine
import CaffinateKit
import UserNotifications

@MainActor
final class AppState: ObservableObject {
    let caffeine = CaffeineController()
    let engine: PomodoroEngine

    // 镜像 engine 状态供 SwiftUI 观察
    @Published private(set) var phase: PomodoroEngine.Phase = .idle
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var isPaused = false

    // MARK: - 设置（UserDefaults 持久化）
    @Published var focusMinutes: Int {
        didSet {
            defaults.set(focusMinutes, forKey: "focusMinutes")
            engine.focusDuration = TimeInterval(focusMinutes * 60)
        }
    }
    @Published var restMinutes: Int {
        didSet {
            defaults.set(restMinutes, forKey: "restMinutes")
            engine.restDuration = TimeInterval(restMinutes * 60)
        }
    }
    @Published var autoCaffeinate: Bool {
        didSet { defaults.set(autoCaffeinate, forKey: "autoCaffeinate") }
    }
    @Published var autoOffHours: Double {
        didSet {
            defaults.set(autoOffHours, forKey: "autoOffHours")
            caffeine.autoOffHours = autoOffHours
        }
    }

    private let defaults = UserDefaults.standard
    private var ticker: Timer?
    private var caffeineElevatedByPomodoro = false
    private var cancellables = Set<AnyCancellable>()
    private var controlServer: ControlServer?

    init() {
        let focus = defaults.object(forKey: "focusMinutes") as? Int ?? 25
        let rest = defaults.object(forKey: "restMinutes") as? Int ?? 5
        focusMinutes = focus
        restMinutes = rest
        autoCaffeinate = defaults.object(forKey: "autoCaffeinate") as? Bool ?? true
        autoOffHours = defaults.object(forKey: "autoOffHours") as? Double ?? 0
        engine = PomodoroEngine(
            focusDuration: TimeInterval(focus * 60),
            restDuration: TimeInterval(rest * 60)
        )
        caffeine.autoOffHours = autoOffHours
        engine.onPhaseEnd = { [weak self] ended in self?.phaseDidEnd(ended) }
        // 转发子对象变更，驱动菜单栏图标刷新
        caffeine.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        requestNotificationPermission()
        controlServer = ControlServer(state: self)
        controlServer?.start()
    }

    // MARK: - 番茄钟操作
    func startFocus() {
        if autoCaffeinate && caffeine.mode == .off {
            caffeine.set(.basic)
            caffeineElevatedByPomodoro = true
        }
        engine.startFocus()
        syncFromEngine()
        startTicker()
    }

    func pause() { engine.pause(); syncFromEngine() }
    func resume() { engine.resume(); syncFromEngine() }

    func reset() {
        engine.reset()
        syncFromEngine()
        stopTicker()
        restoreCaffeineIfNeeded()
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stopTicker() { ticker?.invalidate(); ticker = nil }

    private func tick() {
        engine.tick(1)
        syncFromEngine()
        if engine.phase == .idle { stopTicker() }
    }

    private func syncFromEngine() {
        phase = engine.phase
        remaining = max(0, engine.remaining)
        isPaused = engine.isPaused
    }

    private func phaseDidEnd(_ ended: PomodoroEngine.Phase) {
        notify(ended)
        if ended == .rest { restoreCaffeineIfNeeded() }
    }

    /// 番茄钟自动开启的防休眠，整个周期结束（或重置）时恢复为关
    private func restoreCaffeineIfNeeded() {
        if caffeineElevatedByPomodoro {
            caffeine.set(.off)
            caffeineElevatedByPomodoro = false
        }
    }

    // MARK: - 通知（裸二进制 swift run 时无 bundle，必须守卫，否则崩溃）
    private var canUseNotifications: Bool { Bundle.main.bundleIdentifier != nil }

    private func requestNotificationPermission() {
        guard canUseNotifications else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(_ ended: PomodoroEngine.Phase) {
        NSSound(named: "Glass")?.play()
        guard canUseNotifications else { return }
        let content = UNMutableNotificationContent()
        if ended == .focus {
            content.title = "专注结束 🍅"
            content.body = "干得漂亮，休息 \(restMinutes) 分钟吧"
        } else {
            content.title = "休息结束 ☕"
            content.body = "来开始下一个番茄？"
        }
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    // MARK: - 展示辅助
    var timeText: String {
        let s = Int(remaining.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    var progress: Double { engine.progress }

    /// 番茄运行中（含暂停）显示倒计时，否则 nil（显示咖啡杯图标）
    var menuBarTitle: String? {
        guard phase != .idle else { return nil }
        return "🍅 \(timeText)"
    }
}
