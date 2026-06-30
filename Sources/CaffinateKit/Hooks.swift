import Foundation

/// 一个 hook 事件：事件名 + 扁平字段载荷。
///
/// 字段会被注入子进程：每个字段变成 `CAFFINATE_<KEY>` 环境变量，同时整体
/// 以 JSON 从 stdin 传给脚本（同 Claude Code hooks 的风格）。
public struct HookEvent: Equatable {
    /// 形如 `pomodoro.focus.start` / `caffeine.enhanced`。
    public let name: String
    /// 载荷字段（如 mode、prev_mode、phase、remaining_sec、source）。
    /// 用有序数组而非字典，保证 env / JSON 输出稳定、可测。
    public let fields: [(key: String, value: String)]

    public init(name: String, fields: [(key: String, value: String)] = []) {
        self.name = name
        self.fields = fields
    }

    public static func == (lhs: HookEvent, rhs: HookEvent) -> Bool {
        lhs.name == rhs.name && lhs.fields.map(\.key) == rhs.fields.map(\.key)
            && lhs.fields.map(\.value) == rhs.fields.map(\.value)
    }

    /// 注入子进程的环境变量：`CAFFINATE_EVENT` + 每个字段 `CAFFINATE_<UPPER_KEY>`。
    public var environment: [String: String] {
        var env = ["CAFFINATE_EVENT": name]
        for f in fields {
            env["CAFFINATE_" + f.key.uppercased()] = f.value
        }
        return env
    }

    /// 从 stdin 传给脚本的 JSON：`{"event":"…","<key>":"<value>",…}`。
    /// 手写编码（字段值转义），避免引入 Codable 顺序不确定性，便于测试。
    public var jsonPayload: String {
        var parts = ["\"event\":\(Self.encode(name))"]
        for f in fields {
            parts.append("\(Self.encode(f.key)):\(Self.encode(f.value))")
        }
        return "{" + parts.joined(separator: ",") + "}"
    }

    private static func encode(_ s: String) -> String {
        var out = "\""
        for c in s {
            switch c {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.append(c)
            }
        }
        return out + "\""
    }
}

/// `hooks.json` 配置：声明式「事件 glob → shell 命令」。
public struct HookConfig: Codable, Equatable {
    public struct Rule: Codable, Equatable {
        /// 事件匹配：精确名、`prefix.*` 前缀通配、或 `*` 全匹配。
        public let on: String
        /// 用 `/bin/sh -c` 执行的 shell 命令。
        public let run: String
        public init(on: String, run: String) {
            self.on = on
            self.run = run
        }
    }
    public let hooks: [Rule]
    public init(hooks: [Rule]) { self.hooks = hooks }
}

/// 解析出的一个待执行动作。
public enum HookAction: Equatable {
    /// config 里的 shell 命令，经 `/bin/sh -c` 执行。
    case shell(String)
    /// hooks 目录里的可执行文件名（调用方拼成完整路径后直接 exec）。
    case executable(String)
}

/// 纯解析逻辑：给定事件名 + config + hooks 目录条目，算出该执行哪些动作。
/// 无任何副作用（不读盘、不派生进程），便于单测。
public enum HookResolver {
    public static func actions(
        for eventName: String,
        config: HookConfig?,
        directoryEntries: [String]
    ) -> [HookAction] {
        var out: [HookAction] = []
        // 1) 目录自动发现：文件名 == 事件名，或名为 `all`（收所有事件）。
        for entry in directoryEntries.sorted() where entry == eventName || entry == "all" {
            out.append(.executable(entry))
        }
        // 2) config 规则，按文件中出现顺序。
        for rule in config?.hooks ?? [] where matches(pattern: rule.on, name: eventName) {
            out.append(.shell(rule.run))
        }
        return out
    }

    /// 事件名匹配：`*` 全匹配；`X.*` 匹配 `X` 或以 `X.` 开头；否则精确相等。
    public static func matches(pattern: String, name: String) -> Bool {
        if pattern == "*" { return true }
        if pattern.hasSuffix(".*") {
            let base = String(pattern.dropLast(2))
            return name == base || name.hasPrefix(base + ".")
        }
        return pattern == name
    }
}
