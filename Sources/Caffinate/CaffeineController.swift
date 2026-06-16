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

    /// 当前是否真正持有防休眠断言（供诊断用）。
    var holdsAssertion: Bool { hasAssertion }

    private var assertionID: IOPMAssertionID = 0
    private var hasAssertion = false
    private var phantomKeyTimer: Timer?
    private var autoOffTimer: Timer?

    init() {
        // 系统唤醒后重申断言，避免休眠期间被回收导致「看似开着其实没挡」
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification, object: nil)
    }

    static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    static func openAccessibilitySettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    func set(_ newMode: Mode) {
        lastError = nil
        if newMode == .enhanced && !Self.accessibilityTrusted {
            // 弹系统授权请求：会把当前二进制登记到辅助功能列表
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            lastError = "增强档需要「辅助功能」权限，已弹出系统授权请求"
            return
        }

        if newMode == .off {
            releaseAssertion()
        } else if !ensureAssertion() {
            mode = .off
            return
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

    /// 创建防休眠断言（已持有则直接成功）。失败置 lastError。
    @discardableResult
    private func ensureAssertion() -> Bool {
        guard !hasAssertion else { return true }
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Caffinate 防休眠" as CFString,
            &id
        )
        guard result == kIOReturnSuccess else {
            lastError = "防休眠开启失败 (IOKit \(result))"
            return false
        }
        assertionID = id
        hasAssertion = true
        return true
    }

    /// 唤醒后重申：先释放再重建，确保断言在新会话中真正生效。
    @objc private func systemDidWake() {
        guard mode != .off else { return }
        releaseAssertion()
        if !ensureAssertion() { mode = .off }
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
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        phantomKeyTimer?.invalidate()
        autoOffTimer?.invalidate()
        releaseAssertion()
    }
}
