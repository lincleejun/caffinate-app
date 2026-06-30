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

    /// 是否已完成首启引导。false 时 popover 显示引导。
    @Published var didOnboard: Bool {
        didSet { defaults.set(didOnboard, forKey: "didOnboard") }
    }

    private let defaults = UserDefaults.standard
    private var ticker: Timer?
    private var caffeineElevatedByPomodoro = false
    private let focusLinker = FocusLinker(vendor: ShortcutsFocusVendor())
    private let historySink = CSVHistorySink(url: CSVHistorySink.defaultURL)
    private lazy var historyTracker = HistoryTracker(sink: historySink)
    private var cancellables = Set<AnyCancellable>()
    private var controlServer: ControlServer?

    // MARK: - Hooks（状态变化 → 外部脚本）
    let hooks = HookEngine()
    /// 下一次咖啡因改档的来源标记。已知来源处（pomodoro/cli）置位，sink 读后复位为
    /// manual。UI 直接调 caffeine.set 不置位 → 默认 manual；auto-off/wake 退化为 manual。
    var caffeineSourceHint = "manual"
    /// 追踪上一档，给 caffeine hook 提供 prev_mode。
    private var previousCaffeineMode: CaffeineController.Mode = .off

    private static func phaseCSV(_ p: PomodoroEngine.Phase) -> String {
        switch p { case .idle: return "idle"; case .focus: return "focus"; case .rest: return "rest" }
    }
    private static let isoFormatter = ISO8601DateFormatter()
    private static func iso(_ d: Date) -> String { isoFormatter.string(from: d) }

    /// 发一个番茄钟事件（phase/remaining 显式传入，避免引擎已切档导致语义错位）。
    private func dispatchPomodoroHook(_ name: String, phase: PomodoroEngine.Phase, remaining: TimeInterval) {
        hooks.dispatch(HookEvent(name: name, fields: [
            ("phase", Self.phaseCSV(phase)),
            ("remaining_sec", String(Int(max(0, remaining)))),
            ("ts", Self.iso(Date())),
        ]))
    }

    /// 发一个咖啡因事件，并复位来源提示位。
    private func dispatchCaffeineHook(from prev: CaffeineController.Mode, to mode: CaffeineController.Mode) {
        hooks.dispatch(HookEvent(name: "caffeine.\(Self.modeCSV(mode))", fields: [
            ("mode", Self.modeCSV(mode)),
            ("prev_mode", Self.modeCSV(prev)),
            ("source", caffeineSourceHint),
            ("ts", Self.iso(Date())),
        ]))
        caffeineSourceHint = "manual"
    }

    private static func modeCSV(_ m: CaffeineController.Mode) -> String {
        switch m { case .off: return "off"; case .basic: return "basic"; case .enhanced: return "enhanced" }
    }
    /// menubar 取 6 条，CLI 取更多——这里只刷新 menubar 镜像。
    private func refreshHistory() { recentHistory = historySink.recent(6) }
    /// 供 ControlServer/CLI 用：最近 n 条。
    func history(_ n: Int) -> [HistoryRecord] { historySink.recent(n) }

    /// 健康自检快照（供 `caf doctor`）。
    func diagnostics() -> Diagnostics {
        Diagnostics(
            caffeineMode: Self.modeCSV(caffeine.mode),
            holdsAssertion: caffeine.holdsAssertion,
            accessibilityTrusted: CaffeineController.accessibilityTrusted,
            linkSystemFocus: linkSystemFocus,
            focusShortcutsInstalled: ShortcutsFocusVendor.installed(),
            historyPath: historySink.path,
            historyWritable: FileManager.default.isWritableFile(atPath: historySink.path)
        )
    }

    init() {
        let focus = defaults.object(forKey: "focusMinutes") as? Int ?? 25
        let rest = defaults.object(forKey: "restMinutes") as? Int ?? 5
        focusMinutes = focus
        restMinutes = rest
        autoCaffeinate = defaults.object(forKey: "autoCaffeinate") as? Bool ?? true
        autoOffHours = defaults.object(forKey: "autoOffHours") as? Double ?? 0
        linkSystemFocus = defaults.object(forKey: "linkSystemFocus") as? Bool ?? false
        didOnboard = defaults.object(forKey: "didOnboard") as? Bool ?? false
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
        // 咖啡因档位变化 → 触发 hook。dropFirst 跳过订阅时的初始 .off，避免启动即触发。
        hooks.ensureDirectory()
        caffeine.$mode
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] mode in
                guard let self else { return }
                let prev = self.previousCaffeineMode
                self.previousCaffeineMode = mode
                self.dispatchCaffeineHook(from: prev, to: mode)
            }
            .store(in: &cancellables)
        // App 退出：收尾未结束的咖啡因段（queue: .main 保证主线程，可安全 assumeIsolated）
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.historyTracker.flush(at: Date()) }
        }
        recentHistory = historySink.recent(6)
        requestNotificationPermission()
        controlServer = ControlServer(state: self)
        controlServer?.start()
    }

    // MARK: - 番茄钟操作
    func startFocus() {
        if autoCaffeinate && caffeine.mode == .off {
            caffeineSourceHint = "pomodoro"
            caffeine.set(.basic)
            caffeineElevatedByPomodoro = true
        }
        engine.startFocus()
        historyTracker.pomodoroBegan("focus", at: Date())
        dispatchPomodoroHook("pomodoro.focus.start", phase: .focus, remaining: engine.remaining)
        syncFromEngine()
        startTicker()
    }

    func pause() {
        let wasActive = engine.phase != .idle && !engine.isPaused
        engine.pause()
        if wasActive {
            dispatchPomodoroHook("pomodoro.pause", phase: engine.phase, remaining: engine.remaining)
        }
        syncFromEngine()
    }

    func resume() {
        let wasPaused = engine.phase != .idle && engine.isPaused
        engine.resume()
        if wasPaused {
            dispatchPomodoroHook("pomodoro.resume", phase: engine.phase, remaining: engine.remaining)
        }
        syncFromEngine()
    }

    func reset() {
        let endedPhase = engine.phase
        let remainingAtReset = engine.remaining
        let wasRunning = endedPhase != .idle
        engine.reset()
        if wasRunning {
            historyTracker.pomodoroEnded(completed: false, at: Date())
            dispatchPomodoroHook("pomodoro.\(Self.phaseCSV(endedPhase)).interrupted",
                                 phase: endedPhase, remaining: remainingAtReset)
        }
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
            dispatchPomodoroHook("pomodoro.focus.end", phase: .focus, remaining: 0)
            historyTracker.pomodoroBegan("rest", at: now)       // 紧接进入休息段
            // 此刻 engine 已切到 rest，remaining 即休息时长
            dispatchPomodoroHook("pomodoro.rest.start", phase: .rest, remaining: engine.remaining)
            // 专注结束进入休息：先关掉系统 Focus，关完再发「专注结束」通知，
            // 否则通知会被勿扰吞掉。未开启联动时 disengage 会立即跑回调。
            focusLinker.disengage(then: { [weak self] in self?.notify(ended) })
        } else {
            dispatchPomodoroHook("pomodoro.rest.end", phase: .rest, remaining: 0)
            notify(ended)
            restoreCaffeineIfNeeded()
        }
        refreshHistory()
    }

    /// 番茄钟自动开启的防休眠，整个周期结束（或重置）时恢复为关
    private func restoreCaffeineIfNeeded() {
        if caffeineElevatedByPomodoro {
            caffeineSourceHint = "pomodoro"
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
        NSSound(named: "Ping")?.play()   // 清脆「叮」提示音
        guard canUseNotifications else { return }
        let content = UNMutableNotificationContent()
        if ended == .focus {
            content.title = String(localized: "Focus done 🍅")
            content.body = String(localized: "Nice work — take a \(restMinutes) min break")
        } else {
            content.title = String(localized: "Break over ☕")
            content.body = String(localized: "Ready for the next pomodoro?")
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
