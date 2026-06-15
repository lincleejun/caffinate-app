# 预置快捷指令

`scripts/setup-focus-shortcuts.sh` 会打开这里的 `.shortcut` 文件，让新机器只需点两下
「添加快捷指令」即可装好联动所需的快捷指令，无需手搭动作。

## 如何生成这两个文件（一次性）

1. 在「快捷指令」App 建好 `Caffinate Focus On` / `Caffinate Focus Off`
   （各一个 `设定专注模式` 动作，建议联动通用的「勿扰」，分别设为开启 / 关闭）。
2. 右键每个快捷指令 → 共享 → 导出文件，分别存为：
   - `Caffinate Focus On.shortcut`
   - `Caffinate Focus Off.shortcut`
   放到本目录。

> 导出时签名模式选「任何人」(anyone)，否则别的机器打开会被拦。
> 务必联动**通用 Focus（勿扰 / Do Not Disturb）**，自定义 Focus 在别的机器上可能不存在。
