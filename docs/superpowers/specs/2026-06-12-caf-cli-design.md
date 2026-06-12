# caf — Caffinate 联动 CLI 设计文档

日期：2026-06-12
状态：已确认

## 目标

新增命令行工具 `caf`，对运行中的 Caffinate 菜单栏 App 查看/设置全部功能：
咖啡因三档、番茄钟启停、所有设置项。状态唯一持有者仍是 App；CLI 只是遥控器。

非目标：CLI 独立执行防休眠、历史/统计、远程控制、第三方依赖。

## 架构

```
caf (CLI 可执行)  ──单行 JSON over unix socket──▶  ControlServer (App 内)
                                                        │ 主线程调用
                                                        ▼
                                                    AppState（现有）
```

- **IPC**：Unix domain socket，路径 `~/Library/Application Support/Caffinate/caf.sock`，
  权限 0600。协议：连接 → CLI 发一行 JSON 请求 → App 回一行 JSON 响应 → 断开。
- **共享协议层**：放在 `CaffinateKit`（CLI 与 App 共同依赖），定义 `ControlRequest` /
  `ControlResponse`（Codable）与命令解析，可单测。
- **App 端**：`ControlServer` 监听 socket（后台队列 accept，DispatchQueue.main 执行命令），
  App 启动时启动，退出时删除 socket 文件。
- **CLI 端**：解析 argv → 若 socket 不通则 `open -b com.lijun.caffinate` 拉起 App，
  轮询等待 socket 就绪（5s 超时）→ 发送请求 → 渲染响应。

## 命令集

| 命令 | 行为 |
|---|---|
| `caf` | 人类可读状态总览：咖啡因档位、番茄阶段/剩余/进度、全部设置 |
| `caf json` | 同上，原始 JSON 输出（脚本用） |
| `caf on` | 咖啡因 → 基础 |
| `caf on max` | 咖啡因 → 增强（未授权辅助功能时返回错误） |
| `caf off` | 咖啡因 → 关 |
| `caf pomo` | 开始专注 |
| `caf pause` | 暂停⇄继续（toggle；idle 时报错） |
| `caf reset` | 重置番茄钟 |
| `caf set focus <1-120>` | 专注分钟数 |
| `caf set rest <1-60>` | 休息分钟数 |
| `caf set auto-caf on\|off` | 专注时自动防休眠 |
| `caf set auto-off <0\|1\|2\|4\|8>` | 防休眠 N 小时自动关（0=从不） |
| `caf help` / `caf -h` / 未知命令 | 用法说明（未知命令时 exit 1） |

每个写命令成功后回显一行结果 + 当前关键状态。

## 协议

请求：`{"command":"set","args":["focus","30"]}`（command + 字符串参数数组）。
响应：`{"ok":true,"state":{...},"message":"..."}` 或 `{"ok":false,"error":"..."}`。
`state` 完整快照：`caffeineMode(off|basic|enhanced)`、`phase(idle|focus|rest)`、
`remainingSeconds`、`isPaused`、`focusMinutes`、`restMinutes`、`autoCaffeinate`、
`autoOffHours`、`accessibilityTrusted`。

## 错误处理

- App 拉起后 socket 5s 内未就绪 → stderr `无法连接 Caffinate`，exit 2。
- 业务错误（增强档未授权、idle 时 pause、参数越界）→ `ok:false`，CLI 显示 error，exit 1。
- 参数边界复用 App 现有约束（focus 1...120、rest 1...60、auto-off 枚举值）。
- App 收到畸形 JSON → 回 `ok:false`，不崩溃。

## 测试

- 协议层（命令解析、参数校验、编解码 round-trip）加入 `caffinate-tests`。
- 端到端：构建后实测 `caf`、`caf on`→`pmset -g assertions`、`caf set focus 30`→UI 同步、
  杀掉 App 后 `caf` 自动拉起。

## 安装

`scripts/build-app.sh` 增加：release 构建 `caf` 并提示
`sudo cp .build/release/caf /usr/local/bin/`（不自动 sudo）。README 增加 CLI 章节。
