# Dynamic Island T08 验收记录

日期：2026-06-24

状态：完成

## 修改文件

- `tahoe-shell/services/DynamicIsland.qml`
  - 监听 `Windows.activeWorkspaceName`。
  - 工作区变化进入 `transient_workspace`。
  - 使用 `Windows.qml` 只读数据，不修改窗口服务。
  - 当前 expanded 或用户交互期间不强行打断。
- `tahoe-shell/components/DynamicIslandContent.qml`
  - 复用既有 transient detail 内容路径显示工作区图标和文本。
- `tahoe-shell/docs/visual-baselines/2026-06-24-dynamic-island-t05-t08/`
  - `workspace-capsule.png`
- `tahoe-shell/docs/dynamic-island-research-roadmap-2026-06-23.md`
  - 标记 T08 完成并链接本验收记录。

`tahoe-shell/services/Windows.qml` 未修改。

## 验证命令

```bash
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I quickshell/build-tahoe/qml_modules tahoe-shell/services/DynamicIsland.qml tahoe-shell/components/DynamicIslandOverlay.qml tahoe-shell/components/DynamicIslandContent.qml tahoe-shell/components/DynamicIslandMediaView.qml tahoe-shell/components/DynamicIslandSummaryView.qml tahoe-shell/shell.qml
timeout 10s /home/wwt/.local/bin/quickshell --no-color --path tahoe-shell
niri msg --json workspaces
niri msg action focus-workspace 2
/home/wwt/.local/bin/qs ipc --pid "$pid" call tahoe dynamicIslandGetDebugSummary
grim -g '0,0 2048x240' tahoe-shell/docs/visual-baselines/2026-06-24-dynamic-island-t05-t08/workspace-capsule.png
niri msg action focus-workspace 1
niri msg --json layers
```

结果：

- 验收前工作区 1 为 active，工作区 2/3 存在于 `eDP-2`。
- `niri msg action focus-workspace 2` 触发：
  - `state=transient_workspace`
  - `displayText=Workspace 2`
  - `targetScreenName=eDP-2`
- 约 1.25 秒后回到 `resting_media`。
- 验收结束后执行 `niri msg action focus-workspace 1` 恢复工作区。

## 运行时 Layer 列表

T08 没有新增 layer；运行时仍为：

```json
[
  {"namespace":"linux-wallpaperengine","output":"eDP-2","layer":"Background","keyboard_interactivity":"None"},
  {"namespace":"tahoe-wallpaper","output":"eDP-2","layer":"Background","keyboard_interactivity":"None"},
  {"namespace":"tahoe-topbar","output":"eDP-2","layer":"Top","keyboard_interactivity":"None"},
  {"namespace":"tahoe-dynamic-island","output":"eDP-2","layer":"Top","keyboard_interactivity":"None"},
  {"namespace":"tahoe-dock","output":"eDP-2","layer":"Top","keyboard_interactivity":"None"}
]
```

## 视觉检查

- 工作区胶囊宽度约 `220px`，显示 `Workspace 2`，文字没有溢出。
- 胶囊只显示在目标屏 `eDP-2`。
- 自动收起后回到原 resting media 状态。

## 已知问题

- 只有当前单屏 `eDP-2` 环境完成 live 验证；多屏策略仍按服务 `targetScreenName` 只在目标/导航屏显示，后续 T10 需要补多屏基线。
- 顶栏工作区按钮点击路径最终仍走 `Windows.activeWorkspaceName` 变化，因此与 `niri msg action focus-workspace ...` 同源；本次 live 验收使用 niri action 覆盖。
