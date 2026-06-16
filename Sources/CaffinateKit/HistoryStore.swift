import Foundation

/// 一条运行历史。type: caffeine | focus | rest；detail: basic/enhanced 或 completed/interrupted。
public struct HistoryRecord: Codable, Equatable {
    public let type: String
    public let start: Date
    public let end: Date
    public let detail: String

    public init(type: String, start: Date, end: Date, detail: String) {
        self.type = type
        self.start = start
        self.end = end
        self.detail = detail
    }

    public var durationSec: Int { max(0, Int(end.timeIntervalSince(start))) }

    /// 单行展示（menubar 与 CLI 共用）。
    public var display: String {
        switch type {
        case "caffeine":
            let mode = detail == "enhanced" ? "增强" : "基础"
            return "☕ \(mode) · \(Self.hm(start))–\(Self.hm(end)) · \(Self.dur(durationSec))"
        case "focus":
            return "🍅 专注 · \(Self.dur(durationSec)) \(detail == "completed" ? "✓" : "✗")"
        case "rest":
            return "🍵 休息 · \(Self.dur(durationSec)) \(detail == "completed" ? "✓" : "✗")"
        default:
            return "\(type) · \(Self.dur(durationSec))"
        }
    }

    private static let hmFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"; return f
    }()
    static func hm(_ d: Date) -> String { hmFormatter.string(from: d) }

    static func dur(_ sec: Int) -> String {
        if sec < 60 { return "\(sec)s" }
        let m = sec / 60
        if m < 60 { return "\(m)m" }
        return "\(m / 60)h\(m % 60)m"
    }
}

/// 历史的落盘/读取后端。抽象出来便于测试（内存 sink）与替换。
public protocol HistorySink: AnyObject {
    func append(_ record: HistoryRecord)
    /// 最近 n 条，**最新在前**。
    func recent(_ n: Int) -> [HistoryRecord]
}

/// 把状态变化翻译成历史记录。持有"未结束的段"的开始时间。纯逻辑 + 注入时钟，可单测。
public final class HistoryTracker {
    private let sink: HistorySink
    private var caffeineOpen: (start: Date, mode: String)?
    private var pomodoroOpen: (start: Date, type: String)?

    public init(sink: HistorySink) { self.sink = sink }

    /// 咖啡因档位变化（off 用 "off"）。换档自动分段：关掉旧段、按需开新段。
    public func caffeine(changedTo mode: String, at now: Date) {
        if let open = caffeineOpen, open.mode != mode {
            sink.append(HistoryRecord(type: "caffeine", start: open.start, end: now, detail: open.mode))
            caffeineOpen = nil
        }
        if mode != "off", caffeineOpen == nil {
            caffeineOpen = (now, mode)
        }
    }

    public func pomodoroBegan(_ type: String, at now: Date) {
        pomodoroOpen = (now, type)
    }

    public func pomodoroEnded(completed: Bool, at now: Date) {
        guard let open = pomodoroOpen else { return }
        sink.append(HistoryRecord(type: open.type, start: open.start, end: now,
                                  detail: completed ? "completed" : "interrupted"))
        pomodoroOpen = nil
    }

    /// App 退出收尾：关掉未结束的咖啡因段（番茄钟未完成则丢弃，不记半截）。
    public func flush(at now: Date) {
        if let open = caffeineOpen {
            sink.append(HistoryRecord(type: "caffeine", start: open.start, end: now, detail: open.mode))
            caffeineOpen = nil
        }
        pomodoroOpen = nil
    }
}

/// CSV 落盘实现。唯一读写者在 App 侧，无文件竞争。表头 + 一行一记录，字段无逗号免转义。
public final class CSVHistorySink: HistorySink {
    private let url: URL
    private static let header = "type,start,end,duration_sec,detail"

    /// 默认落盘位置：Application Support/Caffinate/history.csv（与 socket 同目录）。
    public static var defaultURL: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Caffinate", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.csv")
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; return f
    }()

    public init(url: URL) {
        self.url = url
        if !FileManager.default.fileExists(atPath: url.path) {
            try? (Self.header + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    public func append(_ r: HistoryRecord) {
        let line = "\(r.type),\(Self.stamp.string(from: r.start)),\(Self.stamp.string(from: r.end)),\(r.durationSec),\(r.detail)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    public func recent(_ n: Int) -> [HistoryRecord] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let rows = text.split(separator: "\n").dropFirst()  // 跳过表头
            .compactMap { Self.parse(String($0)) }
        return Array(rows.suffix(n).reversed())  // 最新在前
    }

    private static func parse(_ line: String) -> HistoryRecord? {
        let f = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard f.count == 5,
              let start = stamp.date(from: f[1]),
              let end = stamp.date(from: f[2]) else { return nil }
        return HistoryRecord(type: f[0], start: start, end: end, detail: f[4])
    }
}
