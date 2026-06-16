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
    /// 专注时联动系统 Focus（静音通知）。默认关——需用户先建两个快捷指令。
    @Published var linkSystemFocus: Bool {
        didSet {
            defaults.set(linkSystemFocus, forKey: "linkSystemFocus")
            syncFocusLink()
        }
    }

    /// menubar 展示用：最近若干条运行历史（最新在前）。
    @Published private(set) var recentHistory: [HistoryRecord] = []

    private let defaults = UserDefaults.standard
    private var ticker: Timer?
    private var caffeineElevatedByPomodoro = false
    private let focusLinker = FocusLinker(vendor: ShortcutsFocusVendor())
    private let historySink = CSVHistorySink(url: CSVHistorySink.defaultURL)
    private lazy var historyTracker = HistoryTracker(sink: historySink)
    private var cancellables = Set<AnyCancellable>()
    private var controlServer: ControlServer?

    private static func modeCSV(_ m: CaffeineController.Mode) -> String {
        switch m { case .off: return "off"; case .basic: return "basic"; case .enhanced: return "enhanced" }
    }
    /// menubar 取 6 条，CLI 取更多——这里只刷新 menubar 镜像。
    private func refreshHistory() { recentHistory = historySink.recent(6) }
    /// 供 ControlServer/CLI 用：最近 n 条。
    func history(_ n: Int) -> [HistoryRecord] { historySink.recent(n) }

    init() {
        let focus = defaults.object(forKey: "focusMinutes") as? Int ?? 25
        let rest = defaults.object(forKey: "restMinutes") as? Int ?? 5
        focusMinutes = focus
        restMinutes = rest
        autoCaffeinate = defaults.object(forKey: "autoCaffeinate") as? Bool ?? true
        autoOffHours = defaults.object(forKey: "autoOffHours") as? Double ?? 0
        linkSystemFocus = defaults.object(forKey: "linkSystemFocus") as? Bool ?? false
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
        // 咖啡因档位变化 → 记历史（覆盖手动与自动所有改档路径）
        caffeine.$mode
            .removeDuplicates()
            .sink { [weak self] mode in
                guard let self else { return }
                self.historyTracker.caffeine(changedTo: Self.modeCSV(mode), at: Date())
                self.refreshHistory()
            }
            .store(in: &cancellables)
        // App 退出：收尾未结束的咖啡因段
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.historyTracker.flush(at: Date()) }
        recentHistory = historySink.recent(6)
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
        historyTracker.pomodoroBegan("focus", at: Date())
        syncFromEngine()
        startTicker()
    }

    func pause() { engine.pause(); syncFromEngine() }
    func resume() { engine.resume(); syncFromEngine() }

    func reset() {
        let wasRunning = engine.phase != .idle
        engine.reset()
        if wasRunning { historyTracker.pomodoroEnded(completed: false, at: Date()) }
        syncFromEngine()
        stopTicker()
        restoreCaffeineIfNeeded()
        refreshHistory()
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
        syncFocusLink()
    }

    /// 系统 Focus 应在「联动开启 且 正专注 且 未暂停」时打开，其余一律关闭。
    /// 单一出口，覆盖开始/暂停/继续/重置/进入休息所有路径；FocusLinker 自身幂等。
    private func syncFocusLink() {
        if linkSystemFocus, engine.phase == .focus, !engine.isPaused {
            focusLinker.engage()
        } else {
            focusLinker.disengage()
        }
    }

    private func phaseDidEnd(_ ended: PomodoroEngine.Phase) {
        let now = Date()
        historyTracker.pomodoroEnded(completed: true, at: now)  // 自然走完 → completed
        if ended == .focus {
            historyTracker.pomodoroBegan("rest", at: now)       // 紧接进入休息段
            // 专注结束进入休息：先关掉系统 Focus，关完再发「专注结束」通知，
            // 否则通知会被勿扰吞掉。未开启联动时 disengage 会立即跑回调。
            focusLinker.disengage(then: { [weak self] in self?.notify(ended) })
        } else {
            notify(ended)
            restoreCaffeineIfNeeded()
        }
        refreshHistory()
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
