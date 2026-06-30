import Foundation

/// CLI ↔ App 的控制协议。单行 JSON 请求 / 单行 JSON 响应。
public struct ControlRequest: Codable, Equatable {
    public var command: String
    public var args: [String]

    public init(command: String, args: [String] = []) {
        self.command = command
        self.args = args
    }
}

public struct ControlState: Codable, Equatable {
    public var caffeineMode: String   // off | basic | enhanced
    public var phase: String          // idle | focus | rest
    public var remainingSeconds: Int
    public var isPaused: Bool
    public var focusMinutes: Int
    public var restMinutes: Int
    public var autoCaffeinate: Bool
    public var autoOffHours: Double
    public var linkSystemFocus: Bool  // 专注时联动系统 Focus（静音通知）
    public var accessibilityTrusted: Bool

    public init(caffeineMode: String, phase: String, remainingSeconds: Int,
                isPaused: Bool, focusMinutes: Int, restMinutes: Int,
                autoCaffeinate: Bool, autoOffHours: Double,
                linkSystemFocus: Bool, accessibilityTrusted: Bool) {
        self.caffeineMode = caffeineMode
        self.phase = phase
        self.remainingSeconds = remainingSeconds
        self.isPaused = isPaused
        self.focusMinutes = focusMinutes
        self.restMinutes = restMinutes
        self.autoCaffeinate = autoCaffeinate
        self.autoOffHours = autoOffHours
        self.linkSystemFocus = linkSystemFocus
        self.accessibilityTrusted = accessibilityTrusted
    }
}

/// `caf doctor` 健康自检：一眼看清谁在挡/放休眠 + 权限/配置状态。
public struct Diagnostics: Codable, Equatable {
    public var caffeineMode: String
    public var holdsAssertion: Bool        // 是否真正持有防休眠断言
    public var accessibilityTrusted: Bool  // 增强档所需
    public var linkSystemFocus: Bool
    public var focusShortcutsInstalled: Bool  // On/Off 两个快捷指令都在
    public var focusRestoreReady: Bool        // Status 快捷指令在 → 退出时精确还原
    public var historyPath: String
    public var historyWritable: Bool

    public init(caffeineMode: String, holdsAssertion: Bool, accessibilityTrusted: Bool,
                linkSystemFocus: Bool, focusShortcutsInstalled: Bool,
                focusRestoreReady: Bool = false,
                historyPath: String, historyWritable: Bool) {
        self.caffeineMode = caffeineMode
        self.holdsAssertion = holdsAssertion
        self.accessibilityTrusted = accessibilityTrusted
        self.linkSystemFocus = linkSystemFocus
        self.focusShortcutsInstalled = focusShortcutsInstalled
        self.focusRestoreReady = focusRestoreReady
        self.historyPath = historyPath
        self.historyWritable = historyWritable
    }
}

/// `caf hooks`：已配置的事件钩子清单（目录自动发现 + hooks.json）。
public struct HookInventory: Codable, Equatable {
    public struct Rule: Codable, Equatable {
        public var on: String
        public var run: String
        public init(on: String, run: String) { self.on = on; self.run = run }
    }
    public var directory: String      // hooks 目录
    public var configPath: String     // hooks.json 路径
    public var executables: [String]  // 目录里发现的可执行钩子文件名
    public var rules: [Rule]          // hooks.json 里的规则

    public init(directory: String, configPath: String, executables: [String], rules: [Rule]) {
        self.directory = directory
        self.configPath = configPath
        self.executables = executables
        self.rules = rules
    }
}

public struct ControlResponse: Codable, Equatable {
    public var ok: Bool
    public var message: String?
    public var error: String?
    public var state: ControlState?
    public var history: [HistoryRecord]?
    public var diagnostics: Diagnostics?
    public var hooks: HookInventory?

    public init(ok: Bool, message: String? = nil, error: String? = nil,
                state: ControlState? = nil, history: [HistoryRecord]? = nil,
                diagnostics: Diagnostics? = nil, hooks: HookInventory? = nil) {
        self.ok = ok
        self.message = message
        self.error = error
        self.state = state
        self.history = history
        self.diagnostics = diagnostics
        self.hooks = hooks
    }
}

/// socket 路径（CLI 与 App 共用）
public enum ControlSocket {
    public static var path: String {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Caffinate", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("caf.sock").path
    }
}

/// argv → 请求。校验在客户端先做一遍（服务端是权威，会再校验）。
public enum CLIParse {
    public struct ParsedCommand: Equatable {
        public let request: ControlRequest
        public let rawOutput: Bool

        public init(request: ControlRequest, rawOutput: Bool = false) {
            self.request = request
            self.rawOutput = rawOutput
        }
    }

    public enum Result: Equatable {
        case run(ParsedCommand)
        case help
        case failure(String)
    }

    public static let usage = """
    caf — Caffinate command-line remote

    Usage:
      caf                     Status overview
      caf json                Status (JSON, for scripts)
      caf on                  Caffeine → Basic (block display/system sleep)
      caf on max              Caffeine → Enhanced (+idle reset, needs Accessibility)
      caf off                 Caffeine → Off
      caf pomo                Start focus
      caf pause               Pause ⇄ resume
      caf reset               Reset pomodoro
      caf set focus <1-120>   Focus minutes
      caf set rest <1-60>     Break minutes
      caf set auto-caf on|off Auto keep-awake while focusing
      caf set auto-off <0|1|2|4|8>  Auto-disable keep-awake after N hours (0=never)
      caf set focus-link on|off Link system Focus while focusing (mute notifications, needs Shortcuts)
      caf history [n]         Run history (default last 20)
      caf doctor              Health check (assertion/permission/shortcuts/history)
      caf hooks               List event hooks (dir + hooks.json) and their paths
      caf help                This help
    """

    public static func parse(_ argv: [String]) -> Result {
        switch argv.first {
        case nil:
            return .run(.init(request: .init(command: "status")))
        case "json":
            return .run(.init(request: .init(command: "status"), rawOutput: true))
        case "help", "-h", "--help":
            return .help
        case "on":
            switch argv.dropFirst().first {
            case nil: return .run(.init(request: .init(command: "caffeine", args: ["basic"])))
            case "max": return .run(.init(request: .init(command: "caffeine", args: ["enhanced"])))
            case let other?: return .failure("Unknown mode “\(other)”. Use: caf on / caf on max")
            }
        case "off":
            return .run(.init(request: .init(command: "caffeine", args: ["off"])))
        case "doctor":
            return .run(.init(request: .init(command: "doctor")))
        case "hooks":
            return .run(.init(request: .init(command: "hooks")))
        case "history":
            switch argv.dropFirst().first {
            case nil:
                return .run(.init(request: .init(command: "history")))
            case let arg?:
                guard let n = Int(arg), n > 0 else { return .failure("history count must be a positive integer") }
                return .run(.init(request: .init(command: "history", args: [String(n)])))
            }
        case "pomo":
            return .run(.init(request: .init(command: "pomo-start")))
        case "pause":
            return .run(.init(request: .init(command: "pomo-pause")))
        case "reset":
            return .run(.init(request: .init(command: "pomo-reset")))
        case "set":
            return parseSet(Array(argv.dropFirst()))
        case let other?:
            return .failure("Unknown command “\(other)”")
        }
    }

    private static func parseSet(_ args: [String]) -> Result {
        guard args.count == 2 else {
            return .failure("Usage: caf set <focus|rest|auto-caf|auto-off> <value>")
        }
        let (key, value) = (args[0], args[1])
        switch key {
        case "focus":
            guard let v = Int(value), (1...120).contains(v) else {
                return .failure("focus must be 1-120 min")
            }
            return .run(.init(request: .init(command: "set", args: ["focus", String(v)])))
        case "rest":
            guard let v = Int(value), (1...60).contains(v) else {
                return .failure("rest must be 1-60 min")
            }
            return .run(.init(request: .init(command: "set", args: ["rest", String(v)])))
        case "auto-caf":
            guard value == "on" || value == "off" else {
                return .failure("auto-caf must be on|off")
            }
            return .run(.init(request: .init(command: "set", args: ["auto-caf", value])))
        case "auto-off":
            guard ["0", "1", "2", "4", "8"].contains(value) else {
                return .failure("auto-off must be 0|1|2|4|8 hours (0=never)")
            }
            return .run(.init(request: .init(command: "set", args: ["auto-off", value])))
        case "focus-link":
            guard value == "on" || value == "off" else {
                return .failure("focus-link must be on|off")
            }
            return .run(.init(request: .init(command: "set", args: ["focus-link", value])))
        default:
            return .failure("Unknown setting “\(key)”")
        }
    }
}
