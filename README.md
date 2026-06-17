# Caffinate ☕🍅

[![CI](https://github.com/lincleejun/caffinate-app/actions/workflows/ci.yml/badge.svg)](https://github.com/lincleejun/caffinate-app/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/lincleejun/caffinate-app?include_prereleases&sort=semver)](https://github.com/lincleejun/caffinate-app/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

轻量 macOS 菜单栏效率小助手：防休眠 + 番茄钟。原生 SwiftUI，零依赖，无需 Xcode。

## 功能

- **咖啡因**：三档防休眠
  - 基础：阻止熄屏/休眠（IOPMAssertion）
  - 增强：基础 + 每 50 秒模拟一次 F15 空键重置系统空闲计时，应对强制 idle 锁屏
- **番茄钟**：25/5 可配置，菜单栏直接显示 `🍅 17:32` 倒计时，结束系统通知 + 提示音
- 专注时自动开启防休眠（可关）；防休眠可设 N 小时自动关闭；登录自启
- **专注联动系统 Focus**（可选）：专注时自动开启 macOS Focus/勿扰静音通知，休息/暂停/结束时自动关闭（见下文配置）

## 安装

### 下载安装（推荐）

到 [Releases](https://github.com/lincleejun/caffinate-app/releases) 下载 `Caffinate.app.zip`,解压拖进「应用程序」。

> 应用**未签名**(没有 Apple 付费账号)。首次打开若提示「无法打开」,**右键 App → 打开**即可;或:
> ```bash
> xattr -dr com.apple.quarantine /Applications/Caffinate.app
> ```

### Homebrew

把 `HomebrewFormula/caffinate.rb` 放进你的 tap(如 `lincleejun/homebrew-tap`)后:

```bash
brew install --cask lincleejun/tap/caffinate
```

### 从源码构建

仅需 macOS 14+ 与 Command Line Tools（`xcode-select --install`）：

```bash
./scripts/build-app.sh
cp -R dist/Caffinate.app /Applications/
open /Applications/Caffinate.app
```

首次运行会有一页**引导**,介绍三档防休眠、番茄钟+历史、可选的系统 Focus 联动。

## 增强档授权

增强档需要「辅助功能」权限：点击「增强」会弹出系统授权请求，按提示开启即可。

首次构建前先运行一次 `./scripts/setup-signing.sh` 配置本机自签名证书（会弹系统密码框），
之后所有构建使用固定签名，**授权在重建后保持有效**。未配置证书时回退 ad-hoc 签名，
那种情况下每次重建都需删除旧授权条目并重新添加。

## 专注联动系统 Focus（静音通知）

macOS 不允许 App 直接切换系统 Focus/勿扰，需借「快捷指令」桥接（Apple 安全限制：添加快捷指令必须用户亲自确认，无法静默创建）。

**已预置导出文件时**（`Resources/shortcuts/`，见该目录 README）：
```bash
./scripts/setup-focus-shortcuts.sh   # 弹出快捷指令，点两下「添加」即可（已存在则跳过）
```

**手动配置：**
1. 打开「快捷指令」App，新建快捷指令，命名 **`Caffinate Focus On`**，加入 `设定专注模式`（Set Focus）动作 → 选你要联动的 Focus（如「勿扰」）→ 设为「开启」。
2. 再新建一个命名 **`Caffinate Focus Off`**，同样用 `设定专注模式` 动作 → 设为「关闭」。

然后在 Caffinate 设置里打开「专注时静音通知（联动系统 Focus）」，或 `caf set focus-link on`。

之后：进入专注自动开 Focus；暂停 / 进入休息 / 重置时自动关。专注结束的提示通知会**先关 Focus 再发**，不会被勿扰吞掉。名字不符或未建快捷指令时静默跳过，不影响其他功能。

## CLI

`caf` 可在终端查看/控制一切（App 未运行时自动拉起）：

```bash
caf                       # 状态总览
caf on / caf on max / caf off   # 咖啡因三档
caf pomo / caf pause / caf reset  # 番茄钟
caf set focus 30          # 设置（rest / auto-caf / auto-off 同理）
caf set focus-link on     # 专注联动系统 Focus 开/关
caf history [n]           # 运行历史（默认 20 条）
caf doctor                # 健康自检：断言/权限/快捷指令/历史
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

# 一键自检（推荐）
caf doctor
```

## License

[MIT](LICENSE) © lincleejun
