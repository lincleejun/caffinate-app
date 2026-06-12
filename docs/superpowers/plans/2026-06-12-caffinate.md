# Caffinate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 原生 SwiftUI 菜单栏小助手：三态防休眠（关/基础/增强）+ 极简番茄钟，奶油暖调 UI，无 Xcode 构建。

**Architecture:** SPM 三 target——`CaffinateKit`（纯逻辑库：番茄状态机）、`Caffinate`（菜单栏 App：MenuBarExtra + IOPMAssertion + CGEvent）、`caffinate-tests`（自带断言的测试可执行，因 CLT 环境无 XCTest/Testing 模块）。打包脚本手写 Info.plist 生成 `.app`。

**Tech Stack:** Swift 6.2（v5 语言模式）/ SwiftUI MenuBarExtra / IOKit.pwr_mgt / CGEvent / UserNotifications / ServiceManagement。零第三方依赖。

**前置事实（已预检验证）：**
- 本机仅有 Command Line Tools，`swift build` 可编译 SwiftUI/MenuBarExtra/IOKit。
- `import XCTest` 和 `import Testing` 在 CLT 下均不可用 → 测试用独立可执行 target。
- 裸二进制（`swift run`）下 `Bundle.main.bundleIdentifier == nil`，UserNotifications/SMAppService 会崩溃或失败 → 相关代码必须做 bundle 守卫。

---

### Task 1: SPM 脚手架 + 最小可运行菜单栏 App

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Sources/CaffinateKit/PomodoroEngine.swift`（空壳占位，Task 2 实现）
- Create: `Sources/Caffinate/CaffinateApp.swift`

- [ ] **Step 1: 写 Package.swift**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Caffinate",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CaffinateKit", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "Caffinate",
            dependencies: ["CaffinateKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "caffinate-tests",
            dependencies: ["CaffinateKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

- [ ] **Step 2: 写 .gitignore**

```
.build/
dist/
.DS_Store
```

- [ ] **Step 3: 创建空壳 Kit 文件（让库 target 可编译）**

`Sources/CaffinateKit/PomodoroEngine.swift`：

```swift
// Task 2 中以 TDD 方式实现
```

- [ ] **Step 4: 最小 App 入口**

`Sources/Caffinate/CaffinateApp.swift`：

```swift
import SwiftUI

@main
struct CaffinateApp: App {
    var body: some Scene {
        MenuBarExtra {
            Text("Caffinate")
                .padding()
        } label: {
            Image(systemName: "cup.and.saucer")
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 5: 占位测试 target**

`Sources/caffinate-tests/main.swift`：

```swift
print("no tests yet")
```

- [ ] **Step 6: 验证编译**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: SPM scaffold with minimal menu bar app"
```

---

### Task 2: PomodoroEngine 状态机（TDD）

**Files:**
- Modify: `Sources/caffinate-tests/main.swift`（先写测试）
- Modify: `Sources/CaffinateKit/PomodoroEngine.swift`（后写实现）

- [ ] **Step 1: 先写失败的测试（完整替换 main.swift）**

```swift
import Foundation
import CaffinateKit

var failures = 0
func expect(_ condition: Bool, _ label: String, line: Int = #line) {
    if condition { print("  ok - \(label)") }
    else { failures += 1; print("FAIL - \(label) (line \(line))") }
}

// 1. 初始状态
do {
    let e = PomodoroEngine()
    expect(e.phase == .idle, "初始为 idle")
    expect(e.remaining == 0, "初始剩余 0")
    expect(!e.isPaused, "初始未暂停")
}

// 2. 开始专注 + tick 递减
do {
    let e = PomodoroEngine(focusDuration: 10, restDuration: 4)
    e.startFocus()
    expect(e.phase == .focus, "startFocus 进入 focus")
    expect(e.remaining == 10, "剩余 = focusDuration")
    e.tick(1)
    expect(e.remaining == 9, "tick 递减")
}

// 3. 专注结束→休息→idle，回调按序触发（验证：阶段切换是通知/联动的依据）
do {
    let e = PomodoroEngine(focusDuration: 2, restDuration: 4)
    var ended: [PomodoroEngine.Phase] = []
    e.onPhaseEnd = { ended.append($0) }
    e.startFocus()
    e.tick(2)
    expect(e.phase == .rest, "focus 结束自动进入 rest")
    expect(e.remaining == 4, "rest 剩余 = restDuration")
    expect(ended == [.focus], "回调收到 .focus")
    e.tick(4)
    expect(e.phase == .idle, "rest 结束回 idle")
    expect(ended == [.focus, .rest], "回调收到 .rest")
}

// 4. 暂停期间时间不流逝（验证：暂停语义）
do {
    let e = PomodoroEngine(focusDuration: 10, restDuration: 4)
    e.startFocus()
    e.tick(3)
    e.pause()
    expect(e.isPaused, "pause 生效")
    e.tick(5)
    expect(e.remaining == 7, "暂停期间 tick 不生效")
    e.resume()
    e.tick(1)
    expect(e.remaining == 6, "恢复后继续递减")
}

// 5. 重置
do {
    let e = PomodoroEngine(focusDuration: 10, restDuration: 4)
    e.startFocus()
    e.tick(3)
    e.reset()
    expect(e.phase == .idle && e.remaining == 0 && !e.isPaused, "reset 完全回 idle")
}

// 6. idle 时 tick/pause 无副作用
do {
    let e = PomodoroEngine()
    e.tick(5)
    e.pause()
    expect(e.phase == .idle && e.remaining == 0 && !e.isPaused, "idle 时操作无副作用")
}

// 7. progress 供圆环 UI 使用
do {
    let e = PomodoroEngine(focusDuration: 10, restDuration: 4)
    expect(e.progress == 0, "idle progress = 0")
    e.startFocus()
    e.tick(5)
    expect(abs(e.progress - 0.5) < 0.0001, "progress 过半")
}

if failures > 0 {
    print("\n\(failures) 个失败")
    exit(1)
}
print("\n全部通过 ✅")
```

- [ ] **Step 2: 运行确认失败**

Run: `swift run caffinate-tests`
Expected: 编译错误 `cannot find 'PomodoroEngine' in scope`（即测试先行，实现缺失）

- [ ] **Step 3: 写最小实现（完整替换 PomodoroEngine.swift）**

```swift
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
```

- [ ] **Step 4: 运行确认通过**

Run: `swift run caffinate-tests`
Expected: 每行 `ok - ...`，最后 `全部通过 ✅`，退出码 0

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: pomodoro engine state machine with tests"
```

---

### Task 3: CaffeineController（防休眠三态）

**Files:**
- Create: `Sources/Caffinate/CaffeineController.swift`

说明：依赖系统副作用（IOPM assertion、CGEvent、AX 权限），无法单测，验证方式为 Task 7 的 `pmset` 实测。

- [ ] **Step 1: 写实现**

```swift
import AppKit
import IOKit.pwr_mgt

/// 防休眠控制。三态：
/// - off:      正常休眠
/// - basic:    IOPMAssertion 阻止显示器/系统 idle 休眠
/// - enhanced: basic + 每 50s 发一次 F15 幻影键重置系统空闲计时（需「辅助功能」权限）
final class CaffeineController: ObservableObject {
    enum Mode: Int, CaseIterable, Identifiable, Hashable {
        case off = 0, basic = 1, enhanced = 2
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .off: return "关"
            case .basic: return "基础"
            case .enhanced: return "增强"
            }
        }
    }

    @Published private(set) var mode: Mode = .off
    @Published var lastError: String?

    /// 0 = 从不自动关
    var autoOffHours: Double = 0

    private var assertionID: IOPMAssertionID = 0
    private var hasAssertion = false
    private var phantomKeyTimer: Timer?
    private var autoOffTimer: Timer?

    static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    static func openAccessibilitySettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    func set(_ newMode: Mode) {
        lastError = nil
        if newMode == .enhanced && !Self.accessibilityTrusted {
            lastError = "增强档需要「辅助功能」权限"
            return
        }

        if newMode == .off {
            releaseAssertion()
        } else if !hasAssertion {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Caffinate 防休眠" as CFString,
                &id
            )
            guard result == kIOReturnSuccess else {
                lastError = "防休眠开启失败 (IOKit \(result))"
                mode = .off
                return
            }
            assertionID = id
            hasAssertion = true
        }

        phantomKeyTimer?.invalidate()
        phantomKeyTimer = nil
        if newMode == .enhanced {
            phantomKeyTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: true) { _ in
                CaffeineController.postPhantomKey()
            }
        }

        rescheduleAutoOff(for: newMode)
        mode = newMode
    }

    private func rescheduleAutoOff(for newMode: Mode) {
        autoOffTimer?.invalidate()
        autoOffTimer = nil
        guard newMode != .off, autoOffHours > 0 else { return }
        autoOffTimer = Timer.scheduledTimer(
            withTimeInterval: autoOffHours * 3600, repeats: false
        ) { [weak self] _ in
            self?.set(.off)
        }
    }

    private func releaseAssertion() {
        if hasAssertion {
            IOPMAssertionRelease(assertionID)
            hasAssertion = false
        }
    }

    /// F15（keycode 113）：绝大多数键盘没有此键，按下无可见效果，但会重置系统空闲计时
    static func postPhantomKey() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCode: CGKeyCode = 113
        CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)?
            .post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)?
            .post(tap: .cghidEventTap)
    }

    deinit {
        phantomKeyTimer?.invalidate()
        autoOffTimer?.invalidate()
        releaseAssertion()
    }
}
```

- [ ] **Step 2: 验证编译**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: caffeine controller with basic/enhanced modes"
```

---

### Task 4: AppState（胶水层：计时器、通知、联动、设置持久化）

**Files:**
- Create: `Sources/Caffinate/AppState.swift`

- [ ] **Step 1: 写实现**

```swift
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
```

- [ ] **Step 2: 验证编译**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: app state glue with timer, notifications, caffeine linkage"
```

---

### Task 5: UI（奶油暖调弹窗 + 动态菜单栏）

**Files:**
- Create: `Sources/Caffinate/Theme.swift`
- Create: `Sources/Caffinate/LoginItem.swift`
- Create: `Sources/Caffinate/Views/CaffeineCard.swift`
- Create: `Sources/Caffinate/Views/PomodoroCard.swift`
- Create: `Sources/Caffinate/Views/SettingsView.swift`
- Create: `Sources/Caffinate/Views/PopoverView.swift`
- Modify: `Sources/Caffinate/CaffinateApp.swift`（完整替换）

- [ ] **Step 1: Theme.swift**

```swift
import SwiftUI

enum Theme {
    static let cream = Color(red: 0.99, green: 0.97, blue: 0.93)
    static let card = Color.white
    static let tomato = Color(red: 0.89, green: 0.32, blue: 0.25)
    static let tomatoDark = Color(red: 0.76, green: 0.22, blue: 0.18)
    static let coffee = Color(red: 0.45, green: 0.30, blue: 0.18)
    static let textPrimary = Color(red: 0.24, green: 0.18, blue: 0.14)
    static let textSecondary = Color(red: 0.55, green: 0.48, blue: 0.42)
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.card)
            )
            .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}
```

- [ ] **Step 2: LoginItem.swift（SMAppService 封装，裸二进制守卫）**

```swift
import Foundation
import ServiceManagement

enum LoginItem {
    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    static var isEnabled: Bool {
        guard isAvailable else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func set(enabled: Bool) -> Bool {
        guard isAvailable else { return false }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }
}
```

- [ ] **Step 3: Views/CaffeineCard.swift**

```swift
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
```

- [ ] **Step 4: Views/PomodoroCard.swift**

```swift
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
```

- [ ] **Step 5: Views/SettingsView.swift**

```swift
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
```

- [ ] **Step 6: Views/PopoverView.swift**

```swift
import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var state: AppState
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Caffinate")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Theme.coffee)
                Spacer()
                Button {
                    withAnimation(.snappy) { showSettings.toggle() }
                } label: {
                    Image(systemName: showSettings ? "xmark.circle.fill" : "gearshape.fill")
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            if showSettings {
                SettingsView()
            } else {
                CaffeineCard()
                PomodoroCard()
            }

            HStack {
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(14)
        .frame(width: 280)
        .background(Theme.cream)
    }
}
```

- [ ] **Step 7: 完整替换 CaffinateApp.swift**

```swift
import SwiftUI

@main
struct CaffinateApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(state)
        } label: {
            if let title = state.menuBarTitle {
                Text(title)
            } else {
                Image(systemName: state.caffeine.mode == .off
                      ? "cup.and.saucer" : "cup.and.saucer.fill")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 8: 编译 + 烟雾测试**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

Run: `swift run Caffinate &`，肉眼确认菜单栏出现 ☕ 图标，点开弹窗显示两张卡片；测试完 `kill %1`。
（裸二进制运行时无通知/无登录自启属预期，bundle 守卫生效。）

- [ ] **Step 9: Commit**

```bash
git add -A && git commit -m "feat: cream-themed popover UI with dynamic menu bar"
```

---

### Task 6: 打包脚本 + README

**Files:**
- Create: `scripts/build-app.sh`
- Create: `README.md`

- [ ] **Step 1: scripts/build-app.sh**

```bash
#!/bin/bash
# 构建 Caffinate.app（无需 Xcode，仅需 Command Line Tools）
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=dist/Caffinate.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp .build/release/Caffinate "$APP/Contents/MacOS/Caffinate"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.lijun.caffinate</string>
    <key>CFBundleName</key>
    <string>Caffinate</string>
    <key>CFBundleDisplayName</key>
    <string>Caffinate</string>
    <key>CFBundleExecutable</key>
    <string>Caffinate</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "✅ 已生成 $APP"
echo "   安装：cp -R $APP /Applications/"
```

- [ ] **Step 2: 赋执行权限并运行**

Run: `chmod +x scripts/build-app.sh && ./scripts/build-app.sh`
Expected: `✅ 已生成 dist/Caffinate.app`

Run: `open dist/Caffinate.app`，确认菜单栏出现 ☕（无 Dock 图标），首次弹出通知授权请求。

- [ ] **Step 3: README.md**

```markdown
# Caffinate ☕🍅

轻量 macOS 菜单栏效率小助手：防休眠 + 番茄钟。原生 SwiftUI，零依赖，无需 Xcode。

## 功能

- **咖啡因**：三档防休眠
  - 基础：阻止熄屏/休眠（IOPMAssertion）
  - 增强：基础 + 每 50 秒模拟一次 F15 空键重置系统空闲计时，应对强制 idle 锁屏
- **番茄钟**：25/5 可配置，菜单栏直接显示 `🍅 17:32` 倒计时，结束系统通知 + 提示音
- 专注时自动开启防休眠（可关）；防休眠可设 N 小时自动关闭；登录自启

## 构建 & 安装

仅需 macOS 14+ 与 Command Line Tools（`xcode-select --install`）：

​```bash
./scripts/build-app.sh
cp -R dist/Caffinate.app /Applications/
open /Applications/Caffinate.app
​```

## 增强档授权

增强档需要「辅助功能」权限：系统设置 → 隐私与安全性 → 辅助功能 → 添加 Caffinate。
注意：本应用为 ad-hoc 签名，**每次重新构建后需要重新授权**（先移除旧条目再添加）。

## 开发

​```bash
swift build              # 编译
swift run caffinate-tests  # 跑测试
swift run Caffinate      # 开发模式直接跑（无通知/自启，属预期）
​```

## 验证防休眠生效

​```bash
pmset -g assertions | grep -i caffinate   # 基础档：应出现 assertion
ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print $NF/1000000000; exit}'  # 增强档：空闲秒数应 ≤50
​```
```

（注意：README 中的 ` ​``` ` 转义仅为本计划文档嵌套需要，实际写入时用正常三反引号。）

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: app bundling script and README"
```

---

### Task 7: 端到端手工验证

无新文件。逐项执行并记录结果：

- [ ] **Step 1: 测试套件通过**

Run: `swift run caffinate-tests`
Expected: `全部通过 ✅`

- [ ] **Step 2: 基础档防休眠实测**

打开 App → 咖啡因切到「基础」，然后：

Run: `pmset -g assertions | grep -A1 -i caffinate`
Expected: 出现 `Caffinate 防休眠` 的 `PreventUserIdleDisplaySleep` assertion。
切回「关」，再次运行命令，assertion 消失。

- [ ] **Step 3: 增强档实测（需先授权辅助功能）**

切到「增强」（未授权时应显示引导文案且无法切换）。授权后切换成功，等待 ~60 秒：

Run: `ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print $NF/1000000000; exit}'`
Expected: 不碰键鼠的前提下，该值始终 ≤ 50（被 F15 重置）。

- [ ] **Step 4: 番茄钟全流程**

设置里把专注/休息改为 1 分钟，开始专注：
- 菜单栏变为 `🍅 0:59` 倒计时
- 咖啡因自动跳到「基础」（联动）
- 1 分钟后：通知 + 提示音，进入休息
- 休息结束：通知，回到就绪，咖啡因自动恢复「关」
- 暂停/继续/重置各操作一遍

- [ ] **Step 5: 收尾**

把时长改回 25/5。如有问题修复后：

```bash
git add -A && git commit -m "chore: e2e verification fixes"
```

---

## Self-Review 记录

- 规格覆盖：防休眠三态 ✅(T3) 权限引导 ✅(T5) 自动关闭 ✅(T3/T5) 番茄钟 ✅(T2/T4) 联动 ✅(T4) 通知+声音 ✅(T4) 菜单栏状态 ✅(T5) 奶油 UI ✅(T5) 登录自启 ✅(T5) 打包 ✅(T6) README ✅(T6) 测试与验证 ✅(T2/T7)
- 占位符：无 TBD/TODO（T1 的空壳文件是 TDD 流程的一部分，T2 立即填充）
- 类型一致性：`PomodoroEngine.Phase{idle,focus,rest}`、`CaffeineController.Mode{off,basic,enhanced}`、`AppState` 对外 API（`startFocus/pause/resume/reset/timeText/progress/menuBarTitle`）各任务间已核对一致。
