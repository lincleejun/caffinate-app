import Foundation
import CaffinateKit

var failures = 0
func expect(_ condition: Bool, _ label: String, line: Int = #line) {
    if condition { print("  ok - \(label)") }
    else { failures += 1; print("FAIL - \(label) (line \(line))") }
}

/// 记录调用次序的假 vendor，模拟系统 Focus 切换同步完成。
final class FakeFocusVendor: FocusVendor {
    var activations = 0
    var deactivations = 0
    var events: [String] = []
    func activate() { activations += 1; events.append("on") }
    func deactivate(then: (() -> Void)?) {
        deactivations += 1
        events.append("off")   // 系统 Focus 已关
        then?()                // 关闭完成后才跑回调
    }
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

// ===== ControlProtocol =====

// 8. 编解码 round-trip
do {
    let req = ControlRequest(command: "set", args: ["focus", "30"])
    let data = try! JSONEncoder().encode(req)
    let back = try! JSONDecoder().decode(ControlRequest.self, from: data)
    expect(back == req, "ControlRequest 编解码 round-trip")

    let resp = ControlResponse(
        ok: true, message: "m", error: nil,
        state: ControlState(
            caffeineMode: "basic", phase: "focus", remainingSeconds: 90,
            isPaused: false, focusMinutes: 25, restMinutes: 5,
            autoCaffeinate: true, autoOffHours: 0,
            linkSystemFocus: false, accessibilityTrusted: false))
    let rdata = try! JSONEncoder().encode(resp)
    let rback = try! JSONDecoder().decode(ControlResponse.self, from: rdata)
    expect(rback == resp, "ControlResponse 编解码 round-trip")
}

// 9. argv 解析：合法命令
do {
    func req(_ argv: [String]) -> ControlRequest? {
        if case .run(let p) = CLIParse.parse(argv) { return p.request }
        return nil
    }
    expect(req([]) == ControlRequest(command: "status"), "caf → status")
    expect(req(["on"]) == ControlRequest(command: "caffeine", args: ["basic"]), "caf on → basic")
    expect(req(["on", "max"]) == ControlRequest(command: "caffeine", args: ["enhanced"]), "caf on max → enhanced")
    expect(req(["off"]) == ControlRequest(command: "caffeine", args: ["off"]), "caf off → off")
    expect(req(["pomo"]) == ControlRequest(command: "pomo-start"), "caf pomo")
    expect(req(["pause"]) == ControlRequest(command: "pomo-pause"), "caf pause")
    expect(req(["reset"]) == ControlRequest(command: "pomo-reset"), "caf reset")
    expect(req(["set", "focus", "30"]) == ControlRequest(command: "set", args: ["focus", "30"]), "caf set focus 30")
    expect(req(["set", "auto-caf", "off"]) == ControlRequest(command: "set", args: ["auto-caf", "off"]), "caf set auto-caf off")
    if case .run(let p) = CLIParse.parse(["json"]) {
        expect(p.request == ControlRequest(command: "status") && p.rawOutput, "caf json → status + raw")
    } else { expect(false, "caf json 应可解析") }
}

// 10. argv 解析：help 与错误
do {
    func isHelp(_ argv: [String]) -> Bool {
        if case .help = CLIParse.parse(argv) { return true }
        return false
    }
    func isFailure(_ argv: [String]) -> Bool {
        if case .failure = CLIParse.parse(argv) { return true }
        return false
    }
    expect(isHelp(["help"]) && isHelp(["-h"]) && isHelp(["--help"]), "help 三种写法")
    expect(isFailure(["frobnicate"]), "未知命令 → failure")
    expect(isFailure(["on", "ultra"]), "on 未知档位 → failure")
    expect(isFailure(["set", "focus", "0"]), "focus 越界(0) → failure")
    expect(isFailure(["set", "focus", "121"]), "focus 越界(121) → failure")
    expect(isFailure(["set", "rest", "61"]), "rest 越界 → failure")
    expect(isFailure(["set", "auto-off", "3"]), "auto-off 非枚举值 → failure")
    expect(isFailure(["set", "auto-caf", "maybe"]), "auto-caf 非 on/off → failure")
    expect(isFailure(["set", "focus"]), "set 缺参数 → failure")
    // focus-link 开关解析
    if case .run(let p) = CLIParse.parse(["set", "focus-link", "on"]) {
        expect(p.request == ControlRequest(command: "set", args: ["focus-link", "on"]),
               "caf set focus-link on")
    } else { expect(false, "caf set focus-link on 应可解析") }
    expect(isFailure(["set", "focus-link", "maybe"]), "focus-link 非 on/off → failure")
    // history 解析：默认与带条数
    if case .run(let p) = CLIParse.parse(["history"]) {
        expect(p.request == ControlRequest(command: "history", args: []), "caf history → history")
    } else { expect(false, "caf history 应可解析") }
    if case .run(let p) = CLIParse.parse(["history", "5"]) {
        expect(p.request == ControlRequest(command: "history", args: ["5"]), "caf history 5")
    } else { expect(false, "caf history 5 应可解析") }
    expect(isFailure(["history", "0"]), "history 0 → failure")
    expect(isFailure(["history", "abc"]), "history 非数字 → failure")
    // doctor 解析
    if case .run(let p) = CLIParse.parse(["doctor"]) {
        expect(p.request == ControlRequest(command: "doctor"), "caf doctor → doctor")
    } else { expect(false, "caf doctor 应可解析") }
}

// 10b. Diagnostics 编解码 round-trip
do {
    let d = Diagnostics(caffeineMode: "enhanced", holdsAssertion: true, accessibilityTrusted: true,
                        linkSystemFocus: true, focusShortcutsInstalled: false,
                        historyPath: "/tmp/x.csv", historyWritable: true)
    let resp = ControlResponse(ok: true, diagnostics: d)
    let back = try! JSONDecoder().decode(ControlResponse.self, from: JSONEncoder().encode(resp))
    expect(back == resp && back.diagnostics == d, "Diagnostics/ControlResponse 编解码 round-trip")
}

// 11. FocusLinker：幂等 + 「先关 Focus 再回调」次序
do {
    let v = FakeFocusVendor()
    let linker = FocusLinker(vendor: v)

    linker.engage()
    expect(v.activations == 1 && linker.isActive, "engage 开启一次")
    linker.engage()
    expect(v.activations == 1, "重复 engage 幂等（不重复开）")

    v.events.removeAll()
    linker.disengage(then: { v.events.append("notify") })
    expect(v.deactivations == 1 && !linker.isActive, "disengage 关闭一次")
    expect(v.events == ["off", "notify"], "先关系统 Focus，再跑回调（发通知）")

    var ran = false
    linker.disengage(then: { ran = true })
    expect(v.deactivations == 1 && ran, "未开启时 disengage 不调 vendor，但回调仍执行")

    linker.engage()
    expect(v.activations == 2 && linker.isActive, "可再次 engage")
}

// 12. HistoryTracker：换档分段 / off 收尾 / 完成与中断 / flush
do {
    final class MemSink: HistorySink {
        var records: [HistoryRecord] = []
        func append(_ r: HistoryRecord) { records.append(r) }
        func recent(_ n: Int) -> [HistoryRecord] { Array(records.suffix(n).reversed()) }
    }
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    func at(_ s: Int) -> Date { t0.addingTimeInterval(TimeInterval(s)) }

    let sink = MemSink()
    let tr = HistoryTracker(sink: sink)

    // off→basic→enhanced→off：应得两条 caffeine（basic 段、enhanced 段）
    tr.caffeine(changedTo: "off", at: at(0))      // 无开段，不记
    tr.caffeine(changedTo: "basic", at: at(10))   // 开 basic
    tr.caffeine(changedTo: "enhanced", at: at(70))// 关 basic(60s)、开 enhanced
    tr.caffeine(changedTo: "off", at: at(190))    // 关 enhanced(120s)
    expect(sink.records.count == 2, "换档+关 → 两条 caffeine")
    expect(sink.records[0].type == "caffeine" && sink.records[0].detail == "basic"
           && sink.records[0].durationSec == 60, "第一段 basic 60s")
    expect(sink.records[1].detail == "enhanced" && sink.records[1].durationSec == 120,
           "第二段 enhanced 120s")

    // 番茄钟：完成一段 focus，中断一段 focus
    tr.pomodoroBegan("focus", at: at(200))
    tr.pomodoroEnded(completed: true, at: at(200 + 1500))
    tr.pomodoroBegan("focus", at: at(2000))
    tr.pomodoroEnded(completed: false, at: at(2000 + 180))
    expect(sink.records.count == 4, "两条番茄钟记录")
    expect(sink.records[2].type == "focus" && sink.records[2].detail == "completed"
           && sink.records[2].durationSec == 1500, "focus completed 25m")
    expect(sink.records[3].detail == "interrupted" && sink.records[3].durationSec == 180,
           "focus interrupted 3m")

    // 未开段时 ended 不记
    tr.pomodoroEnded(completed: true, at: at(9999))
    expect(sink.records.count == 4, "无开段 ended 不产生记录")

    // flush 收尾未结束的 caffeine 段
    tr.caffeine(changedTo: "basic", at: at(5000))
    tr.flush(at: at(5050))
    expect(sink.records.count == 5 && sink.records[4].detail == "basic"
           && sink.records[4].durationSec == 50, "flush 关掉未结束 caffeine 段")

    // recent 最新在前
    let r = sink.recent(2)
    expect(r.count == 2 && r[0].durationSec == 50, "recent 最新在前")
}

// 13. CSVHistorySink：写两条 → 读回 round-trip（临时文件）
do {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("caf-hist-\(getpid()).csv")
    try? FileManager.default.removeItem(at: tmp)
    let sink = CSVHistorySink(url: tmp)
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    sink.append(HistoryRecord(type: "caffeine", start: t0, end: t0.addingTimeInterval(2400), detail: "enhanced"))
    sink.append(HistoryRecord(type: "focus", start: t0, end: t0.addingTimeInterval(1500), detail: "completed"))
    let back = sink.recent(10)
    expect(back.count == 2, "CSV 读回两条")
    expect(back[0].type == "focus" && back[0].detail == "completed" && back[0].durationSec == 1500,
           "最新一条 focus completed 25m（最新在前）")
    expect(back[1].type == "caffeine" && back[1].detail == "enhanced" && back[1].durationSec == 2400,
           "第二条 caffeine enhanced 40m")
    // 新 sink 指向同文件应读到同样内容（持久化）
    let reopened = CSVHistorySink(url: tmp).recent(10)
    expect(reopened.count == 2, "重新打开仍能读到（已落盘）")
    try? FileManager.default.removeItem(at: tmp)
}

// Focus 还原策略：「不覆盖」语义
do {
    // 进入：没开 / 读不到 → 开我们的；已有 Focus → 不碰
    expect(FocusRestorePolicy.shouldActivateOurFocus(prior: .none), "本来没开 → 开我们的")
    expect(FocusRestorePolicy.shouldActivateOurFocus(prior: .unavailable), "读不到 → 回退开我们的")
    expect(!FocusRestorePolicy.shouldActivateOurFocus(prior: .active("Work")), "本来开着 → 不覆盖")

    // 退出：仅当我们开过才关 → 精确还原
    expect(FocusRestorePolicy.shouldDeactivate(weActivated: true), "我们开的 → 退出时关回没开")
    expect(!FocusRestorePolicy.shouldDeactivate(weActivated: false), "不是我们开的 → 退出时不动你的 Focus")
}

if failures > 0 {
    print("\n\(failures) 个失败")
    exit(1)
}
print("\n全部通过 ✅")
