# Tahoe 任务桌面阶段 7 验收记录

日期：2026-06-30

对应路线图：`task-desktop-research-roadmap-2026-06-30.md` 阶段 7：XWayland、托盘、AppMenu 兼容性产品化。

## 结论

阶段 7 已完成。

本阶段把 XWayland 兼容路径从“隐含在 arch-update.sh 和健康页进程探测里”，收敛为可复用诊断脚本。健康页现在能显示 patched `xwayland-satellite` 的 `ok`、`missing`、`stale`、`broken` 状态，并能看到 patch hash、上游 ref、build stamp、wrapper、niri config 指向和 minimize/clipboard bridge 回归锚点。`arch-update.sh` 在构建/部署后复用同一检查，静态兼容路径失效时会明确失败。

## 改动范围

- 新增 `scripts/check-xwayland-satellite-compat.sh`。
  - 检查 patched binary、glamor wrapper、build stamp、patch hash、上游 ref、niri config 指向和运行中进程。
  - 检查 `patches/xwayland-satellite-minimize.patch` 中 minimize 与 clipboard bridge 的回归锚点。
  - 输出健康页可解析的 `STATUS|...` 行，状态包含 `ok`、`missing`、`stale`、`broken`。
  - `--strict` 对静态 missing/stale/broken 退出非 0；运行中旧进程只提示重启，不阻断更新。
- 修改 `scripts/arch-update.sh`。
  - 新增 `run_xwayland_satellite_compat_check()`。
  - 构建、wrapper 部署和 niri config 部署后运行严格兼容检查。
  - Tahoe shell 部署时把诊断脚本安装到 `~/.config/quickshell/tahoe/scripts/check-xwayland-satellite-compat.sh`，供已部署健康页调用。
- 修改 `tahoe-shell/services/SystemStatus.qml`。
  - 健康页 XWayland 状态改为调用 `scripts/check-xwayland-satellite-compat.sh`。
  - 保留无诊断脚本时的降级状态和修复路径。
  - `stale` 计入注意，`broken` 计入缺失。
- 修改 `tahoe-shell/components/settings/SettingsTheme.js`。
  - 增加 `stale` / `broken` 状态标签和颜色。
- 修改 `tahoe-shell/services/CommandRunner.qml` 和 `AppMenu.qml`。
  - AppMenu bridge 依赖检查增加 helper 文件可读/可运行原因。
  - AppMenu 服务读取同一依赖状态，helper 缺失或损坏时直接显示明确原因。
- 修改 `scripts/README.md`，记录新的 XWayland 兼容诊断脚本和严格检查语义。
- 更新 `tahoe-shell/docs/task-desktop-research-roadmap-2026-06-30.md` 阶段 7 状态。

## 验收点

- 用户能在健康页看到 XWayland patched path 是 `ok`、`missing`、`stale` 还是 `broken`。
- XWayland 状态能展示 patch hash、上游 ref、wrapper 路径、niri config 指向和运行时状态。
- 健康页在 repo 开发态和已部署 `~/.config/quickshell/tahoe` 安装态都能找到 XWayland 诊断脚本；缺少脚本时显示降级修复路径。
- minimize 回归检查覆盖 `set_minimized`、`WM_CHANGE_STATE`、`wm_action_minimize`、`xdg_toplevel::Request::SetMinimized` 和测试锚点。
- clipboard bridge 回归检查覆盖 `UTF8_STRING`、`text/plain;charset=utf-8`、`selection_cancelled` 和 `ForeignSelection` 锚点。
- `arch-update.sh` 在静态 XWayland 兼容路径缺失、过期或损坏时明确失败。
- legacy tray bridge 仍在健康页展示，并保留缺失/未运行时的修复路径。
- AppMenu bridge 缺少 helper、`python3`、`busctl`、registrar 或 focused-app DBusMenu 时都有明确状态/原因。
- 当前 patched satellite 路径未删除，现有 niri config 仍指向 `~/.local/lib/niri/xwayland-satellite-minimize-glamor`。

## 验证

已执行：

```sh
bash -n scripts/check-xwayland-satellite-compat.sh scripts/arch-update.sh
```

结果：通过。

```sh
scripts/check-xwayland-satellite-compat.sh --status --strict
```

结果：退出码 0，输出 `xwayland` 和 `xwayland_regression` 两条 `ok` 状态；patch sha 为 `faa6695b88381937051fd04f8fc3bafcd0d4335b08042da9fcb0a8a5f39b696b`。

```sh
python3 tahoe-shell/services/appmenu_probe.py '' '' '' ''
```

结果：退出码 0，当前会话输出 `未检测到 AppMenu registrar`，detail 为当前应用未发布可发现的 `/MenuBar` DBusMenu 或系统未启动 appmenu bridge。

```sh
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I /home/wwt/niri/quickshell/build-tahoe/qml_modules tahoe-shell/services/SystemStatus.qml tahoe-shell/services/CommandRunner.qml tahoe-shell/services/AppMenu.qml tahoe-shell/components/settings/SettingsTheme.js tahoe-shell/components/settings/controls/TahoeStatusRow.qml tahoe-shell/components/settings/pages/HealthPage.qml tahoe-shell/components/settings/pages/OverviewPage.qml
```

结果：退出码 0，无输出。

```sh
git diff --check -- scripts/check-xwayland-satellite-compat.sh scripts/arch-update.sh scripts/README.md tahoe-shell/services/SystemStatus.qml tahoe-shell/services/CommandRunner.qml tahoe-shell/services/AppMenu.qml tahoe-shell/components/settings/SettingsTheme.js
```

结果：通过。

## 未执行项

未运行完整 `scripts/arch-update.sh`，也未重启 live Tahoe/niri 会话做真实 X11 应用 minimize/clipboard 交互。原因：`arch-update.sh` 会拉取代码、更新 submodule、构建和部署，会影响当前工作树与桌面会话；本阶段验收只运行新增诊断脚本、QML lint、脚本语法和 helper 探测。实际会话中仍建议打开一个 X11 应用，确认 minimize、剪贴板互通和 legacy tray/AppMenu 健康页状态。
