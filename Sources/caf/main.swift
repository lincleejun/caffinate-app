import Foundation
import CaffinateKit

// MARK: - socket 通信

func connectSocket(path: String) -> Int32? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let ok = withUnsafeMutableBytes(of: &addr.sun_path) { dst -> Bool in
        let bytes = path.utf8CString
        guard bytes.count <= dst.count else { return false }
        bytes.withUnsafeBytes { dst.copyBytes(from: $0) }
        return true
    }
    guard ok else { close(fd); return nil }

    let size = socklen_t(MemoryLayout<sockaddr_un>.size)
    let connected = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.connect(fd, $0, size)
        }
    }
    guard connected == 0 else { close(fd); return nil }
    return fd
}

func roundTrip(_ request: ControlRequest) -> ControlResponse? {
    guard let fd = connectSocket(path: ControlSocket.path) else { return nil }
    defer { close(fd) }

    var payload = (try? JSONEncoder().encode(request)) ?? Data()
    payload.append(0x0A)
    let sent = payload.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    guard sent == payload.count else { return nil }

    var data = Data()
    var buf = [UInt8](repeating: 0, count: 4096)
    while data.count < 65536 {
        let n = read(fd, &buf, buf.count)
        guard n > 0 else { break }
        data.append(contentsOf: buf[0..<n])
        if buf[0..<n].contains(0x0A) { break }
    }
    return try? JSONDecoder().decode(ControlResponse.self, from: data)
}

/// 连不上则拉起 App 并轮询等待 socket 就绪（5s 超时）
func roundTripAutoLaunch(_ request: ControlRequest) -> ControlResponse? {
    if let resp = roundTrip(request) { return resp }

    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = ["-g", "-b", "com.lijun.caffinate"]
    do {
        try open.run()
        open.waitUntilExit()
    } catch {
        return nil
    }
    guard open.terminationStatus == 0 else { return nil }

    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
        usleep(200_000)  // 200ms
        if let resp = roundTrip(request) { return resp }
    }
    return nil
}

// MARK: - 渲染

func fmtTime(_ seconds: Int) -> String {
    String(format: "%d:%02d", seconds / 60, seconds % 60)
}

func render(_ resp: ControlResponse) {
    if let message = resp.message { print(message) }
    if let d = resp.diagnostics {
        func mark(_ ok: Bool) -> String { ok ? "✅" : "⚠️" }
        let mode = ["off": "Off", "basic": "Basic", "enhanced": "Enhanced"][d.caffeineMode] ?? d.caffeineMode
        print("🩺 Caffinate doctor")
        print("  Caffeine mode: \(mode)")
        print("  \(mark(d.caffeineMode == "off" || d.holdsAssertion)) Keep-awake assertion: \(d.holdsAssertion ? "held" : (d.caffeineMode == "off" ? "off (normal)" : "not held⚠️"))")
        print("  \(mark(d.accessibilityTrusted)) Accessibility: \(d.accessibilityTrusted ? "granted" : "not granted (Enhanced unavailable)")")
        print("  \(mark(!d.linkSystemFocus || d.focusShortcutsInstalled)) Link system Focus: \(d.linkSystemFocus ? "on" : "off")\(d.linkSystemFocus ? (d.focusShortcutsInstalled ? " (shortcuts ready)" : " (shortcuts missing⚠️)") : "")")
        print("  \(mark(d.historyWritable)) History writable: \(d.historyWritable ? "yes" : "no")")
        print("  History file: \(d.historyPath)")
        return
    }
    if let history = resp.history {
        if history.isEmpty { print("(no run history yet)") }
        else { for r in history { print(r.display) } }
        return
    }
    guard let s = resp.state else { return }

    let mode = ["off": "Off", "basic": "Basic", "enhanced": "Enhanced"][s.caffeineMode] ?? s.caffeineMode
    let modeDetail: String
    switch s.caffeineMode {
    case "basic": modeDetail = " (display & system sleep blocked)"
    case "enhanced": modeDetail = " (sleep blocked + idle reset)"
    default: modeDetail = ""
    }
    print("☕ Caffeine: \(mode)\(modeDetail)")

    switch s.phase {
    case "idle":
        print("🍅 Pomodoro: ready (focus \(s.focusMinutes) min)")
    default:
        let label = s.phase == "focus" ? "Focus" : "Break"
        let pause = s.isPaused ? " · paused" : ""
        let total = (s.phase == "focus" ? s.focusMinutes : s.restMinutes) * 60
        print("🍅 Pomodoro: \(label)\(pause) \(fmtTime(s.remainingSeconds)) / \(fmtTime(total))")
    }

    let autoOff = s.autoOffHours == 0 ? "never" : "\(Int(s.autoOffHours))h"
    print("⚙️ Settings: focus \(s.focusMinutes)min · break \(s.restMinutes)min"
          + " · auto keep-awake \(s.autoCaffeinate ? "on" : "off") · auto-off \(autoOff)"
          + " · link Focus \(s.linkSystemFocus ? "on" : "off")")
    if !s.accessibilityTrusted {
        print("⚠️ Accessibility not granted: Enhanced unavailable (System Settings → Privacy & Security → Accessibility)")
    }
}

func stderrLine(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

// MARK: - main

switch CLIParse.parse(Array(CommandLine.arguments.dropFirst())) {
case .help:
    print(CLIParse.usage)
    exit(0)

case .failure(let reason):
    stderrLine("Error: \(reason)")
    stderrLine("")
    stderrLine(CLIParse.usage)
    exit(1)

case .run(let parsed):
    guard let resp = roundTripAutoLaunch(parsed.request) else {
        stderrLine("Could not reach Caffinate (app launch timed out or comms failed)")
        exit(2)
    }
    if parsed.rawOutput {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        if let data = try? enc.encode(resp) {
            print(String(decoding: data, as: UTF8.self))
        }
    } else {
        if !resp.ok, let error = resp.error { stderrLine("Error: \(error)") }
        render(resp)
    }
    exit(resp.ok ? 0 : 1)
}
