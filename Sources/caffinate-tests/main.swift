import Foundation
import CaffinateKit

var failures = 0
func expect(_ condition: Bool, _ label: String, line: Int = #line) {
    if condition { print("  ok - \(label)") }
    else { failures += 1; print("FAIL - \(label) (line \(line))") }
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

if failures > 0 {
    print("\n\(failures) 个失败")
    exit(1)
}
print("\n全部通过 ✅")
