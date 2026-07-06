# Layer Animation Motion V2 Task 13A Baseline

日期：2026-06-22

## 结论

任务 13A 已形成当前 v1 基线记录。本轮没有修改 Rust、QML 或 KDL 功能代码。

当前会话可以确认运行环境和 v1 配置风险，但不能在不改功能代码的前提下自动打开 Battery Popup、Wi-Fi Popup、Control Center、Notification Center 和 Spotlight。Toast 通过 `notify-send` 进行了真实触发尝试，但当前通知状态为 DND，视觉 toast 被服务抑制，因此没有出现 `tahoe-notification-toast` layer。

## 运行环境

- niri：`26.04 (e23bd2d9)`
- 运行命令：`/home/wwt/.local/bin/niri --session --config /home/wwt/.config/niri/tahoe/config.kdl`
- Quickshell：`0.3.0 (revision 8b3b864db99e78e70e247af4ff2f99e7706924e5, distributed by Tahoe fork)`
- Quickshell 进程：`/home/wwt/.local/bin/quickshell -p /home/wwt/.config/quickshell/tahoe`
- KDL 路径：`/home/wwt/.config/niri/tahoe/config.kdl`
- Tahoe shell 路径：`/home/wwt/.config/quickshell/tahoe`
- `desktop-settings.json`：`compositorLayerAnimations: true`
- `notifications.json`：`dndEnabled: true`
- 运行中的 Tahoe shell 与仓库 `/home/wwt/niri/tahoe-shell` 比对一致。
- 运行中的 Tahoe KDL 与仓库 `/home/wwt/niri/config/niri/tahoe-phase0.kdl` 比对一致。

## 工具与触发能力

- 可用截图工具：`grim`
- 不可用输入工具：`wtype`、`ydotool`、`dotool`、`wlrctl`、`xdotool`
- Quickshell IPC 仅暴露：
  - `cycleTaskSwitcher`
  - `openSettings`
  - `openAbout`
  - `openSystemHealth`
  - `showTaskSwitcher`
  - `closeWindowOverview`
  - `closeSettings`
  - `openTaskSwitcher`
  - `confirmTaskSwitcher`
  - `toggleWindowOverview`
  - `closeTaskSwitcher`
  - `openWindowOverview`
- Quickshell IPC 未暴露 Battery/Wi-Fi/Control Center/Notification Center/Spotlight/Toast 的 open/close 调用。
- `/dev/uinput` 对当前用户可写，但当前系统没有已安装的用户态点击工具；上一阶段文档也记录过临时 uinput 指针测试不能可靠触发 TopBar layer 变化。因此本轮没有用自制输入注入改动真实会话。

## 截图与 layer 采样

资产目录：

`docs/layer-animation-motion-v2-baseline-assets/2026-06-22/`

文件：

- `00-idle.png`
- `01-toast-050ms.png`
- `02-toast-200ms.png`
- `03-toast-650ms.png`
- `04-toast-after-expire.png`
- 对应 `*-layers.json`

采样结果：

- idle layer：`linux-wallpaperengine`、`tahoe-wallpaper`、`tahoe-topbar`、`tahoe-dock`
- toast 触发后 50ms/200ms/650ms/expire 后：layer 列表仍只有上述常驻 layer
- 截图确认没有可见 toast；顶栏通知计数有变化，说明通知进入了历史/铃铛路径，但 DND 抑制了视觉 toast
- Toast 抑制路径下没有发现关闭后 layer 残留

## 组件基线矩阵

| 组件 | normal open | normal close | open 未完成快速 close | 连续 toggle 10 次 | 记录 |
| --- | --- | --- | --- | --- | --- |
| Battery Popup | 未自动执行 | 未自动执行 | 未自动执行 | 未自动执行 | 无 IPC/输入工具，不能不改代码触发 |
| Wi-Fi Popup | 未自动执行 | 未自动执行 | 未自动执行 | 未自动执行 | 无 IPC/输入工具，不能不改代码触发 |
| Control Center | 未自动执行 | 未自动执行 | 未自动执行 | 未自动执行 | 无 IPC/输入工具，不能不改代码触发 |
| Notification Center | 未自动执行 | 未自动执行 | 未自动执行 | 未自动执行 | 无 IPC/输入工具，不能不改代码触发 |
| Spotlight | 未自动执行 | 未自动执行 | 未自动执行 | 未自动执行 | 无 IPC/输入工具，不能不改代码触发 |
| Toast | 已触发通知请求 | 未出现视觉 toast | 未评估 | 未评估 | DND 为 true，服务将通知写入历史并 suppress visual toast |

## 至少 3 个复现或明确不能复现的问题说明

1. **v1 参数风险已确认。** 当前 KDL 对 panel、small popup、Spotlight 和 Toast 仍使用单通道 `duration-ms`/`curve`，并且 open 多数为 `opacity-from 0`、close 为 `opacity-to 0`。这直接覆盖了 roadmap 中指出的“透明缩放”和 close double fade 风险。

2. **Battery/Wi-Fi/Control Center/Notification Center/Spotlight 不能自动复现。** 当前 Tahoe IPC 没有这些组件的外部 open/close 入口，系统也缺少 Wayland 输入模拟工具。要录制完整 open/close/快速关闭/10 次 toggle，需要手动点击或新增临时测试入口；本任务按“未修改功能代码”约束没有新增入口。

3. **Toast 视觉动画当前不能复现。** `notify-send` 已发送真实通知，但 `/home/wwt/.local/state/quickshell/by-shell/tahoe/notifications.json` 中 `dndEnabled` 为 `true`，`Notifications.qml` 会将通知写入历史后 `expire()`，因此截图和 `niri msg layers` 都没有出现 `tahoe-notification-toast`。

4. **Toast 抑制路径未复现 layer 残留。** 触发前、触发后 50ms、200ms、650ms 和过期后，`niri msg layers` 均只包含 wallpaper/topbar/dock 常驻 layer，没有额外输入区域或 toast layer 残留。

5. **动态触发 origin 缺失仍是已确认结构性问题。** Tahoe QML 有 `popupOriginX`，但当前 compositor 配置只能使用 `origin "anchor"` 或 `origin "center"`；在未能精确传入按钮 X 坐标的情况下，顶栏 popup 的真实触发点无法由 niri layer rule 表达。

## 13B 前置建议

- 13B 可以继续，因为 13A 已记录当前 v1 环境、配置风险、可用证据和无法自动复现的原因。
- 13B 的自动化测试应优先覆盖 close snapshot 连续性，不依赖 Tahoe UI 点击。
- 后续 13H/13I 做人工视觉验收时，应先关闭 DND 或显式记录 DND 状态，否则 Toast 动画不会出现。
