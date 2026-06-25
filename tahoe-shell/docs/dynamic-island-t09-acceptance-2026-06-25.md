# Dynamic Island T09 验收记录

日期：2026-06-25

状态：完成

## 修改文件

- `tahoe-shell/services/DesktopSettings.qml`
  - 在现有 `desktop-settings.json` 中持久化灵动岛设置。
  - 新增启用状态、旧顶栏时间、左键/右键动作、自动媒体展开和 hover 展开。
  - 对点击动作做 sanitize，非法值回退到默认。
- `tahoe-shell/components/settings/pages/DynamicIslandPage.qml`
  - 新增设置页，复用 Tahoe settings 控件。
- `tahoe-shell/components/SettingsPanel.qml`
  - 注册 `dynamic-island` 页面、标题、副标题和 StackLayout 索引。
- `tahoe-shell/components/settings/SettingsSidebar.qml`
  - 左侧栏新增“灵动岛”入口。
- `tahoe-shell/components/settings/pages/OverviewPage.qml`
  - 概览页新增灵动岛 summary tile。
- `tahoe-shell/components/settings/SettingsTheme.js`
  - 新增 `dynamic-island` category color。
- `tahoe-shell/services/Search.qml`
  - Spotlight/搜索新增“灵动岛设置”入口。
- `tahoe-shell/services/DynamicIsland.qml`
  - 接入 settings service。
  - 禁用时停止 transient、pending OSD/通知和 swipe，状态回到 `resting_time`。
  - 左键/右键按配置执行：媒体/摘要、通知中心、控制中心或无动作。
  - 自动媒体展开和 hover 展开使用持久化设置。
- `tahoe-shell/components/TopBar.qml`
  - 禁用岛或选择保留旧时间时显示可读时间 fallback chip。
  - fallback chip 可在岛启用时转发点击和 hover 展开。
- `tahoe-shell/components/DynamicIslandOverlay.qml`
  - 禁用时不显示、不开放 mask。
  - 保留旧顶栏时间时，resting overlay 隐藏，只在 transient/expanded/swipe 时出现。
  - hover 展开/收起走集中 motion token。
- `tahoe-shell/components/DynamicIslandChip.qml`
  - 暴露 hover enter/exit 信号。
- `tahoe-shell/components/DynamicIslandMotion.js`
  - 新增 `hoverExpandDelayMs = 350`、`hoverCollapseDelayMs = 250`。
- `tahoe-shell/shell.qml`
  - 给服务和 TopBar 传入 `DesktopSettings`。
  - 岛请求打开控制中心/通知中心时复用现有顶栏 popup。
  - 增加 T09 IPC smoke 函数。
- `tahoe-shell/docs/dynamic-island-research-roadmap-2026-06-23.md`
  - 按串行规则补充 T09 必需范围并标记完成。

## 验证命令

```bash
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I quickshell/build-tahoe/qml_modules tahoe-shell/services/DesktopSettings.qml tahoe-shell/services/DynamicIsland.qml tahoe-shell/components/DynamicIslandChip.qml tahoe-shell/components/DynamicIslandOverlay.qml tahoe-shell/components/TopBar.qml tahoe-shell/components/SettingsPanel.qml tahoe-shell/components/settings/SettingsSidebar.qml tahoe-shell/components/settings/pages/DynamicIslandPage.qml tahoe-shell/components/settings/pages/OverviewPage.qml tahoe-shell/services/Search.qml tahoe-shell/shell.qml
timeout 10s /home/wwt/.local/bin/quickshell --no-color --path tahoe-shell
niri msg --json layers
/home/wwt/.local/bin/qs ipc --pid "$pid" call tahoe dynamicIslandGetSettingsSummary
/home/wwt/.local/bin/qs ipc --pid "$pid" call tahoe dynamicIslandSetEnabled false
/home/wwt/.local/bin/qs ipc --pid "$pid" call tahoe dynamicIslandSetHideTopbarTime false
/home/wwt/.local/bin/qs ipc --pid "$pid" call tahoe dynamicIslandSetLeftClickAction notifications
/home/wwt/.local/bin/qs ipc --pid "$pid" call tahoe dynamicIslandSetRightClickAction summary
/home/wwt/.local/bin/qs ipc --pid "$pid" call tahoe dynamicIslandSetAutoExpandMedia true
/home/wwt/.local/bin/qs ipc --pid "$pid" call tahoe dynamicIslandSetHoverExpand true
```

结果：

- `qmllint` 退出 0；仍有既有 Quickshell 类型元数据、`settingsAdapter` unqualified 和 `modelData` warning。
- `quickshell` smoke 到达 `Configuration Loaded`；`timeout` 退出 124 为预期。
- IPC 初始默认：
  - `enabled=true`
  - `hideTopbarTime=true`
  - `leftClickAction=toggle_media`
  - `rightClickAction=control_center`
  - `autoExpandMedia=false`
  - `hoverExpand=false`
- IPC 修改后重启 repo-path quickshell，读取值保持一致：
  - `enabled=false`
  - `hideTopbarTime=false`
  - `leftClickAction=notifications`
  - `rightClickAction=summary`
  - `autoExpandMedia=true`
  - `hoverExpand=true`
- 禁用态 debug summary：
  - `state=resting_time`
  - `enabled=false`
  - `expanded=false`
  - `pendingNotification=false`
  - `swipeDragging=false`
- 验证结束后已恢复默认设置。

## 运行时 Layer 列表

T09 没有新增 layer；运行时仍为：

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

- 默认启用且隐藏旧时间时，resting overlay 继续作为顶栏中心的可读胶囊。
- 禁用灵动岛时，TopBar 中心显示 `DynamicIslandChip` 时间 fallback，不丢时间。
- 选择保留旧顶栏时间时，resting overlay 隐藏，transient/expanded 状态仍由 overlay 显示。
- 设置页使用现有 Tahoe 控件，窄宽度下 segmented control 不撑出父容器。

## 已知问题

- T09 只增加配置入口和行为切换；没有新增通知 toast/岛二选一策略。
- 右键打开控制中心、左键打开通知中心由 shell 使用岛中心 anchor 复用现有 popup，视觉细节在 T10 基线记录。
