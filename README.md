# Caffinate ☕🍅

轻量 macOS 菜单栏效率小助手：防休眠 + 番茄钟。原生 SwiftUI，零依赖，无需 Xcode。

## 功能

- **咖啡因**：三档防休眠
  - 基础：阻止熄屏/休眠（IOPMAssertion）
  - 增强：基础 + 每 50 秒模拟一次 F15 空键重置系统空闲计时，应对强制 idle 锁屏
- **番茄钟**：25/5 可配置，菜单栏直接显示 `🍅 17:32` 倒计时，结束系统通知 + 提示音
- 专注时自动开启防休眠（可关）；防休眠可设 N 小时自动关闭；登录自启

## 构建 & 安装

仅需 macOS 14+ 与 Command Line Tools（`xcode-select --install`）：

```bash
./scripts/build-app.sh
cp -R dist/Caffinate.app /Applications/
open /Applications/Caffinate.app
```

## 增强档授权

增强档需要「辅助功能」权限：系统设置 → 隐私与安全性 → 辅助功能 → 添加 Caffinate。
注意：本应用为 ad-hoc 签名，**每次重新构建后需要重新授权**（先移除旧条目再添加）。

## CLI

`caf` 可在终端查看/控制一切（App 未运行时自动拉起）：

```bash
caf                       # 状态总览
caf on / caf on max / caf off   # 咖啡因三档
caf pomo / caf pause / caf reset  # 番茄钟
caf set focus 30          # 设置（rest / auto-caf / auto-off 同理）
caf json                  # JSON 输出，脚本用
```

安装：`./scripts/build-app.sh && sudo cp dist/caf /usr/local/bin/`

## 开发

```bash
swift build                # 编译
swift run caffinate-tests  # 跑测试
swift run Caffinate        # 开发模式直接跑（无通知/自启，属预期）
```

## 验证防休眠生效

```bash
# 基础档：应出现本应用的 assertion
pmset -g assertions | grep -i caffinate

# 增强档：不碰键鼠时，系统空闲秒数应始终 ≤ 50
ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print $NF/1000000000; exit}'
```
