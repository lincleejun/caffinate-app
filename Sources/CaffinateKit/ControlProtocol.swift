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
    public var accessibilityTrusted: Bool

    public init(caffeineMode: String, phase: String, remainingSeconds: Int,
                isPaused: Bool, focusMinutes: Int, restMinutes: Int,
                autoCaffeinate: Bool, autoOffHours: Double, accessibilityTrusted: Bool) {
        self.caffeineMode = caffeineMode
        self.phase = phase
        self.remainingSeconds = remainingSeconds
        self.isPaused = isPaused
        self.focusMinutes = focusMinutes
        self.restMinutes = restMinutes
        self.autoCaffeinate = autoCaffeinate
        self.autoOffHours = autoOffHours
        self.accessibilityTrusted = accessibilityTrusted
    }
}

public struct ControlResponse: Codable, Equatable {
    public var ok: Bool
    public var message: String?
    public var error: String?
    public var state: ControlState?

    public init(ok: Bool, message: String? = nil, error: String? = nil, state: ControlState? = nil) {
        self.ok = ok
        self.message = message
        self.error = error
        self.state = state
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
    caf — Caffinate 命令行遥控器

    用法：
      caf                     状态总览
      caf json                状态（JSON，脚本用）
      caf on                  咖啡因 → 基础（防熄屏/休眠）
      caf on max              咖啡因 → 增强（+空闲重置，需辅助功能权限）
      caf off                 咖啡因 → 关
      caf pomo                开始专注
      caf pause               暂停⇄继续
      caf reset               重置番茄钟
      caf set focus <1-120>   专注分钟数
      caf set rest <1-60>     休息分钟数
      caf set auto-caf on|off 专注时自动防休眠
      caf set auto-off <0|1|2|4|8>  防休眠 N 小时自动关（0=从不）
      caf help                本说明
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
            case let other?: return .failure("未知档位「\(other)」，可用：caf on / caf on max")
            }
        case "off":
            return .run(.init(request: .init(command: "caffeine", args: ["off"])))
        case "pomo":
            return .run(.init(request: .init(command: "pomo-start")))
        case "pause":
            return .run(.init(request: .init(command: "pomo-pause")))
        case "reset":
            return .run(.init(request: .init(command: "pomo-reset")))
        case "set":
            return parseSet(Array(argv.dropFirst()))
        case let other?:
            return .failure("未知命令「\(other)」")
        }
    }

    private static func parseSet(_ args: [String]) -> Result {
        guard args.count == 2 else {
            return .failure("set 用法：caf set <focus|rest|auto-caf|auto-off> <值>")
        }
        let (key, value) = (args[0], args[1])
        switch key {
        case "focus":
            guard let v = Int(value), (1...120).contains(v) else {
                return .failure("focus 取值 1-120 分钟")
            }
            return .run(.init(request: .init(command: "set", args: ["focus", String(v)])))
        case "rest":
            guard let v = Int(value), (1...60).contains(v) else {
                return .failure("rest 取值 1-60 分钟")
            }
            return .run(.init(request: .init(command: "set", args: ["rest", String(v)])))
        case "auto-caf":
            guard value == "on" || value == "off" else {
                return .failure("auto-caf 取值 on|off")
            }
            return .run(.init(request: .init(command: "set", args: ["auto-caf", value])))
        case "auto-off":
            guard ["0", "1", "2", "4", "8"].contains(value) else {
                return .failure("auto-off 取值 0|1|2|4|8 小时（0=从不）")
            }
            return .run(.init(request: .init(command: "set", args: ["auto-off", value])))
        default:
            return .failure("未知设置项「\(key)」")
        }
    }
}
