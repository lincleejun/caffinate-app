import Foundation
import CaffinateKit

/// 用 macOS「快捷指令」切换系统 Focus。
///
/// 约定用户在「快捷指令」App 里建立两个快捷指令（各放一个 `Set Focus` 动作，
/// 具体联动哪个 Focus/勿扰由用户自己选）：
///   - "Caffinate Focus On"  → 开启所选 Focus（直到关闭）
///   - "Caffinate Focus Off" → 关闭 Focus
///
/// `shortcuts run` 在后台队列执行，绝不阻塞主线程；用户没建快捷指令时静默失败，
/// 不崩、不打扰。
final class ShortcutsFocusVendor: FocusVendor {
    static let onShortcut = "Caffinate Focus On"
    static let offShortcut = "Caffinate Focus Off"

    private let queue = DispatchQueue(label: "caffinate.focus.shortcuts", qos: .utility)

    func activate() { run(Self.onShortcut, then: nil) }
    func deactivate(then: (() -> Void)?) { run(Self.offShortcut, then: then) }

    private func run(_ shortcut: String, then: (() -> Void)?) {
        queue.async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            proc.arguments = ["run", shortcut]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
            proc.waitUntilExit()
            // Focus 切换已结束，回到主线程跑回调（如「先关再发通知」）。
            if let then { DispatchQueue.main.async { then() } }
        }
    }
}
