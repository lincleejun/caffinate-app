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
            response = ControlResponse(ok: false, error: "无法解析请求")
        }

        var out = (try? JSONEncoder().encode(response))
            ?? Data(#"{"ok":false,"error":"响应编码失败"}"#.utf8)
        out.append(0x0A)
        out.withUnsafeBytes { _ = write(client, $0.baseAddress, $0.count) }
    }

    // MARK: - 命令执行（主线程）

    @MainActor
    private func execute(_ request: ControlRequest) -> ControlResponse {
        guard let state else {
            return ControlResponse(ok: false, error: "App 状态不可用")
        }
        switch request.command {
        case "status":
            return success(state)

        case "caffeine":
            let target: CaffeineController.Mode?
            switch request.args.first {
            case "off": target = .off
            case "basic": target = .basic
            case "enhanced": target = .enhanced
            default: target = nil
            }
            guard let target else { return ControlResponse(ok: false, error: "无效档位") }
            state.caffeine.set(target)
            guard state.caffeine.mode == target else {
                return ControlResponse(ok: false, error: state.caffeine.lastError ?? "切换失败",
                                       state: snapshot(state))
            }
            return success(state, "咖啡因 → \(target.label)")

        case "pomo-start":
            state.startFocus()
            return success(state, "开始专注 \(state.focusMinutes) 分钟 🍅")

        case "pomo-pause":
            guard state.phase != .idle else {
                return ControlResponse(ok: false, error: "番茄钟未在运行", state: snapshot(state))
            }
            if state.isPaused {
                state.resume()
                return success(state, "已继续")
            }
            state.pause()
            return success(state, "已暂停")

        case "pomo-reset":
            state.reset()
            return success(state, "已重置")

        case "set":
            return executeSet(request.args, state: state)

        default:
            return ControlResponse(ok: false, error: "未知命令「\(request.command)」")
        }
    }

    @MainActor
    private func executeSet(_ args: [String], state: AppState) -> ControlResponse {
        guard args.count == 2 else { return ControlResponse(ok: false, error: "set 需要两个参数") }
        switch args[0] {
        case "focus":
            guard let v = Int(args[1]), (1...120).contains(v) else {
                return ControlResponse(ok: false, error: "focus 取值 1-120")
            }
            state.focusMinutes = v
            return success(state, "专注时长 → \(v) 分钟")
        case "rest":
            guard let v = Int(args[1]), (1...60).contains(v) else {
                return ControlResponse(ok: false, error: "rest 取值 1-60")
            }
            state.restMinutes = v
            return success(state, "休息时长 → \(v) 分钟")
        case "auto-caf":
            guard args[1] == "on" || args[1] == "off" else {
                return ControlResponse(ok: false, error: "auto-caf 取值 on|off")
            }
            state.autoCaffeinate = (args[1] == "on")
            return success(state, "专注自动防休眠 → \(args[1] == "on" ? "开" : "关")")
        case "auto-off":
            guard let v = Double(args[1]), [0, 1, 2, 4, 8].contains(v) else {
                return ControlResponse(ok: false, error: "auto-off 取值 0|1|2|4|8")
            }
            state.autoOffHours = v
            return success(state, "自动关闭 → \(v == 0 ? "从不" : "\(Int(v)) 小时")")
        case "focus-link":
            guard args[1] == "on" || args[1] == "off" else {
                return ControlResponse(ok: false, error: "focus-link 取值 on|off")
            }
            state.linkSystemFocus = (args[1] == "on")
            return success(state, "专注联动系统 Focus → \(args[1] == "on" ? "开" : "关")")
        default:
            return ControlResponse(ok: false, error: "未知设置项「\(args[0])」")
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
