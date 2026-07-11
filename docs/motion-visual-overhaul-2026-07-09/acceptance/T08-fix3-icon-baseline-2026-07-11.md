# T08-fix3 · 图标悬空（半空）· 验收记录

日期：2026-07-11

## 背景

用户反馈截图右侧运行窗口图标「卡在半空中」——放大后脚底离开 Dock 基线，看起来悬空。

## 根因

图标 `transformOrigin: Item.Center`：scale 时上下同时扩展，脚底上移约 `(scale−1)/2 × size`。  
再叠加 `lift = (magnification−1)×14`（+ hover +2），脚底进一步抬离基线。  
macOS Dock 是从图标**底部**放大，脚底始终贴在 Dock 上沿附近。

## 改动

| 位置 | 改动 |
| --- | --- |
| `Dock.qml` pinned `appIcon` | `transformOrigin: Item.Bottom`；去掉 hover +2 lift；`dockLiftFactor=0` |
| `WindowButton.qml` `icon` | `transformOrigin: Item.Bottom`；`lift=0`；y 改为底对齐 `parent.height - height - 6 - bounceOffset` |
| 点击 bounce | 仍用 `bounceOffset` 整图标上跳，不影响 rest 基线 |

## 验收

| 命令 | 结果 |
| --- | --- |
| pytest `test_motion_token_convergence` | PASS |
| quickshell 冒烟 | Configuration Loaded；无 Binding loop / interceptor |

手测：扫过 pinned / 窗口半区，放大时脚底贴基线，不悬空；离开后全部回落。

## 结论

可单独 `git revert`。部署副本需同步后重启 shell。
