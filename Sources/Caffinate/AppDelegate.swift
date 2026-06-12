import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 稍等 MenuBarExtra 完成挂载后自动展开面板，让"打开应用就能看到 UI"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            Self.openMenuBarPanel()
        }
    }

    /// 应用已在运行时再次被打开（Finder 双击 / 启动台）会走到这里
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        Self.openMenuBarPanel()
        return false
    }

    /// MenuBarExtra 没有公开的编程展开 API，通过状态栏按钮模拟一次点击
    static func openMenuBarPanel() {
        for window in NSApp.windows where window.className.contains("StatusBarWindow") {
            guard let item = window.value(forKey: "statusItem") as? NSStatusItem,
                  let button = item.button else { continue }
            button.performClick(nil)
            return
        }
    }
}
