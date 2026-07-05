# Tahoe 任务桌面阶段 4 验收记录

日期：2026-06-30

对应路线图：`task-desktop-research-roadmap-2026-06-30.md` 阶段 4：命令和依赖 provider。

## 结论

阶段 4 已完成。

本阶段新增轻量 `CommandRunner` 服务，把 QML 中分散的外部命令依赖探测收敛到同一 provider；截图、剪贴板、AppMenu、网络 fallback、电源动作、电源模式、亮度和输入法均接入 provider。健康页读取同一套依赖状态，不再维护截图、剪贴板、AppMenu、网络、蓝牙和输入法的重复探测逻辑。

## 改动范围

- 新增 `tahoe-shell/services/CommandRunner.qml`。
- 修改 `tahoe-shell/shell.qml`，实例化并注入 `commandRunner`。
- 修改 `tahoe-shell/components/Screenshot.qml`，保留既有 `grim`、`slurp`、`swappy`、`wl-copy`、`notify-send` 脚本，改由 provider 构造和启动，并记录结构化 action result。
- 修改 `tahoe-shell/services/ClipboardHistory.qml`，剪贴板工具探测优先读取 provider；复制、删除、清空动作通过 provider 返回结构化结果；`cliphist`/`wl-clipboard` 路径保持不变。
- 修改 `tahoe-shell/services/AppMenu.qml`，Python helper 和 `busctl` 触发命令由 provider 统一构造，缺依赖时写入明确状态。
- 修改 `tahoe-shell/services/Controls.qml`，Wi-Fi `nmcli` fallback、自动连接维护和亮度写入接入 provider；Quickshell 网络/蓝牙状态源保持不变。
- 修改 `tahoe-shell/services/Power.qml` 和 `PowerProfiles.qml`，电源动作与电源模式命令通过 provider 包装；Tahoe lock screen 主路径未改。
- 修改 `tahoe-shell/services/InputMethod.qml`，`fcitx5-remote` 探测和切换命令接入 provider。
- 修改 `tahoe-shell/services/SystemStatus.qml`，健康页合并 provider status items 与本地系统状态，去除重复依赖探测。
- 修改 `tahoe-shell/components/TopBar.qml`，截图依赖缺失时保留入口但降透明度。

## 验收点

- 截图仍使用当前设置和原工具链：`grim`、`slurp`、可选 `swappy`、`wl-copy`、`notify-send`。
- 剪贴板历史仍使用 `cliphist` 和 `wl-clipboard`。
- AppMenu 仍使用 `services/appmenu_probe.py` 和 `busctl`。
- Wi-Fi fallback 仍使用 `nmcli`，蓝牙状态仍来自 Quickshell Bluetooth 服务。
- 电源菜单的锁屏仍优先进入 Tahoe `LockScreen.qml`，其它电源动作保留原 systemd/niri fallback。
- 健康页信息不减少，并新增/统一显示 provider 输出的网络、蓝牙、输入法、截图、剪贴板、AppMenu、电源命令、电源模式和亮度命令状态。
- 缺依赖时 UI/服务状态能显示明确原因：健康页 status row、剪贴板弹窗 `errorText`、截图服务 `errorText/lastResult`、AppMenu 状态和输入法 tooltip。
- action result 使用统一结构：`success`、`failure`、`missing`、`timeout`、`cancelled`。

## 验证

已执行：

```sh
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I /home/wwt/niri/quickshell/build-tahoe/qml_modules tahoe-shell/services/CommandRunner.qml tahoe-shell/components/Screenshot.qml tahoe-shell/components/TopBar.qml tahoe-shell/services/ClipboardHistory.qml tahoe-shell/services/AppMenu.qml tahoe-shell/services/InputMethod.qml tahoe-shell/services/Controls.qml tahoe-shell/services/Power.qml tahoe-shell/services/PowerProfiles.qml tahoe-shell/services/SystemStatus.qml tahoe-shell/shell.qml
```

结果：通过。仍有仓库既有的 `PanelWindow`/`TahoeGlass` qmltypes warning、`modelData` unqualified warning 和部分 Quickshell service qmltypes warning。

```sh
git diff --check -- tahoe-shell/services/CommandRunner.qml tahoe-shell/components/Screenshot.qml tahoe-shell/components/TopBar.qml tahoe-shell/services/ClipboardHistory.qml tahoe-shell/services/AppMenu.qml tahoe-shell/services/InputMethod.qml tahoe-shell/services/Controls.qml tahoe-shell/services/Power.qml tahoe-shell/services/PowerProfiles.qml tahoe-shell/services/SystemStatus.qml tahoe-shell/shell.qml
```

结果：通过。

```sh
sh -n <extracted CommandRunner.dependencyProbeScript>
sh -n <extracted SystemStatus.probeScript>
```

结果：均通过。

实际执行 `CommandRunner.dependencyProbeScript`：退出码 0，并输出 `COMMAND|...` 与 `STATUS|...` 行；本机状态中 network、bluetooth、fcitx、screenshot、clipboard、power、powerprofiles、brightness 为 ok，AppMenu bridge 为 warn。

实际执行 `SystemStatus.probeScript`：退出码 0，并输出 portal、PipeWire、UPower、Tahoe 锁屏路径、SNI、legacy tray、xwayland、niri IPC、窗口缩略图 provider 和 about 信息。

## 未执行项

未重启 live Tahoe shell，也未做真实鼠标/键盘交互验收。原因：当前阶段是源码反腐化和依赖状态收敛，为避免影响正在运行的桌面会话，本记录只做 QML lint、脚本语法、脚本实际探测和 diff 检查。实际会话中仍建议打开截图入口、剪贴板弹窗、AppMenu、Wi-Fi fallback、电源菜单和健康页做一次目视确认。
