# Tahoe Dynamic Island 研究结论与串行执行路线图

日期：2026-06-23

## 目标

把 `/home/wwt/Downloads/Tide-island-main` 的灵动岛体验重新实现到当前 Tahoe/niri 项目中，但不直接复用 Tide-island 代码。

本路线图的目标不是“加一个像灵动岛的按钮”，而是让它成为 Tahoe 顶部交互的中心：

- 替换当前顶栏中间的裸时间文字，解决透明背景下看不清的问题。
- 保留 Tahoe 顶栏、控制中心、通知中心、窗口模型、niri layer animation 和 TahoeGlass 的既有架构。
- 用 Tide-island 的交互节奏、胶囊 morph、手势阈值、自动收起时间和内容优先级作为手感基准。
- 严格串行执行，一个任务完整实现、验证、记录后，才能开始下一个任务。

## 研究对象

Tide-island 参考路径：

- `/home/wwt/Downloads/Tide-island-main/shell.qml`
- `/home/wwt/Downloads/Tide-island-main/DynamicIslandWindow.qml`
- `/home/wwt/Downloads/Tide-island-main/qml/island/*`
- `/home/wwt/Downloads/Tide-island-main/qml/controlcenter/*`
- `/home/wwt/Downloads/Tide-island-main/qml/workspace/*`
- `/home/wwt/Downloads/Tide-island-main/backend/*`
- `/home/wwt/Downloads/Tide-island-main/tools/tide-island-setup.cpp`

Tahoe/niri 参考路径：

- `/home/wwt/niri/tahoe-shell/shell.qml`
- `/home/wwt/niri/tahoe-shell/components/TopBar.qml`
- `/home/wwt/niri/tahoe-shell/components/ControlCenter.qml`
- `/home/wwt/niri/tahoe-shell/components/NotificationToast.qml`
- `/home/wwt/niri/tahoe-shell/components/NotificationCenter.qml`
- `/home/wwt/niri/tahoe-shell/services/Controls.qml`
- `/home/wwt/niri/tahoe-shell/services/Notifications.qml`
- `/home/wwt/niri/tahoe-shell/services/Windows.qml`
- `/home/wwt/niri/tahoe-shell/components/TahoeGlass.js`
- `/home/wwt/niri/config/niri/tahoe-phase0.kdl`
- `/home/wwt/.config/niri/tahoe/config.kdl`

## 总结结论

最佳融入方式是：

```text
TopBar 中间裸时间
  -> 替换为常驻 DynamicIslandChip
  -> 点击/右键/手势触发 IslandOverlay
  -> Overlay 使用 Tahoe 现有服务，不引入 Tide 后端
```

不建议把 Tide-island 的 `DynamicIslandWindow.qml` 作为一个完整顶栏 layer 直接搬进来。原因：

- Tide 自己设置 `exclusiveZone: 4 + islandHeight + 3`，而 Tahoe `TopBar` 已经 `exclusiveZone: 34`。同时存在会把窗口布局向下挤两次。
- Tide 绑定 `Quickshell.Hyprland`、Hyprland monitor、Hyprland dispatch、`hyprctl` snapshot；当前项目应该绑定 niri 的 `Windows.qml` 和 `niri msg --json event-stream`。
- Tide 自己有 `IslandBackend` C++ QML 模块，覆盖通知、音量、亮度、电池、Wi-Fi、蓝牙、歌词、配置；Tahoe 已经有同类服务，不能再开第二套状态源。
- Tide 的控制中心和工作区总览是独立实现；Tahoe 已经有 `ControlCenter`、`NotificationCenter`、`WindowOverview`、`TaskSwitcher`，应复用现有组件。

因此应迁移 Tide 的“体验模型”，不迁移 Tide 的“运行时架构”。

## 当前 Tahoe 问题

`TopBar.qml` 当前时间是一个裸 `Text`：

```qml
Text {
    anchors.centerIn: parent
    text: Qt.formatDateTime(root.now, "ddd HH:mm")
    color: root.topTextSecondary
    font.pixelSize: 13
}
```

它位于 `barSurface` 内部中心，但没有自己的高对比背景。顶栏玻璃填充来自 `TahoeGlass.js`：

```js
var FillTopBar = "#14ffffff";
```

这意味着时间文字在浅色窗口、复杂壁纸、透明/模糊背景上经常不可读。这个问题不应靠简单调深顶栏解决，因为会影响整个 Tahoe 顶栏的轻盈感。正确方案是把时间变成高可读的灵动岛胶囊。

## Tide-island 可迁移的体验

### 1. 胶囊尺寸和常态

Tide 默认配置：

```text
islandWidth: 140
islandHeight: 38
islandPositionX: 50
bodyFontSize: 16
titleFontSize: 20
iconFontSize: 18
```

Tahoe 当前顶栏高度是 `34`，内层 barSurface 高度约 `24`。因此不能把 Tide 的 38px 高胶囊直接塞进顶栏内部，否则会破坏当前顶栏高度。

推荐拆成两种几何：

- 顶栏常驻 chip：高度 24px，宽度 116 到 156px，放在 `TopBar` 中心，替换裸时间。
- 灵动岛 overlay：高度 38px 起步，宽度 140px 起步，`exclusiveZone: 0`，视觉上覆盖在顶栏中心，负责完整 Tide 风格 morph。

这样既保留 Tahoe 顶栏布局，也保留 Tide 原版岛的尺寸手感。

### 2. 状态机

Tide 的核心状态：

```text
normal
custom
lyrics
split
long_capsule
expanded
control_center
notification
bluetooth_expanded
overview
```

Tahoe 第一版应收敛为：

```text
resting_time
resting_media
transient_osd
transient_notification
transient_workspace
expanded_media
expanded_summary
```

映射关系：

| Tide 状态 | Tahoe 目标状态 | 第一版处理 |
| --- | --- | --- |
| `normal` | `resting_time` | 常驻时间胶囊 |
| `lyrics` | `resting_media` 或后续 `resting_lyrics` | 第一版先用媒体标题代替歌词 |
| `custom` | `expanded_summary` | 后续显示电池、音量、亮度、工作区 |
| `split` | `transient_osd` | 音量/亮度/静音 |
| `long_capsule` | `transient_workspace` | niri 工作区切换反馈 |
| `expanded` | `expanded_media` | 播放器展开 |
| `notification` | `transient_notification` | 新通知短暂胶囊 |
| `control_center` | 调用 Tahoe `ControlCenter` | 不在岛内重做完整控制中心 |
| `overview` | 调用 Tahoe `WindowOverview` | 不迁移 Hyprland overview |
| `bluetooth_expanded` | 后续可选 | 先不做 |

### 3. 原版手感参数

这些参数是后续实现的硬约束，除非有截图或录屏证明需要调整，否则不能随意改：

| 行为 | Tide 参数 | Tahoe 约束 |
| --- | --- | --- |
| 主胶囊宽高/圆角 morph | `400ms`, `Easing.OutQuint` | Overlay 主胶囊必须使用同等节奏 |
| 胶囊颜色变化 | `280ms`, `Easing.InOutQuad` | 保持偏慢、柔和，不做硬切 |
| 左右滑动 settle | `220ms`, `Easing.OutCubic` | 手势结束后必须有同等回弹/归位 |
| OSD 自动收起 | `1250ms` | 音量/亮度反馈不超过约 1.25s |
| 通知自动收起 | `4200ms` | 通知胶囊约 4.2s，除非用户交互 |
| 蓝牙展开自动收起 | `2500ms` | 后续实现时复用 |
| hover 展开延迟 | `350ms` | 如果启用 hover expand，必须有延迟 |
| hover 收起延迟 | `250ms` | 避免鼠标轻微离开就收起 |
| 通知内容淡入 | `280ms in`, `140ms out` | 通知胶囊内容沿用该节奏 |
| 滑动阈值 | `>= 0.56` 进入右侧，`<= -0.56` 进入左侧 | 手势判定沿用 |
| 从侧态回中阈值 | `0.44` | 避免轻微滑动误触 |
| 拖动垂直容忍 | `24px` | 触控板斜向滑动不应频繁误判 |

动画实现原则：

- 胶囊 morph 由 QML 驱动，不交给 niri layer-open/layer-close。
- `tahoe-dynamic-island` overlay 默认保持 mapped，避免 compositor layer 动画和 QML morph 双重驱动。
- 如果未来为了省资源改成按需 map/unmap，`tahoe-dynamic-island` 不能配置 popin/scale 类 layer animation，只能使用极轻 fade 或不配置 layer animation。
- 动画 token 必须集中到新文件或组件属性，不允许每个子层随手写 duration。

### 4. 输入和手势

Tide 交互：

```text
左键点击: 打开/关闭播放器
右键点击: 打开/关闭控制中心
左滑: 自定义信息
右滑: 歌词
双指横向/纵向滑动: 在时间、歌词、自定义之间切换
Super+Tab: 工作区总览
```

Tahoe 第一版映射：

```text
左键点击 chip: 展开/收起媒体岛；无媒体时打开通知中心或摘要
右键点击 chip: 打开现有 ControlCenter
左滑 chip/overlay: 摘要页，显示电池/音量/亮度/工作区
右滑 chip/overlay: 媒体页，后续接歌词
Super+Tab: 保持现有 Tahoe WindowOverview/TaskSwitcher 逻辑，不绑定 Tide overview
```

输入区域必须使用 `PanelWindow.mask` 或等效 Region，只开放可见胶囊和必要的手势条。禁止让一个全宽透明 layer 吃掉顶部输入。

## Tahoe 集成架构

### 新组件

建议新增：

```text
tahoe-shell/components/DynamicIslandChip.qml
tahoe-shell/components/DynamicIslandOverlay.qml
tahoe-shell/components/DynamicIslandContent.qml
tahoe-shell/components/DynamicIslandMotion.js
tahoe-shell/services/DynamicIsland.qml
```

职责：

- `DynamicIslandChip.qml`
  - 嵌入 `TopBar` 中心。
  - 替换当前裸时间。
  - 常驻 24px 高，确保时间永远可读。
  - 只负责紧凑显示和转发点击/手势。

- `DynamicIslandOverlay.qml`
  - 独立 `PanelWindow`。
  - namespace: `tahoe-dynamic-island`。
  - `exclusiveZone: 0`。
  - `WlrLayer.Top`，不抢 `Overlay` 层，避免压过 Spotlight/Launchpad/Settings。
  - 默认 mapped，内部胶囊根据状态显示/隐藏。
  - 使用 `TahoeGlass.regions` 声明胶囊玻璃区域。

- `DynamicIslandContent.qml`
  - 根据状态渲染时间、OSD、通知、媒体、摘要。
  - 内容层淡入淡出，外层几何 morph 独立。

- `DynamicIslandMotion.js`
  - 保存 Tide 手感参数。
  - 包括 `morphDuration = 400`、`swipeDuration = 220`、`notificationHideMs = 4200` 等。

- `services/DynamicIsland.qml`
  - 统一状态机和事件入口。
  - 订阅 `Controls`、`Battery`、`Notifications`、`Windows`。
  - 向 chip 和 overlay 暴露只读状态。

### 现有组件修改

`TopBar.qml`：

- 删除中心裸时间 `Text`。
- 保留 `now` timer 或把时间 timer 下沉到 `DynamicIsland` 服务。
- 在 `barSurface` 中心放 `DynamicIslandChip`。
- 当前左右 RowLayout 仍保留，不改变左侧菜单、工作区、右侧状态区。

`shell.qml`：

- 实例化 `DynamicIsland` 服务。
- 给 `TopBar` 传入 `dynamicIslandService`。
- 在每个 screen 的 `Variants` 中实例化 `DynamicIslandOverlay`。
- overlay 根据 screen name 只在目标屏或所有屏显示。第一版建议跟随当前导航屏，逻辑复用 `navigationScreenName()`。

`config/niri/tahoe-phase0.kdl` 和 `~/.config/niri/tahoe/config.kdl`：

- 第一版不为 `tahoe-dynamic-island` 添加 layer-open/layer-close。
- 如果加入 glass fallback rule，只允许 `geometry-corner-radius 19` 或 24/34 这类与实际胶囊匹配的规则。
- 不允许 broad `namespace="^quickshell"` 规则。

## 数据源映射

| 需求 | Tide 数据源 | Tahoe 数据源 |
| --- | --- | --- |
| 时间/日期 | `IslandClock` | 新 `DynamicIsland` 服务或 chip 内部 `Timer` |
| 音量/静音 | `SysBackend`/`SystemServices` | `Controls.volume`, `Controls.muted` |
| 亮度 | `SystemServices`/`brightnessctl` | `Controls.brightness`, `Controls.brightnessAvailable` |
| 电池 | `SysBackend`/UPower | `Battery.qml` |
| 通知 | `SystemServices.notificationReceived` | `Notifications.current`, `activeModel`, `historyModel` |
| 媒体 | `Quickshell.Services.Mpris` | `Controls.activePlayer` 或新媒体 helper |
| 工作区 | `Quickshell.Hyprland` | `Windows.activeWorkspace`, `workspaceList`, niri event-stream |
| 控制中心 | Tide `ControlCenterLayer` | Tahoe `ControlCenter` |
| Wi-Fi/蓝牙 | Tide C++ backend + Quickshell Bluetooth | Tahoe `Controls.qml` |
| 歌词 | Tide `lyricsmpris` | 后续单独实现，不进第一阶段 |

## 明确不迁移

第一阶段和第二阶段禁止迁移以下部分：

- `IslandBackend` C++ 模块。
- Hyprland imports、Hyprland dispatch、Hyprland overview。
- Tide 控制中心完整 UI。
- Tide Wi-Fi 连接/蓝牙配对后端。
- Tide setup 工具对 Hyprland 配置的写入。
- Tide systemd service 和安装脚本。
- Tide 的 GPLv3 代码片段。

允许参考行为、状态命名、时长、阈值和布局目标，但实现必须使用 Tahoe 本地代码风格重写。

## 严格串行规则

1. 必须按任务编号顺序执行。
2. 一个任务的实现、验证、截图/日志记录和文档更新全部完成后，才能开始下一个任务。
3. 任何任务验收失败，必须停留在当前任务修复，不得“先做后面的”。
4. 每个任务只允许改该任务声明的文件范围。需要扩大范围时，先更新本文档。
5. 不允许在同一任务里同时重构状态机、视觉、niri KDL 和服务接口，除非任务明确允许。
6. 手感参数不能因为实现方便而改。需要改时必须写明原因，并用截图或录屏对比 Tide 原版。
7. 每个任务完成后必须记录：
   - 修改文件
   - 验证命令
   - 运行时 layer 列表
   - 视觉检查结论
   - 已知问题

## 执行路线图

### T00 文档固化

状态：本文档创建后完成。

目标：

- 保存 Tide 研究结论。
- 定义 Tahoe 集成架构。
- 固化串行规则和原版手感约束。

验收：

- 本文档存在于 `tahoe-shell/docs/`。
- 明确禁止直接搬 Tide 后端和 Hyprland 绑定。
- 明确后续任务顺序。

### T01 替换顶栏中间时间为常驻岛 chip

状态：完成（2026-06-24）

验收记录：`tahoe-shell/docs/dynamic-island-t01-acceptance-2026-06-24.md`

范围：

- `components/TopBar.qml`
- 新增 `components/DynamicIslandChip.qml`
- 可选新增 `components/DynamicIslandMotion.js`

目标：

- 删除当前中心裸时间。
- 顶栏中心显示 24px 高的高可读胶囊。
- 默认内容为当前时间。
- 胶囊背景必须比顶栏更实，确保浅色/复杂背景上可读。

视觉要求：

- 不改变 `TopBar.exclusiveZone: 34`。
- 左右状态区不被挤压、不重叠。
- 1366px 宽度下仍能显示左侧 active app、工作区、右侧状态区。
- 胶囊不要使用 Tide 38px 高度，避免破坏顶栏。

手感要求：

- chip hover/press 使用 Tahoe 微交互，但 duration 应接近 Tide 的柔和节奏，不做硬闪。
- 不引入 overlay，不做通知/OSD。

验收：

- `niri msg --json layers` 中仍只有原有 `tahoe-topbar`，没有新增岛 layer。
- 顶栏中心不再出现裸 `Text` 时间。
- 深浅背景下时间可读。
- 截图记录到后续验收文档或本任务记录。

完成后才能开始 T02。

### T02 新增 DynamicIsland 服务状态机

状态：完成（2026-06-24）

验收记录：`tahoe-shell/docs/dynamic-island-t02-acceptance-2026-06-24.md`

范围：

- 新增 `services/DynamicIsland.qml`
- `shell.qml` 只做服务实例化和传参
- `TopBar.qml` 只接入服务属性

目标：

- 建立 Tahoe 自己的岛状态机。
- 暴露只读状态：
  - `state`
  - `displayText`
  - `secondaryText`
  - `progress`
  - `iconCode`
  - `targetScreenName`
  - `expanded`
- 不渲染 overlay。

第一版状态：

```text
resting_time
resting_media
transient_osd
transient_notification
transient_workspace
expanded_media
expanded_summary
```

验收：

- 服务不崩 shell。
- 无媒体时 chip 显示时间。
- 有 MPRIS 时可切换到 `resting_media`，但不自动展开 overlay。
- 状态切换可通过临时 IPC 或内部函数 smoke 测试。

完成后才能开始 T03。

### T03 新增 DynamicIslandOverlay 基础层

状态：完成（2026-06-24）

验收记录：`tahoe-shell/docs/dynamic-island-t03-acceptance-2026-06-24.md`

范围：

- 新增 `components/DynamicIslandOverlay.qml`
- `components/DynamicIslandMotion.js`（T03 最小范围扩展：集中 overlay morph/progress token）
- `shell.qml`
- 可选 `config/niri/tahoe-phase0.kdl` 只添加 namespace 注释或明确不添加动画规则

目标：

- 增加独立 per-screen overlay layer。
- namespace: `tahoe-dynamic-island`。
- `exclusiveZone: 0`。
- 默认保持 mapped，内部胶囊按状态显示，避免 layer open/close 干扰 QML morph。
- 输入 mask 只覆盖胶囊区域。

视觉要求：

- overlay resting 时与 topbar chip 对齐，视觉上像从 chip 接管。
- overlay 胶囊起步尺寸为 Tide 原版 `140x38`。
- 主胶囊 morph 使用 `400ms OutQuint`。
- radius 使用高度的一半，展开态按 Tide 规则变大。

验收：

- `niri msg --json layers` 可看到 `tahoe-dynamic-island`。
- 没有新增 exclusive zone。
- 点击/拖动顶部其他区域不会被透明 overlay 吃掉。
- 手动触发状态时胶囊 morph 有 Tide 原版的慢弹感。

完成后才能开始 T04。

### T04 通知胶囊

状态：完成（2026-06-24）

验收记录：`tahoe-shell/docs/dynamic-island-t04-acceptance-2026-06-24.md`

范围：

- `services/DynamicIsland.qml`
- `components/DynamicIslandContent.qml`
- `components/DynamicIslandOverlay.qml`
- 不修改 `Notifications.qml` 的核心生命周期，除非先记录原因

目标：

- 新通知到达时，岛进入 `transient_notification`。
- 不替代现有 `NotificationToast` 和 `NotificationCenter`，第一版可以与 toast 共存。
- 读取 `Notifications.current` 或服务新增的轻量事件。

手感要求：

- 通知显示约 `4200ms`。
- 内容淡入 `280ms`，淡出 `140ms`。
- 若当前处于 `expanded_media` 或用户正在交互，通知不得强行打断，按 Tide 的 `blocksTransientSplit` 规则排队或忽略。

验收：

- `notify-send` 能触发岛通知。
- DND 开启时不显示视觉通知，但历史仍更新。
- 通知文本清理 HTML 和实体，不能原样显示 `<b>`、`&amp;` 等。
- 多通知不会造成岛宽度抖动。

完成后才能开始 T05。

### T05 音量/亮度 OSD 胶囊

状态：完成（2026-06-24）

验收记录：`tahoe-shell/docs/dynamic-island-t05-acceptance-2026-06-24.md`

范围：

- `services/DynamicIsland.qml`
- `components/DynamicIslandContent.qml`
- 必要时只读接入 `Controls.qml`

目标：

- 音量变化进入 `transient_osd`。
- 静音显示静音图标。
- 亮度变化进入 `transient_osd`。
- 显示百分比和环形/条形 progress。

手感要求：

- 默认 `1250ms` 自动收起。
- 连续音量变化必须更新同一个胶囊，不反复重新进入。
- progress 变化使用平滑动画，接近 Tide `SmoothedAnimation velocity 1.2 duration 180` 的感觉。

验收：

- 用现有控制中心调音量/亮度时岛能反馈。
- 外部快捷键导致 `Controls` 属性变化时也能反馈。
- 调整期间没有通知/媒体展开抢占。

完成后才能开始 T06。

### T06 媒体展开态

状态：完成（2026-06-24）

验收记录：`tahoe-shell/docs/dynamic-island-t06-acceptance-2026-06-24.md`

范围：

- `components/DynamicIslandContent.qml`
- `services/DynamicIsland.qml`
- 可选新增 `components/DynamicIslandMediaView.qml`

目标：

- 左键点击岛时展开媒体控制。
- 显示封面、标题、艺术家、播放/暂停、上一首/下一首。
- 使用 Tahoe 现有 MPRIS player，不迁移 Tide `IslandMprisController`。

手感要求：

- 展开宽度约 `400px`，高度约 `165px`，参考 Tide。
- 主 morph 仍为 `400ms OutQuint`。
- 内容在几何接近完成时淡入，避免文字被压缩变形。
- 播放状态变化可以短暂自动展开，但必须可配置，第一版默认不强制自动展开。

验收：

- 有播放器时显示真实媒体信息。
- 播放/暂停/上一首/下一首可用。
- 无播放器时点击不崩，回到时间或摘要。
- 展开时通知/OSD 不强行覆盖。

完成后才能开始 T07。

### T07 左右滑动页面

状态：完成（2026-06-24）

验收记录：`tahoe-shell/docs/dynamic-island-t07-acceptance-2026-06-24.md`

范围：

- `DynamicIslandChip.qml`
- `DynamicIslandOverlay.qml`
- `services/DynamicIsland.qml`
- 可选新增 `DynamicIslandSummaryView.qml`

目标：

- 左滑进入摘要页：电池、音量、亮度、工作区。
- 右滑进入媒体页；未来歌词接入后切换为歌词。
- 支持鼠标拖动和触控板 wheel 横向/纵向转换。

手感要求：

- 进入阈值 `0.56`。
- 回中阈值 `0.44`。
- settle 动画 `220ms OutCubic`。
- 垂直容忍 `24px`。
- 滑动中胶囊宽度跟随，松手后 settle。

验收：

- 快速短滑不会误进入。
- 慢速拖动可预览页面。
- 松手后宽度和内容不跳变。
- 触控板双指横向/纵向滑动都能合理工作。

完成后才能开始 T08。

### T08 niri 工作区胶囊

状态：完成（2026-06-24）

验收记录：`tahoe-shell/docs/dynamic-island-t08-acceptance-2026-06-24.md`

范围：

- `services/DynamicIsland.qml`
- `services/Windows.qml` 只读接入，原则上不改服务
- `DynamicIslandContent.qml`

目标：

- niri 工作区切换时显示 `Workspace X` 或 Tahoe 风格工作区名。
- 从当前 resting side 进入和退出，复刻 Tide 的 `long_capsule` 体验。

手感要求：

- 展开宽度约 `220px`。
- 自动收起 `1250ms`。
- 如果当前在摘要/媒体 side，收回时应回到原 resting state。

验收：

- `niri msg action focus-workspace ...` 触发反馈。
- 顶栏工作区按钮点击也触发反馈。
- 多屏场景只在目标屏或导航屏显示，不在所有屏乱闪。

完成后才能开始 T09。

### T09 设置入口和持久化配置

状态：完成（2026-06-25）

验收记录：`tahoe-shell/docs/dynamic-island-t09-acceptance-2026-06-25.md`

范围：

- `services/DesktopSettings.qml` 或新 island 设置状态
- `SettingsPanel` 对应页面
- `services/DynamicIsland.qml`
- `components/TopBar.qml`
- `components/DynamicIslandOverlay.qml`
- `components/DynamicIslandMotion.js`
- `shell.qml`
- 不引入 Tide `UserConfigBackend`

目标：

- 添加是否启用灵动岛。
- 添加是否隐藏旧顶栏时间，默认隐藏。
- 添加左键/右键行为选择。
- 添加是否自动媒体展开。
- 添加 hover expand 开关。

验收：

- 设置持久化到 Tahoe 现有 state 路径。
- 修改后 shell reload 仍保留。
- 禁用灵动岛时顶栏要有可读时间 fallback，不能丢时间。

完成后才能开始 T10。

### T10 动画和视觉验收基线

范围：

- 文档、截图、可能的 Playwright/截图脚本
- 不做功能改动，除非验收暴露 bug

目标：

- 建立灵动岛视觉基线。
- 对比 Tide 原版关键动作。

至少记录：

- resting chip
- overlay resting
- notification transient
- OSD progress
- media expanded
- left/right swipe halfway
- left/right swipe settled
- workspace transient
- dark mode
- light mode
- 1366px 宽
- 宽屏

验收：

- 没有文字溢出。
- 没有透明背景导致不可读。
- 没有 overlay 误吃输入。
- 没有和 `NotificationToast`、`ControlCenter`、`Spotlight`、`Launchpad` 层级冲突。
- `niri msg --json layers` layer 集合符合预期。

完成后才能进入任何后续增强。

## 后续增强池

以下任务必须等 T00 到 T10 全部完成后再考虑：

- 歌词后端，替代 Tide `lyricsmpris` 的重新实现。
- CAVA 音频可视化。
- 蓝牙设备连接展开提示。
- 把通知 toast 合并到灵动岛，或提供二选一模式。
- 让岛触发 Tahoe WindowOverview。
- 更精确的 per-screen focus 和 active output 策略。
- 在 niri KDL 中给 `tahoe-dynamic-island` 增加专用 glass fallback 或 no-op animation profile。

## 验收命令建议

常用命令：

```bash
niri msg --json layers
niri msg --json outputs
niri msg --json workspaces
niri msg --json windows
notify-send "Island test" "Notification body"
qs ipc -p /home/wwt/niri/tahoe-shell call tahoe openWindowOverview
```

部署和检查应沿用项目现有脚本，不得绕过 TahoeGlass guardrails。

## 风险清单

### 风险 1：双重动画

如果 `tahoe-dynamic-island` 同时使用 QML morph 和 niri layer-open popin，会出现缩放叠加、透明闪烁、手感不像 Tide。

规避：

- overlay 默认保持 mapped。
- 不为该 namespace 配置 popin。
- 主胶囊只在 QML 内 morph。

### 风险 2：输入区域挡住顶部

全宽透明 `PanelWindow` 如果 mask 不正确，会吃掉顶栏、窗口标题栏或浏览器顶部输入。

规避：

- 必须使用 mask。
- resting 时只开放胶囊。
- 手势条只在需要 side swipe 时开启。

### 风险 3：和现有通知重复

Tahoe 已有 `NotificationToast` 和 `NotificationCenter`。岛通知如果不做策略，会重复打扰。

规避：

- 第一版允许共存，先验证。
- 后续设置中提供“toast/岛/两者”策略。
- DND 必须统一走 `Notifications.dndEnabled`。

### 风险 4：顶栏布局挤压

把 38px 高 Tide 胶囊直接塞进 34px 高顶栏会破坏布局。

规避：

- 顶栏 chip 用 24px 高。
- 完整 38px 胶囊只在 overlay 中渲染。

### 风险 5：GPL 代码边界

Tide-island 是 GPLv3。当前项目不应复制其代码片段，尤其是大段 QML/C++。

规避：

- 只参考行为、阈值、时长和状态结构。
- 所有实现按 Tahoe 现有代码风格重写。
- 新文件不从 Tide 粘贴。

## 当前推荐起点

下一步只能做 T01：

1. 新建 `DynamicIslandChip.qml`。
2. 替换 `TopBar.qml` 中心裸时间。
3. 保持所有服务和 overlay 不动。
4. 验证顶栏可读性和布局稳定。

T01 通过前，不允许开始 overlay、通知、OSD 或媒体展开。
