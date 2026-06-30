import Foundation
import CaffinateKit

/// App 内的控制服务：unix socket 监听，逐连接读一行 JSON 请求、回一行 JSON 响应。
/// 命令在主线程上执行（AppState 是 @MainActor）。
final class ControlServer {
    private weak var state: AppState?
    private var serverFD: Int32 = -1
    private let queue = DispatchQueue(label: "caffinate.control", qos: .userInitiated)

    init(state: AppState) {
        self.state = state
    }

    func start() {
        let path = ControlSocket.path
        unlink(path)

        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let ok = withUnsafeMutableBytes(of: &addr.sun_path) { dst -> Bool in
            let bytes = path.utf8CString
            guard bytes.count <= dst.count else { return false }
            bytes.withUnsafeBytes { dst.copyBytes(from: $0) }
            return true
        }
        guard ok else { close(serverFD); serverFD = -1; return }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(serverFD, $0, size)
            }
        }
        guard bound == 0 else { close(serverFD); serverFD = -1; return }

        chmod(path, 0o600)
        guard listen(serverFD, 4) == 0 else { close(serverFD); serverFD = -1; return }

        let fd = serverFD
        queue.async { [weak self] in self?.acceptLoop(fd) }
    }

    func stop() {
        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }
        unlink(ControlSocket.path)
    }

    deinit { stop() }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { break }  // server fd 关闭后退出
            handle(client)
        }
    }

    private func handle(_ client: Int32) {
        defer { close(client) }

        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while data.count < 65536 {
            let n = read(client, &buf, buf.count)
            guard n > 0 else { break }
            data.append(contentsOf: buf[0..<n])
            if buf[0..<n].contains(0x0A) { break }
        }

        let response: ControlResponse
        if let request = try? JSONDecoder().decode(ControlRequest.self, from: data) {
            response = DispatchQueue.main.sync {
                MainActor.assumeIsolated { self.execute(request) }
            }
        } else {
            response = ControlResponse(ok: false, error: "Could not parse request")
        }

        var out = (try? JSONEncoder().encode(response))
            ?? Data(#"{"ok":false,"error":"Response encoding failed"}"#.utf8)
        out.append(0x0A)
        out.withUnsafeBytes { _ = write(client, $0.baseAddress, $0.count) }
    }

    // MARK: - 命令执行（主线程）

    @MainActor
    private func execute(_ request: ControlRequest) -> ControlResponse {
        guard let state else {
            return ControlResponse(ok: false, error: "App state unavailable")
        }
        switch request.command {
        case "status":
            return success(state)

        case "history":
            let n = max(1, Int(request.args.first ?? "") ?? 20)
            return ControlResponse(ok: true, state: snapshot(state), history: state.history(n))

        case "doctor":
            return ControlResponse(ok: true, diagnostics: state.diagnostics())

        case "hooks":
            let inv = HookInventory(
                directory: state.hooks.directoryPath,
                configPath: state.hooks.configPath,
                executables: state.hooks.discoveredExecutables(),
                rules: state.hooks.configRules().map { .init(on: $0.on, run: $0.run) }
            )
            return ControlResponse(ok: true, hooks: inv)

        case "caffeine":
            let target: CaffeineController.Mode?
            switch request.args.first {
            case "off": target = .off
            case "basic": target = .basic
            case "enhanced": target = .enhanced
            default: target = nil
            }
            guard let target else { return ControlResponse(ok: false, error: "Invalid mode") }
            state.caffeineSourceHint = "cli"
            state.caffeine.set(target)
            guard state.caffeine.mode == target else {
                return ControlResponse(ok: false, error: state.caffeine.lastError ?? "Switch failed",
                                       state: snapshot(state))
            }
            return success(state, "Caffeine → \(target.cliLabel)")

        case "pomo-start":
            state.startFocus()
            return success(state, "Focus started: \(state.focusMinutes) min 🍅")

        case "pomo-pause":
            guard state.phase != .idle else {
                return ControlResponse(ok: false, error: "Pomodoro not running", state: snapshot(state))
            }
            if state.isPaused {
                state.resume()
                return success(state, "Resumed")
            }
            state.pause()
            return success(state, "Paused")

        case "pomo-reset":
            state.reset()
            return success(state, "Reset")

        case "set":
            return executeSet(request.args, state: state)

        default:
            return ControlResponse(ok: false, error: "Unknown command “\(request.command)”")
        }
    }

    @MainActor
    private func executeSet(_ args: [String], state: AppState) -> ControlResponse {
        guard args.count == 2 else { return ControlResponse(ok: false, error: "set needs two arguments") }
        switch args[0] {
        case "focus":
            guard let v = Int(args[1]), (1...120).contains(v) else {
                return ControlResponse(ok: false, error: "focus must be 1-120")
            }
            state.focusMinutes = v
            return success(state, "Focus duration → \(v) min")
        case "rest":
            guard let v = Int(args[1]), (1...60).contains(v) else {
                return ControlResponse(ok: false, error: "rest must be 1-60")
            }
            state.restMinutes = v
            return success(state, "Break duration → \(v) min")
        case "auto-caf":
            guard args[1] == "on" || args[1] == "off" else {
                return ControlResponse(ok: false, error: "auto-caf must be on|off")
            }
            state.autoCaffeinate = (args[1] == "on")
            return success(state, "Auto keep-awake while focusing → \(args[1] == "on" ? "on" : "off")")
        case "auto-off":
            guard let v = Double(args[1]), [0, 1, 2, 4, 8].contains(v) else {
                return ControlResponse(ok: false, error: "auto-off must be 0|1|2|4|8")
            }
            state.autoOffHours = v
            return success(state, "Auto-disable → \(v == 0 ? "never" : "\(Int(v))h")")
        case "focus-link":
            guard args[1] == "on" || args[1] == "off" else {
                return ControlResponse(ok: false, error: "focus-link must be on|off")
            }
            state.linkSystemFocus = (args[1] == "on")
            return success(state, "Link system Focus → \(args[1] == "on" ? "on" : "off")")
        default:
            return ControlResponse(ok: false, error: "Unknown setting “\(args[0])”")
        }
    }

    @MainActor
    private func success(_ state: AppState, _ message: String? = nil) -> ControlResponse {
        ControlResponse(ok: true, message: message, state: snapshot(state))
    }

    @MainActor
    private func snapshot(_ state: AppState) -> ControlState {
        let modeName: String
        switch state.caffeine.mode {
        case .off: modeName = "off"
        case .basic: modeName = "basic"
        case .enhanced: modeName = "enhanced"
        }
        let phaseName: String
        switch state.phase {
        case .idle: phaseName = "idle"
        case .focus: phaseName = "focus"
        case .rest: phaseName = "rest"
        }
        return ControlState(
            caffeineMode: modeName,
            phase: phaseName,
            remainingSeconds: Int(state.remaining.rounded()),
            isPaused: state.isPaused,
            focusMinutes: state.focusMinutes,
            restMinutes: state.restMinutes,
            autoCaffeinate: state.autoCaffeinate,
            autoOffHours: state.autoOffHours,
            linkSystemFocus: state.linkSystemFocus,
            accessibilityTrusted: CaffeineController.accessibilityTrusted
        )
    }
}
