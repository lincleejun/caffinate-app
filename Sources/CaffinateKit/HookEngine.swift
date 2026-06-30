import Foundation

/// Hook 派发器：把一个 `HookEvent` 翻译成「读 config + 列目录 → 解析 → 派生子进程」。
///
/// 设计要点：
/// - **非阻塞**：`dispatch` 立即返回，所有读盘/派生都在后台队列，绝不卡主线程/状态机。
/// - **fire-and-forget**：脚本输出丢弃、错误只记日志；hook 失败不影响 App。
/// - **并发上限 + 超时**：避免脚本卡死或风暴拖垮系统。
/// - **每次都重读** config 与目录：支持用户实时增删 hook，无需重启。
///
/// 解析逻辑在 `HookResolver`（纯函数，单测覆盖）；这里只负责副作用部分。
public final class HookEngine {
    private let directory: URL
    private let configURL: URL
    private let timeout: TimeInterval
    private let queue = DispatchQueue(label: "ai.caffinate.hooks", attributes: .concurrent)
    private let slots: DispatchSemaphore

    /// - Parameters:
    ///   - directory: hooks 目录（放可执行钩子）。
    ///   - configURL: hooks.json 路径；默认取 directory 同级的 `hooks.json`。
    ///   - maxConcurrent: 同时运行的钩子进程上限。
    ///   - timeout: 单个钩子最长运行秒数，超时强杀。
    public init(
        directory: URL = HookEngine.defaultDirectory,
        configURL: URL? = nil,
        maxConcurrent: Int = 8,
        timeout: TimeInterval = 10
    ) {
        self.directory = directory
        self.configURL = configURL
            ?? directory.deletingLastPathComponent().appendingPathComponent("hooks.json")
        self.timeout = timeout
        self.slots = DispatchSemaphore(value: max(1, maxConcurrent))
    }

    /// 默认 hooks 目录：`~/Library/Application Support/Caffinate/hooks/`
    /// （与 socket / history.csv 同一 Caffinate 目录）。
    public static var defaultDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Caffinate/hooks", isDirectory: true)
    }

    /// hooks.json 路径（供 `caf hooks` 展示）。
    public var configPath: String { configURL.path }
    /// hooks 目录路径（供 `caf hooks` 展示）。
    public var directoryPath: String { directory.path }

    /// 目录里发现的可执行钩子文件名（供 `caf hooks` 展示）。
    public func discoveredExecutables() -> [String] { executableEntries().sorted() }
    /// hooks.json 里的规则（供 `caf hooks` 展示）。
    public func configRules() -> [HookConfig.Rule] { loadConfig()?.hooks ?? [] }

    /// 确保 hooks 目录存在，并放一份说明（首次创建时）。不可执行，不会被运行。
    public func ensureDirectory() {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let readme = directory.appendingPathComponent("README.txt")
        if !fm.fileExists(atPath: readme.path) {
            try? Self.readmeText.write(to: readme, atomically: true, encoding: .utf8)
        }
    }

    /// 派发一个事件：立即返回，后台异步执行所有匹配的钩子。
    public func dispatch(_ event: HookEvent) {
        queue.async { [weak self] in
            guard let self else { return }
            let config = self.loadConfig()
            let entries = self.executableEntries()
            let actions = HookResolver.actions(
                for: event.name, config: config, directoryEntries: entries
            )
            for action in actions {
                self.queue.async {
                    self.slots.wait()
                    defer { self.slots.signal() }
                    self.run(action, event: event)
                }
            }
        }
    }

    // MARK: - 内部

    private func loadConfig() -> HookConfig? {
        guard let data = try? Data(contentsOf: configURL) else { return nil }
        return try? JSONDecoder().decode(HookConfig.self, from: data)
    }

    /// 目录里所有「普通文件 + 有执行位」的条目名。
    private func executableEntries() -> [String] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names.filter { name in
            let p = directory.appendingPathComponent(name).path
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: p, isDirectory: &isDir)
                && !isDir.boolValue && fm.isExecutableFile(atPath: p)
        }
    }

    private func run(_ action: HookAction, event: HookEvent) {
        let process = Process()
        switch action {
        case .shell(let cmd):
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", cmd]
        case .executable(let name):
            process.executableURL = directory.appendingPathComponent(name)
            process.arguments = []
        }
        process.currentDirectoryURL = directory

        var env = ProcessInfo.processInfo.environment
        for (k, v) in event.environment { env[k] = v }
        process.environment = env

        let stdin = Pipe()
        process.standardInput = stdin
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            Self.log("hook 启动失败 [\(event.name)]: \(error.localizedDescription)")
            return
        }

        // 把事件 JSON 写进 stdin 后关闭。write(contentsOf:) 是抛错版，脚本不读 stdin
        // 直接退出导致 EPIPE 时会抛 Swift 错误而非崩溃信号。
        let payload = Data((event.jsonPayload + "\n").utf8)
        try? stdin.fileHandleForWriting.write(contentsOf: payload)
        try? stdin.fileHandleForWriting.close()

        // 超时看门狗：到点仍在跑就强杀。
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        queue.asyncAfter(deadline: .now() + timeout, execute: watchdog)
        process.waitUntilExit()
        watchdog.cancel()
    }

    private static func log(_ message: String) {
        FileHandle.standardError.write(Data(("[caffinate-hooks] " + message + "\n").utf8))
    }

    private static let readmeText = """
    Caffinate hooks
    ===============

    放在这个目录里的「可执行文件」会在对应事件发生时被运行。
    文件名 = 事件名即自动触发；名为 `all` 的文件接收所有事件。

    事件名：
      caffeine.off  caffeine.basic  caffeine.enhanced
      pomodoro.focus.start  pomodoro.focus.end  pomodoro.focus.interrupted
      pomodoro.rest.start   pomodoro.rest.end
      pomodoro.pause        pomodoro.resume

    载荷：每个字段是 CAFFINATE_<KEY> 环境变量，同时完整事件以 JSON 从 stdin 传入。
      常见变量：CAFFINATE_EVENT, CAFFINATE_MODE, CAFFINATE_PREV_MODE,
                CAFFINATE_PHASE, CAFFINATE_REMAINING_SEC, CAFFINATE_SOURCE, CAFFINATE_TS

    例：进入专注时开系统 Focus（需先在「快捷指令」建好同名指令）
      1) 新建文件 pomodoro.focus.start
      2) 内容：
           #!/bin/bash
           shortcuts run "Focus On"
      3) chmod +x pomodoro.focus.start

    或用声明式配置 ../hooks.json：
      { "hooks": [
          { "on": "pomodoro.focus.start", "run": "shortcuts run 'Focus On'" },
          { "on": "pomodoro.focus.end",   "run": "shortcuts run 'Focus Off'" },
          { "on": "caffeine.*",           "run": "logger -t caffinate $CAFFINATE_EVENT" }
        ] }

    查看已发现的钩子： caf hooks
    """
}
