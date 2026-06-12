# Caffinate — 菜单栏效率小助手 设计文档

日期：2026-06-12
状态：已确认

## 目标

一个轻便、本地运行的 macOS 菜单栏小助手，两个功能：

1. **防休眠（caffeine）**：阻止电脑熄屏/休眠；公司 MDM 强制 idle 锁屏的场景下，可切换到增强档（模拟无感输入重置 idle 计时器）。
2. **番茄钟**：极简款，25/5 分钟可配置，菜单栏直接显示倒计时。

非目标：历史统计、图表、任何持久化数据库、第三方依赖。

## 形态与技术栈

- 原生 SwiftUI 菜单栏 App，`MenuBarExtra`（window 风格弹窗），无 Dock 图标（`LSUIElement = true`）。
- Swift Package Manager 构建（`swift build`），`scripts/build-app.sh` 打包成 `Caffinate.app`（手写 Info.plist + ad-hoc 签名），**不需要 Xcode**。
- 目标系统 macOS 15（本机），最低 macOS 14。
- 零第三方依赖，设置存 UserDefaults。

## 菜单栏状态

| 状态 | 菜单栏显示 |
|---|---|
| 空闲 | ☕ 轮廓图标 |
| 防休眠开启 | ☕ 实心图标 |
| 番茄运行中 | `🍅 17:32` 倒计时文本 |

## 模块 1：CaffeineController（防休眠）

三态：**关 / 基础 / 增强**。

- **基础档**：`IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep)` 原生阻止显示器与系统 idle 休眠。App 退出/关闭开关时释放 assertion。
- **增强档**：基础档之上，每 50 秒用 `CGEvent` 发送一次 F15 键按下+抬起（无可见效果），重置系统 idle 计时器，应对 MDM 强制锁屏。
- **权限**：增强档需要"辅助功能"权限。用 `AXIsProcessTrusted()` 检测；未授权时增强档置灰，弹窗内显示引导 + 一键打开系统设置（`x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`）。
- **自动关闭**：可选"N 小时后自动关"（默认关闭该选项），防止整夜亮屏。

## 模块 2：PomodoroTimer（番茄钟）

- 纯状态机：`idle → focus(默认25min) → break(默认5min) → idle`；支持暂停/继续/重置。
- 时长可配置（专注 1–120 min，休息 1–60 min）。
- **联动**：专注开始时若防休眠为"关"，自动开启基础档；专注/休息结束后恢复原状态。设置项"专注时自动防休眠"默认开，可关。
- 阶段结束：系统通知（UserNotifications，首次启动请求权限）+ 提示音（NSSound 系统音）。
- 不记录历史。

## UI（奶油暖调）

弹窗约 280×360：

- 米白/奶油底色，大圆角卡片，柔和阴影；点缀色：番茄红（计时）+ 咖啡棕（caffeine）。
- 上部：「咖啡因」卡片，三态分段开关（关/基础/增强）+ 状态说明文字。
- 中部：大号圆环倒计时（番茄红渐变进度），中央数字时间，下方 开始/暂停/重置 按钮。
- 底部：齿轮进设置页（同一弹窗内翻页）：专注/休息时长、自动联动开关、自动关闭时长、登录自启（`SMAppService.mainApp`）。

## 错误处理

- 辅助功能未授权 → 增强档不可选 + 界面引导，不静默失败。
- IOPMAssertion 创建失败 → 开关回弹到"关"并显示错误提示。
- 通知权限被拒 → 阶段结束仍播放提示音，菜单栏闪烁文字提示。

## 测试与验证

- `PomodoroTimer` 状态机为纯逻辑（注入时钟），`swift test` 单测覆盖：状态流转、暂停/恢复、时长边界、联动触发。
- 防休眠基础档：开启后 `pmset -g assertions` 应出现本 App 的 assertion；关闭后消失。
- 增强档：开启后系统 idle 时间（`ioreg HIDIdleTime`）应每 ~50s 被重置。

## 交付物

- `Package.swift` + `Sources/Caffinate/`（App 源码）+ `Tests/`
- `scripts/build-app.sh` → 产出 `dist/Caffinate.app`
- `README.md`：构建、安装、授权说明
