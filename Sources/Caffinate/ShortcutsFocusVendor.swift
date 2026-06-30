import Foundation
import CaffinateKit

/// 用 macOS「快捷指令」切换系统 Focus，并在退出时**精确还原**到进入前的状态。
///
/// 约定用户在「快捷指令」App 里建立快捷指令（具体联动哪个 Focus 由用户自己选）：
///   - "Caffinate Focus On"  → 开启所选 Focus（直到关闭）
///   - "Caffinate Focus Off" → 关闭 Focus
///   - "Caffinate Focus Status"（可选，开启还原能力）→ 一个 `Get Current Focus`
///     动作，输出当前 Focus 名（没开则输出空）。
///
/// 还原逻辑（见 `FocusRestorePolicy`）：进入专注前先读当前 Focus——
///   - 你本来没开 → 专注期间开我们的，退出时关回「没开」；
///   - 你本来开着某个 Focus → 全程不碰它（macOS 不能按名字开任意 Focus，
///     所以「不覆盖」才是能精确保住你状态的做法）；
///   - 没建 Status 快捷指令、读不到 → 回退老行为（无脑开/关）。
///
/// `shortcuts run` 在后台串行队列执行，绝不阻塞主线程；`weActivated` 也只在该
/// 队列上读写，天然无竞争。用户没建快捷指令时静默失败，不崩、不打扰。
final class ShortcutsFocusVendor: FocusVendor {
    static let onShortcut = "Caffinate Focus On"
    static let offShortcut = "Caffinate Focus Off"
    static let statusShortcut = "Caffinate Focus Status"

    private let queue = DispatchQueue(label: "caffinate.focus.shortcuts", qos: .utility)
    /// 本轮专注是否由「我们」开启了 Focus（决定退出时是否关）。仅在 queue 上访问。
    private var weActivated = false

    func activate() {
        queue.async {
            let prior = Self.readCurrentFocus()
            let shouldOpen = FocusRestorePolicy.shouldActivateOurFocus(prior: prior)
            self.weActivated = shouldOpen
            if shouldOpen {
                Self.runShortcut(Self.onShortcut)
            }
            // prior == .active：什么都不做，保住你原来的 Focus。
        }
    }

    func deactivate(then: (() -> Void)?) {
        queue.async {
            let shouldClose = FocusRestorePolicy.shouldDeactivate(weActivated: self.weActivated)
            self.weActivated = false
            if shouldClose {
                Self.runShortcut(Self.offShortcut)
            }
            // Focus 已还原，回主线程跑回调（如「先关再发通知」）。
            if let then { DispatchQueue.main.async { then() } }
        }
    }

    /// 读取当前系统 Focus（同步，仅在 vendor 队列上调用）。
    /// 用 "Caffinate Focus Status" 快捷指令的输出判断：缺指令/失败 → unavailable；
    /// 输出空 → none；非空 → active(名字)。
    static func readCurrentFocus() -> FocusQuery {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("caffinate-focus-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        proc.arguments = ["run", statusShortcut,
                          "--output-path", tmp.path,
                          "--output-type", "public.plain-text"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return .unavailable }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return .unavailable }  // 没建该快捷指令

        let raw = (try? String(contentsOf: tmp, encoding: .utf8)) ?? ""
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? .none : .active(name)
    }

    /// 两个切换快捷指令是否都已建好（供 `caf doctor`）。
    static func installed() -> Bool {
        let names = listShortcuts()
        return names.contains(onShortcut) && names.contains(offShortcut)
    }

    /// 还原能力是否就绪：Status 快捷指令已建（否则退化为无脑开/关）。
    static func restoreReady() -> Bool {
        listShortcuts().contains(statusShortcut)
    }

    /// `shortcuts list` 的全部名字（同步）。
    private static func listShortcuts() -> [String] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        proc.arguments = ["list"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return [] }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n").map { String($0) }
    }

    /// 同步跑一个快捷指令（仅在 vendor 队列上调用）。
    private static func runShortcut(_ shortcut: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        proc.arguments = ["run", shortcut]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
    }
}
