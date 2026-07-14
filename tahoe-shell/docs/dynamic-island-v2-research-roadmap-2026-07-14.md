# Tahoe Dynamic Island V2 深度研究报告与严格串行执行路线图

日期：2026-07-14

项目根目录：/home/wwt/niri

新版 Tide 参考目录：/home/wwt/Downloads/Tide-island-main (1)/Tide-island-main

旧版 Tide 参考目录：/home/wwt/Downloads/Tide-island-main

状态：研究完成，尚未开始实现

本文定位：Dynamic Island V2 的唯一研究结论、架构约束、UI 规范和执行顺序 source of truth。

---

## 0. 文档目的

本文解决以下问题：

1. 明确新版 Tide 对 niri 的真实支持范围，避免误判为可以整体搬运。
2. 明确当前 Tahoe 灵动岛的架构优点、功能缺陷、状态竞争和视觉债务。
3. 给出不创造平行接口、不复制第二套服务的目标架构。
4. 给出完整 UI 翻新规范，而不是在旧布局上换颜色。
5. 把后续工作拆成严格串行任务。
6. 规定每个任务必须经过独立子代理只读审查。
7. 规定每个任务只有在 commit 和 push 成功后才算完成。
8. 规定任何任务都不能以破坏当前功能为代价推进。

本文不是实现提交。后续实现必须从 T00 开始，严格按任务编号执行。

---

## 1. 总结结论

### 1.1 核心结论

本次工作不应再次把 Tide 的 DynamicIslandWindow.qml 搬入 Tahoe。

正确路线是：

- 保留 Tahoe 已有的 Windows、Controls、Notifications、Battery、DesktopSettings 和 TahoeGlass。
- 只吸收 Tide 中被证明有价值的交互语义。
- 在现有公开接口内部重构状态机和 UI。
- 不增加第二条 niri event stream。
- 不增加第二套通知服务。
- 不增加第二套 MPRIS 选择器。
- 不增加第二套主题、材质、动效 profile 或部署脚本。
- 不保留旧 UI 与新 UI 两套长期运行路径。

新版 Tide 的 niri 支持是一个窄适配层，不是完整 niri 桌面模型。它主要完成：

- 连接 NIRI_SOCKET。
- 发送 EventStream 请求。
- 维护 focused output。
- 维护每个输出的 active workspace index。
- 处理 WorkspacesChanged 和 WorkspaceActivated。
- 在 niri 下禁用 Tide 自己的 Hyprland 工作区总览。

当前 Tahoe 的 Windows.qml 已拥有更完整的窗口、焦点、布局、紧急状态和工作区模型。因此应补齐当前 reducer，而不是引入 Tide 的 CompositorBackend。

### 1.2 UI 结论

当前 UI 不能通过微调修复，必须重写视图层。

需要保留：

- PanelWindow 常驻映射策略。
- Top layer。
- exclusiveZone: 0。
- 精确输入 Region。
- 单 TahoeGlass region。
- 现有服务数据源。

需要重做：

- 所有状态的内容层。
- 状态尺寸和圆角体系。
- 顶栏与灵动岛的视觉关系。
- 通知、OSD、媒体和空闲态的信息层级。
- 动画时序。
- 多屏展示语义。

推荐视觉方向是“深色焦点玻璃”：

- 不是 Tide 的纯黑胶囊。
- 不是控制中心的浅色玻璃缩小版。
- 使用中性深色、高对比文字和有限强调色。
- 降低 QML 填充不透明度，让现有 pill 玻璃材质真正可见。
- 空闲态小而稳定，展开态有明确任务，不展示重复系统信息。

### 1.3 产品结论

灵动岛应展示“正在发生的事情”，而不是成为第二个控制中心。

适合进入灵动岛：

- 正在播放的媒体。
- 计时器。
- 录屏、录音、麦克风或摄像头占用。
- 用户主动开始的下载、传输或连接过程。
- 时间敏感的通知。
- 音量和亮度 OSD。
- 蓝牙设备连接成功或失败。

不适合作为默认展开内容：

- 静态电池概览。
- 已经在顶栏显示的工作区。
- 与控制中心完全重复的音量和亮度摘要。
- 为了填满面板而存在的四宫格状态页。

因此 V2 核心版本应删除当前 expanded_summary 的默认产品定位。

---

## 2. 不可违反的执行规则

### 2.1 严格串行

任何时刻只能有一个任务处于 active 状态。

任务状态只能按以下顺序变化：

pending -> active -> testing -> review -> ready-to-commit -> pushed -> complete

禁止：

- 同时开始两个任务。
- 当前任务还在测试时提前写下一个任务。
- 当前任务审查未通过时开始下一个任务。
- 当前任务已经 commit 但尚未 push 时开始下一个任务。
- 将多个任务压缩进一个大提交。

### 2.2 完成定义

一个任务只有同时满足以下条件才算 complete：

1. 任务范围内的实现完成。
2. 任务明确要求的静态测试全部通过。
3. 任务明确要求的 QML 测试全部通过。
4. 任务明确要求的实机或截图验收完成。
5. 最终 staged diff 只包含任务精确 allowlist。
6. staged binary diff 已计算稳定 SHA-256。
7. 独立子代理针对该 SHA-256 对应的最终 staged diff 完成只读审查。
8. reviewer 给出 APPROVE。
9. 所有 REQUEST_CHANGES 已修复并开启新的独立审查轮次。
10. 修复后重新运行该任务全部测试。
11. 提交前 staged SHA-256 与获批 SHA-256 完全一致。
12. 任务提交已经创建，且 commit patch SHA-256 与获批 staged SHA-256 一致。
13. 提交已经成功 push 到当前跟踪分支。
14. 本地 HEAD 与远端跟踪分支提交一致。

任意一项未满足，任务仍然是 active，不得开始下一项。

### 2.3 每任务独立审查

每个任务完成实现和测试后，必须启动一个全新的独立子代理进行只读审查。

审查代理要求：

- 不参与该任务实现。
- 不修改任何文件。
- 不接受“代码大概正确”作为结论。
- 首先检查行为回归、状态竞争、多屏问题和测试缺口。
- 然后检查反腐化约束。
- 最后检查视觉、性能、可访问性和维护性。
- 输出必须包含文件和行号。
- 发现按 Critical、High、Medium、Low 分类。
- 明确给出 APPROVE 或 REQUEST_CHANGES。
- 核对实现者声明的 staged SHA-256。
- 只审查最终 staged diff，不审查会在之后继续变化的 working diff。

为了保持独立性，审查代理应使用新的 agent 实例，不复用前一任务的 reviewer。

如果 reviewer 给出 REQUEST_CHANGES，或审查后 index/代码发生任何变化：

- 重新运行该任务所有测试。
- 重新按精确 allowlist 暂存。
- 重新计算 staged SHA-256。
- 启动另一个新的独立审查代理。
- 旧 verdict 和旧 SHA-256 立即失效。
- 只有新 reviewer 针对新 SHA-256 给出 APPROVE 后才允许提交。

### 2.4 每任务 commit 和 push

每个任务必须形成一个独立、可回滚的提交。

要求：

- 提交只包含该任务 allowlist 中的文件。
- 禁止 git add . 和 git add -A。
- 不夹带格式化全仓库、依赖更新或无关清理。
- 不提交用户或其他进程产生的修改。
- 提交信息使用任务编号。
- commit body 记录测试和审查证据。
- 正常 push，禁止 force push。
- push 被拒绝时任务不算完成。
- push 前远端 tip 必须仍等于本任务 base SHA。
- push 被拒绝后不得自行 pull、rebase、merge 或改写历史；必须先报告准确状态并取得用户授权。
- 如果用户授权后提交内容或父提交发生变化，必须重新测试、重新暂存、重新计算 SHA-256 并开启新的审查轮次。

推荐提交格式：

~~~text
<type>(dynamic-island): TNN <short description>

Task: TNN
Tests: <commands and result>
Independent-Review: <fresh agent id>
Review-Verdict: APPROVE
Review-Round: <number>
Reviewed-Staged-SHA256: <sha256>
Runtime-Check: <result or not-required>
~~~

推荐推送后核验：

~~~bash
git rev-parse HEAD
git rev-parse @{upstream}
git status --short --branch
~~~

### 2.5 回滚规则

- 每个任务必须可以通过单独 git revert 回滚。
- 禁止通过 git reset --hard 回滚已推送任务。
- 禁止把多个任务 squash 后覆盖远端历史。
- 回滚一个任务后，所有依赖该任务的后续任务必须重新评估。

---

## 3. 研究范围和证据

### 3.1 已读取的当前 Tahoe 核心

- tahoe-shell/services/DynamicIsland.qml
- tahoe-shell/services/Windows.qml
- tahoe-shell/services/Controls.qml
- tahoe-shell/services/Notifications.qml
- tahoe-shell/services/Battery.qml
- tahoe-shell/services/DesktopSettings.qml
- tahoe-shell/components/DynamicIslandOverlay.qml
- tahoe-shell/components/DynamicIslandContent.qml
- tahoe-shell/components/DynamicIslandMediaView.qml
- tahoe-shell/components/DynamicIslandSummaryView.qml
- tahoe-shell/components/DynamicIslandChip.qml
- tahoe-shell/components/DynamicIslandMotion.js
- tahoe-shell/components/TopBar.qml
- tahoe-shell/components/NotificationToast.qml
- tahoe-shell/components/NotificationCenter.qml
- tahoe-shell/components/ControlCenter.qml
- tahoe-shell/components/GlassPanel.qml
- tahoe-shell/components/TahoeGlass.js
- tahoe-shell/components/Motion.js
- tahoe-shell/components/settings/SettingsTheme.js
- tahoe-shell/shell.qml
- 相关 Python 和 QML 测试。

关键规模：

- DynamicIsland.qml：约 1369 行。
- DynamicIslandOverlay.qml：约 532 行。
- DynamicIslandContent.qml：约 411 行。
- DynamicIslandMediaView.qml：约 474 行。
- DynamicIslandSummaryView.qml：约 174 行。

### 3.2 已读取的 Tide 核心

- DynamicIslandWindow.qml
- backend/CompositorBackend.cpp
- backend/CompositorBackend.h
- qml/island/CompositorWorkspaceTracker.qml
- qml/island/IslandMprisController.qml
- qml/island/NotificationLayer.qml
- qml/island/OsdLayer.qml
- qml/island/ExpandedPlayerLayer.qml
- qml/island/SwipeCustomInfoLayer.qml
- qml/island/SwipeLyricsLayer.qml
- qml/island/IslandRootGestureArea.qml
- qml/island/IslandSystemState.qml
- Timer、Bluetooth、Wallpaper、Overview 和快捷键相关代码。

关键规模：

- 新版 DynamicIslandWindow.qml：约 2545 行。
- CompositorBackend：约 348 行。
- 新版岛相关 QML 总计约 6961 行。

### 3.3 版本差异

旧版 Tide 包版本约为 1.0.11，新版本地源码包版本约为 1.0.21。

新版相比旧版增加了：

- niri compositor backend。
- 独立配置程序。
- 计时器。
- 壁纸选择器。
- 通知展开。
- 自动隐藏。
- 歌词和更多侧滑模块。
- 蓝牙和录制状态。

这些新增功能并不意味着全部适合 Tahoe。

### 3.4 实机证据

审计时运行环境：

- niri 正在运行。
- Quickshell 使用 ~/.config/quickshell/tahoe。
- 输出为 eDP-2。
- 逻辑分辨率 2048x1280。
- scale 1.25。
- 顶栏为浅色 Tahoe 玻璃。
- 灵动岛为接近不透明的深色胶囊。

通过现有 IPC 采集了：

- resting time。
- expanded summary。
- OSD。
- workspace transient。
- control center。
- notification center。

截图仅保存在 /tmp，没有写入仓库。

### 3.5 测试证据

独立路线图审查时执行的当前完整 Tahoe 测试结果：

- 453 passed。
- 143 subtests passed。
- 总耗时约 20 秒。

当前灵动岛相关测试执行结果：

- 106 passed。
- 13 subtests passed。
- 总耗时约 5.27 秒。

覆盖范围包括：

- 通知稳定身份。
- 通知 replacement。
- 手动通知 FIFO。
- 媒体 hit testing。
- 媒体 interaction lifecycle。
- 点击与滑动意图。
- visualizer 所有权。
- 音量事件去重。

未覆盖：

- 通知与 OSD/工作区之间的优先级。
- swipe settle 每一帧的目标宽度。
- 事件发生时的输出捕获。
- 焦点变化时岛是否跨屏跳动。
- 非目标输出的通知行为。
- 主题、圆角和视觉截图矩阵。
- source/runtime 部署一致性。

Tide 本地编译测试：

- compositor_backend：5 个 case 通过。
- tide_island_shortcut_config：9 个 case 通过。

Tide UI 没有对应的系统化 QML 行为测试。

### 3.6 来源与证据边界

本报告的直接证据来自：

- 当前仓库的 Tahoe shell 源码、测试、运行时截图和 Quickshell 日志。
- 本地 Tide 源码：/home/wwt/Downloads/Tide-island-main (1)/Tide-island-main。
- Tide 上游入口：https://github.com/enhaoswen/Tide-island 。
- Tide 本地 README、LICENSE、niri backend、QML scene 和配置生成代码。

交互与可访问性只参考公开平台原则，不复制视觉实现：

- Apple Live Activities：https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities 。
- Android live update notifications：https://developer.android.com/develop/ui/views/notifications/live-update 。
- GNOME notification guidelines：https://developer.gnome.org/hig/patterns/feedback/notifications.html 。

T00 必须把实际使用的 Tide URL、无法取得的 commit、确定性源码树 SHA256、LICENSE SHA256 和访问日期写入基线。URL 不能替代本地源码哈希；无法确认来源或许可证边界时不得开始实现。

---

## 4. 当前架构分析

### 4.1 当前拓扑

当前结构大致为：

~~~text
shell.qml
  -> one global DynamicIsland service/controller
  -> one TopBar per screen
  -> one DynamicIslandOverlay per screen

DynamicIsland.qml
  -> Controls
  -> Notifications
  -> Battery
  -> Windows
  -> DesktopSettings

DynamicIslandOverlay.qml
  -> one GlassPanel
  -> DynamicIslandContent
  -> media/summary/transient scenes
~~~

这个大方向是正确的：

- 全局数据和状态只维护一次。
- 每个输出仅有一个展示 surface。
- 没有为每个输出复制通知、媒体或 niri 服务。

### 4.2 必须保留的优点

1. Notifications.qml 是真正的 org.freedesktop.Notifications owner。
2. 通知支持稳定 ID、replacement、DND、action、图标和 FIFO。
3. Windows.qml 已经有丰富的 niri window model。
4. Controls.qml 已经统一管理音量、亮度和 MPRIS。
5. Overlay 常驻映射，避免 layer-open 动画与 QML morph 双重驱动。
6. exclusiveZone: 0，不改变工作区可用区域。
7. 输入 mask 精确跟随岛。
8. TahoeGlass 使用单 region，符合材质治理预算。
9. 媒体控制已有按压、释放、取消和销毁清理。
10. IPC 和设置已有用户兼容面。

### 4.3 当前根本缺陷

DynamicIsland.qml 同时承担：

- 数据适配。
- 状态推导。
- 强制状态。
- transient queue。
- 通知身份。
- OSD 去重。
- 手势。
- hover。
- 输出选择。
- 媒体命令。
- timer。
- debug summary。

这使一个视觉组件的任何新状态都会修改全局可变状态，导致竞争和恢复逻辑不断增加。

---

## 5. Tide 新版 niri 支持研究

### 5.1 实际支持范围

CompositorBackend 直接打开 NIRI_SOCKET，写入 EventStream 请求。

它主要处理：

- WorkspacesChanged。
- WorkspaceActivated。
- focused output。
- active workspace index per output。

CompositorWorkspaceTracker 再把这些数据映射到每个岛窗口。

它没有提供：

- Tahoe 当前级别的窗口生命周期模型。
- 完整窗口布局状态。
- 窗口紧急状态。
- 工作区 active window 追踪。
- Tahoe WindowOverview。
- Tahoe TaskSwitcher。

### 5.2 可吸收内容

- WorkspaceActivated 的增量更新语义。
- 每输出 active workspace index。
- focused output 的显式维护。
- niri 和 Hyprland backend 的条件加载思想。
- niri 下不复制 Hyprland overview 的边界意识。

### 5.3 禁止搬入内容

- Tide CompositorBackend 生产实例。
- 第二条 NIRI_SOCKET 连接。
- Tide HyprlandWorkspaceTracker。
- Tide overview 和窗口缩略图体系。
- Tide 快捷键配置写入器。
- Tide 自己的控制中心。

### 5.4 Tide 中值得重写的体验

- 显式 swipe settle target width。
- 通知自适应宽高。
- 长通知点击展开。
- 记忆上次 active MPRIS D-Bus name。
- 可配置侧滑活动。
- Timer 紧凑态和展开态。
- 录屏指示。
- 蓝牙连接 transient。
- 按需 Loader。

### 5.5 Tide 中不能复制的问题

- showNotificationAll 向所有输出广播。
- 每个输出实例化重服务和控制器。
- dbus-monitor 通知镜像没有稳定 ID。
- 通知可能改变 exclusive zone。
- DynamicIslandWindow 隐式高度长期偏大。
- timer bubble 输入 Region 不完整。
- 假频谱和大量硬编码颜色。
- 大量负 letter spacing。
- 重复 Wi-Fi、Bluetooth、控制中心和壁纸服务。

---

## 6. 已定位的功能缺陷

### 6.1 source/runtime 漂移

审计时仓库与 ~/.config/quickshell/tahoe 存在约 48 项差异。

至少以下灵动岛文件不同：

- services/DynamicIsland.qml
- components/DynamicIslandContent.qml
- components/DynamicIslandMediaView.qml
- components/DynamicIslandOverlay.qml
- components/TopBar.qml

这会造成：

- 仓库测试已通过，但实际桌面仍运行旧逻辑。
- 已修复 bug 在实机继续出现。
- 截图和源代码无法对应。

必须优先修复部署可追踪性，不能继续依靠手工 rsync。

现有 scripts/arch-update.sh 是唯一允许的正常部署入口。不得新增平行 deploy-dynamic-island.sh。

### 6.2 swipe settle 两阶段跳变

当前 swipePreviewWidth 在 swipeSettling 时回到 resting width。

resolveSwipe 又先把 swipeProgress 清零，再设置 expanded state。

Overlay 的宽度优先读取 swipePreviewWidth。

结果是：

1. 用户完成滑动。
2. 岛先向 140/190px 收缩。
3. settle timer 结束。
4. 岛再向 360/400px 展开。

应改为一次显式 settle：

- gesture 决定 target state。
- 同时计算 target width。
- settle 全程保持该目标。
- settle 完成后只清理 gesture phase，不再二次改变几何目标。

### 6.3 transient 优先级缺失

当前 blocksTransientOsd 和 blocksTransientWorkspace 只检查 expanded 或 userInteracting。

因此：

- OSD 可以覆盖通知。
- workspace 可以覆盖通知。
- pending notification 与 pending OSD 的恢复顺序可以互相覆盖。
- displayingNotificationId 可能滞留。

必须引入明确优先级和恢复规则。

### 6.4 输出没有在事件发生时捕获

targetScreenName 根据当前焦点窗口或 active workspace 动态计算。

通知显示 4.2 秒期间，如果焦点切换到另一输出，岛可能跳屏。

正确语义：

- 事件创建时捕获 output。
- transient 生命周期内 owner output 不变。
- 用户主动点击某个输出时，该输出成为展开会话 owner。
- 会话关闭后恢复自动 owner。

### 6.5 niri 工作区状态可能过期

Windows.qml 处理 WorkspacesChanged，但没有处理 WorkspaceActivated。

niri 的 WorkspacesChanged 是结构变化，不保证每次激活都全量重发。

因此 isActive/isFocused 和 activeWorkspaceName 可能在切换后过期。

### 6.6 MPRIS 选择不稳定

Controls.qml 当前倾向选择：

1. playing player。
2. 第一项 paused 且有 track 的 player。
3. 第一项可用 player。

如果 D-Bus model 重排，岛可能切换到另一个播放器。

应在 Controls 内部记忆 active player D-Bus name，并验证：

- player 仍存在。
- track metadata 有效。
- 控制能力有效。
- playing player 的优先级。

不得新增 IslandMprisController 生产服务。

### 6.7 多屏通知缺口

NotificationToast 在启用灵动岛时全局抑制。

灵动岛通知只显示在 target output。

真实缺口是：

- 非 owner 输出不会显示岛 transient。
- NotificationToast 又被全局抑制，因此不会显示 transient toast。
- TopBar 仍保留通知历史徽标和 NotificationCenter 入口，并非所有通知入口都消失。
- dynamicIslandHideTopbarTime=true 时，现有 activeForScreen 逻辑可能让非 owner 输出中心 base clock 为空。

V2 必须明确：

- 通知只在 owner output 显示。
- 非 owner output 保留 base clock、通知徽标和 NotificationCenter 入口。
- 不在每个输出复制同一 notification transient。
- island disabled 时恢复 NotificationToast。

### 6.8 brightness 0 边界

当前亮度 baseline 把非正数映射为 1.0。

handleBrightnessChange 又忽略 brightness <= 0。

降到最低亮度时可能没有 OSD 或 baseline 错误。

### 6.9 性能浪费

- 每个输出常驻实例化全部内容 scene。
- summary 和 media 组件长期存在。
- 假 visualizer 有定时器。
- 高不透明填充遮住玻璃，却仍支付 blur 成本。

V2 必须使用 Loader，只实例化当前 scene 和过渡所需的前一 scene。

---

## 7. 当前视觉问题研究

### 7.1 历史设计债务

旧路线图把 Tide 的以下参数视为硬约束：

- 140x38 resting。
- 400ms 左右 morph。
- 220ms swipe settle。
- 纯深色胶囊。
- expanded_summary 对应 Tide custom info。

这些约束没有根据当前 Tahoe 顶栏、字体、1.25 scale 和多屏环境重新验证。

旧路线图 T10 要求：

- dark mode。
- light mode。
- 1366px。
- 宽屏。
- 通知。
- OSD。
- 媒体。
- 滑动中间帧。

仓库中只有 T01 到 T09 验收，没有 T10 视觉验收记录。

因此当前 UI 是功能移植完成后的中间结果，不是经过完整设计验收的最终结果。

### 7.2 顶栏与岛不属于同一视觉层级

当前顶栏：

- 浅色。
- 半透明。
- 连续。
- 有壁纸色彩。
- 32px 左右内层高度。

当前岛：

- 接近纯黑。
- 94% 到 95% 不透明。
- resting 高 38px。
- y 为 0。
- 覆盖顶栏上边缘。

结果不像“顶栏焦点组件”，更像后贴上去的黑色补丁。

### 7.3 几何问题

当前固定尺寸：

- time：140x38。
- media compact：190x38。
- OSD/workspace：220x44/38。
- notification：320x56。
- media expanded：400x165。
- summary expanded：360x132。

所有状态 radius = height / 2。

因此：

- 400x165 媒体页 radius 为 82.5。
- 360x132 summary radius 为 66。
- 展开态像大椭圆，不像精致面板。
- 内部内容与外轮廓之间产生大量无意义空白。

### 7.4 内容层级问题

expanded_summary 四项权重完全相同：

- 电池。
- 音量。
- 亮度。
- 工作区。

但当前屏幕顶栏已经显示：

- 电池。
- 工作区。
- 状态图标。

控制中心已经显示：

- 音量。
- 亮度。
- 网络。
- 媒体。

summary 没有提供新信息或更高效操作。

### 7.5 OSD 重复编码

当前 OSD 同时显示：

- 百分比文本。
- 环形进度。

两者表达同一数值，且环形尺寸过小。

更合理的桌面 OSD：

- 图标说明类型。
- 水平进度说明相对量。
- 右侧数值说明精确量。

### 7.6 通知缺少来源身份

当前岛通知使用通用 bell 图标。

它没有充分利用 Notifications.qml 已经拥有的：

- appName。
- appIcon。
- actions。
- urgency。
- default action。

结果通知看起来像系统占位文本，而不是应用事件。

### 7.7 媒体页仍是 Tide 第一版布局

当前媒体页基本沿用：

- 左上专辑图。
- 中间标题和作者。
- 右上五根紫色条。
- 中部 timeline。
- 底部上一首/播放/下一首。

主要问题：

- 五根紫色条是假数据。
- Canvas 手绘按钮与 TahoeSymbol 不一致。
- 播放键没有主次层级。
- 专辑图只有 56px，视觉锚点偏弱。
- 400x165 的大椭圆削弱了内容排版。

---

## 8. V2 产品与 UI 设计原则

### 8.1 一眼可读

紧凑态只显示一个首要状态。

展开态才显示：

- 上下文。
- 进度。
- 快速操作。

禁止把完整面板硬塞进紧凑态。

### 8.2 活动优先

优先级来源于用户当前活动，而不是数据是否容易获得。

默认活动优先级：

1. 用户正在操作的展开会话。
2. critical notification。
3. 普通通知。
4. timer completion。
5. volume/brightness OSD。
6. workspace feedback。
7. media preview。
8. resting clock。

### 8.3 不重复已有 UI

- 不在岛里复制完整控制中心。
- 不在岛里复制通知中心。
- 不在岛里复制 WindowOverview。
- 不在岛里复制顶栏工作区列表。
- 不在岛里复制 Wi-Fi/Bluetooth 设置面板。

### 8.4 单一焦点

每个状态必须有一个视觉焦点：

- clock：时间。
- media：专辑图和标题。
- notification：应用图标和标题。
- OSD：进度。
- timer：剩余时间。
- recording：红色状态点和持续时间。

### 8.5 中性表面，语义色点缀

- 表面保持中性深灰。
- 强调色来自 SettingsTheme.accent。
- battery 只在低电量或充电时使用语义色。
- recording 使用系统红。
- critical notification 使用注意色。
- 不使用固定紫色作为媒体默认色。

---

## 9. 推荐视觉系统

以下值是首轮静态原型基线，不是未经截图验证的永久硬编码。

### 9.1 材质

继续使用现有 pill material。

禁止：

- 新增 island material。
- 修改全局 pill profile 来只服务灵动岛。
- 创建第二套 TahoeGlass 配置。

初始 QML fill 建议：

| 状态 | 建议 fill | 说明 |
| --- | --- | --- |
| compact | #cc10141a | 约 80% 深色，让玻璃可见 |
| transient | #d610141a | 约 84% 深色，提高短文本稳定性 |
| expanded | #df10141a | 约 87% 深色，保证正文和控制可读 |

描边建议：

- 1px。
- #24ffffff 到 #30ffffff。
- 使用现有 compositor edge highlight，不额外堆多层阴影。

### 9.2 文本

使用系统 Noto Sans CJK SC，不引入专用 UI 字体。

| 用途 | 字号 | 字重 |
| --- | --- | --- |
| compact primary | 13 | DemiBold |
| compact secondary | 11 | Normal |
| transient primary | 14 | DemiBold |
| transient secondary | 11-12 | Normal |
| expanded title | 16 | DemiBold |
| expanded metadata | 12 | Normal |
| timer value | 28-32 | DemiBold |
| progress time | 10-11 | Normal |

规则：

- letter spacing 固定 0。
- 禁止负 letter spacing。
- 中文和英文都必须截图。
- 主标题最多一行。
- 通知正文紧凑态最多一行，展开态最多三行后滚动或省略。

### 9.3 圆角

| 状态 | radius |
| --- | --- |
| compact 32px 高 | 16 |
| compact media 36px 高 | 18 |
| OSD 44px 高 | 22 |
| notification 60-80px 高 | 22-26 |
| expanded | 28-32 |

禁止展开态继续使用 height / 2。

### 9.4 几何

| 状态 | 建议逻辑尺寸 | 说明 |
| --- | --- | --- |
| resting clock | 112-136 x 32 | 内容测量宽度 |
| compact media | 200-224 x 36 | 专辑图、标题、状态 |
| OSD | 220-240 x 44 | 图标、bar、数值 |
| workspace optional | 140-168 x 36 | 仅必要时 |
| notification compact | 300-420 x 60-80 | 自适应宽高 |
| media expanded | 404-432 x 160-172 | 固定上限，窄屏收缩 |
| notification expanded | 380-440 x 96-176 | 内容驱动 |
| timer expanded | 340-380 x 136-152 | 后续活动 |

位置建议：

- compact y = 4，与 TopBar 内层对齐。
- expanded 顶边保持稳定，不在变形过程中上下跳动。
- width 必须限制为 screenWidth - 32。
- 1366px 逻辑宽度必须单独验收。

### 9.5 色彩

基础：

- primary text：#f7f8fa。
- secondary text：#aeb6c2。
- muted text：#7f8996。
- progress track：#30ffffff。
- neutral control fill：#20ffffff。

强调：

- 使用 SettingsTheme.accent(darkMode, accentId)。
- 不在组件内硬编码 #b56cff。
- critical 使用 SettingsTheme.statusAttention。

---

## 10. 各场景 UI 规格

### 10.1 Resting Clock

布局：

- leading：本地化星期，例如“周二”。
- trailing：24 小时时间，例如“22:31”。
- 两段之间 8-10px。
- 时间为主，星期为 secondary。

规则：

- 使用系统 locale。
- 不硬编码英文 Tue。
- 没有活动时不自动展开 summary。
- 左键和右键继续使用现有可配置 action。

### 10.2 Compact Media

布局：

- 22x22 专辑图。
- 8px 间距。
- 单行曲名。
- trailing 为播放/暂停状态图标。
- 可选 2px 底部播放进度。

规则：

- 不显示作者，避免密度过高。
- 没有真实 CAVA 数据时不显示假频谱。
- 暂停一段时间后可根据现有产品设置恢复 clock。
- 曲名最大宽度必须受控，不能推动顶栏布局。

### 10.3 OSD

布局：

- 20px 音量或亮度图标。
- 112-128px 水平进度条。
- 36-42px 右对齐数值。

状态：

- volume。
- muted。
- brightness。

规则：

- 删除环形进度。
- muted 显示“静音”，进度为 0。
- 亮度 0 是合法值。
- 高频连续更新只修改 bar 和数值，不重复执行内容进场。

### 10.4 Notification Compact

布局：

- 30-32px 应用图标。
- 应用名或来源作为 secondary metadata。
- 标题作为 primary。
- 正文最多一行。
- critical 可增加 2px 语义色边缘或小状态点。

规则：

- 不使用通用 bell 代替已有 app icon。
- 单行内容使用约 300px。
- 长内容自适应到 420px 和两行。
- 点击通知主体执行 notification default action。
- 有 overflow 时在 trailing 提供独立 expand chevron；只有该按钮切换 expanded，并阻止事件传播到主体。
- expand chevron 的 hit target 至少 40px，首选 44px。
- 水平滑动执行 dismiss。
- DND 下不展示，但保留历史。

### 10.5 Notification Expanded

布局：

- 顶部应用图标、应用名和时间。
- 中部标题与最多三行正文。
- 底部最多三个 action。

规则：

- action 直接使用 Notifications.qml 的现有模型。
- 不建立第二份 notification 对象。
- 默认 action 不再重复显示“打开”按钮。
- 超长正文使用受限 Flickable，最大高度 176px。

### 10.6 Expanded Media

布局：

- 左上 64x64 专辑图，radius 12。
- 右侧标题和作者。
- timeline 横跨内容区。
- elapsed 和 duration 使用 10-11px。
- 底部上一首、播放/暂停、下一首。

控制层级：

- 播放/暂停：36px 实心 accent 圆形按钮。
- 上一首/下一首：32px 透明按钮。
- hit target 保持至少 44px。

规则：

- 使用 TahoeSymbol。
- 删除 Canvas 手绘媒体图标。
- 只有后端支持 seek 时 timeline 才可交互。
- 专辑图加载失败时使用统一 music symbol。
- 不使用整张专辑图作为背景，避免噪声和额外 GPU 成本。

### 10.7 Workspace Feedback

默认策略：

- 顶栏工作区可见时不显示岛 workspace transient。
- 顶栏隐藏、全屏特殊模式或用户明确启用时才显示。

布局：

- 当前 workspace index/name。
- 可选三个位置点。
- 动画方向与 niri 激活方向一致。

### 10.8 Timer

Timer 不是核心重构前置条件，应在核心稳定后实现。

compact：

- timer icon。
- 剩余时间。
- 细进度环或底部进度线，二选一。

expanded：

- 大号剩余时间。
- 当前状态。
- 暂停/继续。
- 取消。

不得复制 Tide Timer 后端；应使用 Tahoe 单一 timer state owner。

### 10.9 Recording Indicator

compact：

- 4-6px 红点。
- 持续时间。

规则：

- 脉冲非常轻。
- reduced motion 下固定红点。
- 录制结束后立即恢复前一稳定状态。

---

## 11. 动效规范

### 11.1 几何

- compact -> transient：220-260ms。
- compact -> expanded：260-300ms。
- expanded -> compact：220-260ms。
- easing 只能由 DynamicIslandMotion.js 复用 Motion.js 的受治理 token；scene/callsite 不直接写 OutCubic 等常量。
- TahoeGlass region 的 x/y/width/height/radius 禁止 SpringAnimation。

### 11.2 内容

- 旧内容退出：100-120ms。
- 新内容进入：160-180ms。
- 位移不超过 6px。
- 不再统一从 scale 0.9 放大到 1。
- 相同语义元素应尽量保持位置连续。

例：

- compact album art 扩展为 64px album art。
- notification app icon 保持 leading anchor。
- OSD 更新只动画 progress，不重新进入整个 scene。

### 11.3 reduced motion

reduced 模式：

- geometry 0-100ms。
- 内容只使用 opacity。
- 禁用 visualizer。
- 禁用 recording pulse。
- 禁用 hover 自动展开。
- 禁用大范围位移。

### 11.4 hover

默认 hover：

- 提高 material interaction。
- 可显示轻微 secondary hint。
- 不直接展开完整播放器。

hover expand 可保留设置兼容，但默认应关闭，并经过独立可用性验收。

---

## 12. 响应式、多屏与输入

### 12.1 TopBar 关系

启用灵动岛：

- Overlay 负责 resting 和 expanded。
- TopBar 只保留中心 reserve。
- 不再由 DynamicIslandChip 提供第二种启用态视觉。

禁用灵动岛：

- TopBar 显示普通、可读的时间文本。
- 不显示仿岛 chip。

center reserve：

- 按最大 compact media 宽度计算。
- 不能继续使用小于 compact media 的 168/184 固定值。
- reserve 不应在每次状态变化时推动左右集群。

### 12.2 多屏

- 全局状态只存一份。
- 每输出 surface 只负责渲染。
- resting clock 可以每屏显示。
- transient 只在 event owner output 显示。
- expanded 只在 session owner output 显示。
- 用户点击某输出后锁定 session owner。
- owner 输出移除时回退到 focused output，再回退到第一个有效输出。

### 12.3 输入

- compact 整体可点击。
- expanded 控件拥有自己的 hit target。
- 父 MouseArea 不得截获子控件。
- notification swipe 与默认点击必须互斥。
- timer detached bubble 若实现，必须纳入 mask。
- keyboard interactivity 只在确实需要键盘的 scene 按需启用。

---

## 13. 可访问性与本地化

- 所有图标控件需要可访问名称。
- 不用颜色作为唯一状态表达。
- primary text 对表面保持足够对比。
- 控件 hit target 不小于 40px，首选 44px。
- 中文、英文和长应用名必须测试。
- 时间和日期使用系统 locale。
- 百分比、时长和工作区名称不得被固定宽度截断到不可理解。
- reduced motion 必须作为正式验收项。

---

## 14. 目标架构与反腐化边界

### 14.1 单一所有权表

| 领域 | 唯一 owner | 允许做法 | 禁止做法 |
| --- | --- | --- | --- |
| niri window/workspace | Windows.qml | 补 reducer 和查询函数 | 新 CompositorBackend、新 event stream |
| media/audio/brightness | Controls.qml | 稳定 active player 选择 | IslandMprisController 生产实例 |
| notifications | Notifications.qml | 读取现有 ID/model/action | dbus-monitor、第二通知队列 |
| battery | Battery.qml | 只读现有状态 | 岛内重新探测 UPower |
| settings | DesktopSettings.qml | 增量扩展现有字段 | island-settings.json |
| theme color | SettingsTheme.js | 新增语义函数 | DynamicIslandTheme.js 平行调色板 |
| glass material | TahoeGlass.js 和 niri material source | 继续使用 pill | 第八套 island material |
| motion profile | Motion.js 和 DynamicIslandMotion.js | 调整现有 token | 新 motion profile 文件 |
| deployment | scripts/arch-update.sh | 增加校验能力 | 新 deploy 脚本或手工 rsync |
| public IPC | shell.qml target tahoe | 保持现有函数名 | DynamicIslandV2 IPC target |
| island orchestration | DynamicIsland.qml | 内部 reducer/adapter | 第二个并行 DynamicIsland service |

### 14.2 公开接口策略

以下公开兼容面保持单一：

- dynamicIslandGetState。
- dynamicIslandGetDebugSummary。
- dynamicIslandGetSettingsSummary。
- dynamicIslandReset。
- dynamicIslandShowTime。
- dynamicIslandShowMedia。
- dynamicIslandShowExpandedMedia。
- dynamicIslandShowExpandedSummary。
- dynamicIslandShowOsd。
- dynamicIslandShowNotification。
- dynamicIslandShowWorkspace。
- dynamicIslandMediaPrevious。
- dynamicIslandMediaToggle。
- dynamicIslandMediaNext。
- dynamicIslandSwipeBegin。
- dynamicIslandSwipeAdvance。
- dynamicIslandSwipeResolve。
- dynamicIslandSwipeCancel。
- dynamicIslandSetEnabled。
- dynamicIslandSetHideTopbarTime。
- dynamicIslandSetLeftClickAction。
- dynamicIslandSetRightClickAction。
- dynamicIslandSetAutoExpandMedia。
- dynamicIslandSetHoverExpand。
- DesktopSettings 现有 dynamicIslandEnabled、dynamicIslandHideTopbarTime、dynamicIslandLeftClickAction、dynamicIslandRightClickAction、dynamicIslandAutoExpandMedia 和 dynamicIslandHoverExpand 字段。

兼容决策现在固定，不得拖到 T18 再选择：

- dynamicIslandShowExpandedSummary 保留函数名。
- V2 删除 summary 后，该函数作为 deprecated compatibility alias 打开现有 ControlCenter，并返回当前稳定 island state。
- 不再产生 expanded_summary state。
- dynamicIslandHideTopbarTime=true 时，各输出由 Overlay 显示 base clock。
- dynamicIslandHideTopbarTime=false 时，各输出由 TopBar 显示普通时间，Overlay 在 resting 时隐藏，只在 activity/transient/expanded 时出现。
- 旧 left-swipe summary 不映射到另一个四宫格；它只在已注册活动 scene 之间切换，没有可切换活动时回到 base scene。

允许内部重构，但不得创建一套 V2 IPC 与旧 IPC 长期并存。

### 14.3 内部 helper 规则

允许创建纯内部 helper，例如 DynamicIslandReducer.js，但必须满足：

- 只有 DynamicIsland.qml 是生产调用方。
- helper 不直接访问系统服务。
- helper 输入是普通事件和旧状态。
- helper 输出是新状态和 effect 描述。
- 同一任务内删除被替代的旧判断逻辑。
- 禁止新旧 reducer 同时决定生产状态。

### 14.4 事件模型

建议内部事件 envelope：

~~~text
{
  kind,
  id,
  payload,
  priority,
  output,
  createdAt,
  expiresAt,
  duration
}
~~~

核心状态：

~~~text
{
  baseScene,
  presentation,
  activeTransient,
  activeNotificationId,
  pendingOsd,
  ownerOutput,
  gesturePhase,
  restoreScene,
  interactionLock
}
~~~

这里的对象只用于 presentation state，不复制 Notifications 或 Controls 的权威模型。

Notifications.qml 唯一拥有：

- 通知 FIFO 顺序。
- replacement。
- expiry。
- dismiss。
- action。
- 当前可展示 head 的推进。

DynamicIsland 只持有当前 activeNotificationId 或等价 presentation lease。被 expanded/user interaction 阻塞时，岛不复制 ID 队列；恢复时向 Notifications.qml 请求当前可展示 head。

### 14.5 优先级

建议优先级：

| 类别 | 优先级 | 队列策略 |
| --- | ---: | --- |
| user interaction / expanded session | 100 | block lower events |
| critical notification | 90 | Notifications.qml-owned FIFO，岛只获取 head lease |
| notification | 80 | Notifications.qml-owned FIFO，岛只获取 head lease |
| timer completion | 70 | FIFO or replace same timer |
| OSD | 50 | coalesce by kind |
| workspace | 40 | latest only |
| media preview | 30 | latest only |
| clock | 0 | stable fallback |

恢复必须只有一个入口，禁止 stateChanged 中分别调用多个 pending presenter 互相覆盖。

### 14.6 scene 数据

禁止所有场景继续共用 displayText/secondaryText/iconCode 作为唯一数据协议。

建议内部只读 presentation model：

- clockPresentation。
- mediaPresentation。
- osdPresentation。
- notificationPresentation。
- timerPresentation。
- workspacePresentation。

这些 model 从权威 service 即时映射，不拥有 service 生命周期，也不复制完整 model。

---

## 15. 测试和验收总策略

### 15.1 每任务基础测试

每个任务至少执行：

~~~bash
git diff --check
PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider <task-test-allowlist>
~~~

触及 QML 行为时执行对应 qmltestrunner harness。

触及 Windows.qml 时执行 niri event reducer 测试。

触及 TahoeGlass 时执行：

~~~bash
bash scripts/check-tahoe-glass-guardrails.sh
python3 -m pytest -q tahoe-shell/tests/test_tahoe_material_governance.py
~~~

### 15.2 全量功能回归

每个实现任务都必须执行完整 Tahoe pytest；模块测试不能替代完整测试：

~~~bash
PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider
~~~

完整测试未运行、异常退出或存在未解释失败时，该任务必须 BLOCK，不能仅记录限制后继续。

只有用户明确批准修改本路线图的测试门禁后，才能改变这一规则；批准本身必须形成独立、审查并 push 的路线图修订提交。

### 15.3 视觉矩阵

最终必须覆盖：

- 1366 宽。
- 1920 宽。
- 2048 逻辑宽。
- 1.0 scale。
- 1.25 scale。
- 亮色复杂壁纸。
- 暗色壁纸。
- dark mode。
- light mode。
- reduced motion。
- 中文长文本。
- 英文长文本。

状态：

- resting clock。
- compact media。
- volume。
- brightness 0 和 100。
- muted。
- notification short。
- notification long。
- notification actions。
- expanded media。
- timer。
- swipe 0%、50%、100%。
- 多屏 owner 切换。

Recording 属于可选 E00，不是 T23 核心发布门禁。

### 15.4 性能门禁

- T00 用同一输出、scale、主题和空闲场景采集 10 分钟基线，记录 quickshell CPU median/p95、RSS median/peak、采样命令和原始日志。
- T22/T23 的 10 分钟空闲 CPU median 不得高于基线加 `max(0.3 percentage point, baseline * 20%)`，RSS peak 不得高于基线 12 MiB。
- 连续 10 次 compact/expanded、通知和 OSD 生命周期后，稳定 60 秒的 RSS 不得相对第一轮单调增长超过 5 MiB。
- hidden Loader 不实例化 scene。
- hidden output 不运行 media visualizer。
- 没有每帧重建 Image。
- 所有动画稳定后 TahoeGlass geometry region commit 为 0/min；时钟文本和媒体进度更新不得重提交 region。
- region count 保持 1；只有明确批准的 secondary bubble 可为 2。
- 展开和收起无残影。
- quickshell 日志无新增 QML warning。
- 使用现有 scripts/capture-glass-baseline.sh、TahoeGlass trace/guardrail 和 ps/pidstat 等系统采样；所需工具或 trace 不可用时任务 BLOCK，不能以“未观察到异常”替代数据。

---

## 16. 严格任务执行协议

后续每个 TNN 都必须使用本协议。

### 16.1 开始前

1. 确认上一任务状态为 complete。
2. git fetch origin。
3. 确认本地 HEAD 与 upstream 一致。
4. 记录 git status。
5. 记录所有 pre-existing dirty files。
6. 创建 tahoe-shell/docs/dynamic-island-v2-task-reports/TNN.md。
7. 在 task report 中记录 base SHA、任务目标、精确文件 allowlist、测试命令、实机验收和禁止项。
8. 路线图中的“主要允许修改”“允许修改”只是候选范围；task report 必须收敛成逐文件或精确 glob，不能保留“必要文件”“等价实现”等开放表述。
9. 将当前任务标记为 active。
10. 只读取当前任务依赖，不提前实现后续任务。

### 16.2 实现中

- 只修改 task report 中冻结的精确 allowlist；task report 自身始终属于 allowlist。
- 遇到无关 dirty change 不回退。
- 如果无关 change 与任务路径重叠，暂停并解决所有权。
- pre-existing dirty change 可以留在 working tree，但不得进入 staged diff。
- 不做顺手重构。
- 不升级依赖。
- 不重命名公开 IPC。
- 不添加长期 feature flag 维持两套生产路径。

### 16.3 测试、暂存与稳定哈希

1. 运行最小回归测试。
2. 运行受影响模块测试。
3. 运行完整 Tahoe pytest；docs-only 任务也至少运行文档检查和一次完整基线测试。
4. 运行任务要求的实机或截图检查。
5. git diff --check。
6. 只按精确 allowlist 逐文件或逐 hunk 暂存。
7. 禁止 git add . 和 git add -A。
8. git diff --cached --check。
9. git diff --cached --name-only 必须是 allowlist 子集。
10. 显示 git diff --cached --binary --full-index。
11. 使用统一命令计算最终 staged SHA-256：

~~~bash
git -c core.quotepath=false diff --cached --binary --full-index | sha256sum
~~~

任何 index 变化都会使该 SHA-256 和既有审查 verdict 失效。

### 16.4 独立审查

独立 reviewer prompt 必须包含：

~~~text
你是本任务的独立只读审查代理。
不要修改文件。
任务：TNN <title>
验收标准：<acceptance list>
精确允许修改文件：<allowlist>
基线提交：<base sha>
Staged SHA-256：<sha256>
待审 diff：git diff --cached --binary --full-index
已运行测试：<commands/results>

优先检查：
1. 功能回归和状态竞争
2. 反腐化边界与平行接口
3. 多屏、通知身份和交互生命周期
4. 测试缺口
5. 视觉、性能和可访问性

输出 Critical/High/Medium/Low findings，带文件和行号。
核对 staged SHA-256。
最后只给 APPROVE 或 REQUEST_CHANGES。
~~~

### 16.5 REQUEST_CHANGES 后返工

1. 取消当前任务暂存，但不丢弃文件。
2. 修复 findings。
3. 重跑该任务所有测试和完整 Tahoe pytest。
4. 重新按 allowlist 暂存。
5. 重新计算 SHA-256。
6. 启动另一个未参与实现和返工的新 reviewer。
7. 不得沿用旧 reviewer verdict。

### 16.6 commit、push 与远端确认

1. reviewer APPROVE 后再次计算 staged SHA-256，必须与获批值一致。
2. 使用 git ls-remote 确认远端目标分支 tip 仍等于 base SHA。
3. 创建带 Task、Tests、Independent-Review、Review-Verdict、Review-Round 和 Reviewed-Staged-SHA256 trailers 的 commit。
4. commit 后使用以下命令计算实际 commit patch SHA-256：

~~~bash
git -c core.quotepath=false diff --binary --full-index HEAD^ HEAD | sha256sum
~~~

5. commit patch SHA-256 必须等于获批 staged SHA-256。
6. push 前再次确认待推送区间只有该单一 commit。
7. 使用显式 refspec 普通 push：git push origin HEAD:refs/heads/<branch>。
8. push 后用 git ls-remote 确认远端 tip 精确等于本地 HEAD。
9. 确认 staged area 为空，working tree 只剩 pre-existing dirty changes。
10. 标记任务 complete。
11. 才能把下一个任务从 pending 改为 active。

---

## 17. 严格串行路线图总览

核心路线固定为 T00 到 T23。

禁止跳号实施。某项被证明不再需要时，也必须完成一个“取消决策提交”，记录证据、审查和 push，不能静默跳过。

| Phase | Tasks | 目标 |
| --- | --- | --- |
| A 基线与防回归 | T00-T02 | 建立可验证基线、部署一致性和公开契约 |
| B 权威数据源修复 | T03-T05 | 补齐 niri、MPRIS、brightness，不引入新 owner |
| C 状态内核 | T06-T09 | reducer、优先级、输出 owner、手势 settle |
| D UI 全面重做 | T10-T19 | 静态原型、统一 surface、逐 scene 替换、动效 |
| E 活动扩展 | T20-T21 | Timer 和 Bluetooth，使用单一权威数据源 |
| F 清理与发布 | T22-T23 | 删除遗留、性能、完整验收、部署 |

---

## 18. Phase A：基线与防回归

### T00：冻结当前功能、运行时和视觉基线

目标：

- 在任何行为修改前留下可复现证据。
- 明确当前仓库、部署目录和运行进程之间的版本关系。
- 建立后续视觉对比基线。
- 在任何实现前完成 Tide 来源、许可证和现有派生代码 provenance 审计。

允许修改：

- tahoe-shell/docs/visual-baselines/dynamic-island-v2-before/
- tahoe-shell/docs/dynamic-island-v2-baseline-*.md
- 与基线采集直接相关的测试清单文档。

禁止修改：

- 生产 QML。
- services。
- niri config。
- 部署脚本。

必须记录：

- git HEAD。
- quickshell 版本。
- niri 版本。
- output、scale、logical size。
- 当前 Dynamic Island IPC debug summary。
- ~/.config/quickshell/tahoe 与仓库 diff 摘要。
- 当前完整测试结果。
- 当前相关 QML 测试结果。
- quickshell 日志 warning 基线。
- 同一静止场景 10 分钟的 quickshell CPU median/p95、RSS median/peak、采样命令和原始日志。
- 两个 Tide 目录的来源 URL；无法确认时明确标记 unknown。
- LICENSE 文件 SHA256。
- 两个非 Git 源码目录的确定性 tree/archive SHA256。
- 当前带 Tide-derived 注释或结构的生产文件清单。
- 当前根仓/Tahoe shell 许可证决策；未解决时 T00 BLOCK，不能进入 T01。

必须截图：

- resting clock。
- expanded summary。
- OSD volume。
- OSD brightness。
- workspace。
- notification；若 DND 开启，记录并使用受控测试会话，不永久改变用户设置。
- control center 与岛同屏关系。
- bright wallpaper 和 dark wallpaper。

审查重点：

- 基线是否来自实际运行版本。
- 是否误把仓库代码截图当作部署代码截图。
- 是否修改了用户设置后未恢复。
- 是否遗漏 scale 和 output。

验收：

- 基线文档可以让另一个人复现。
- PNG 有尺寸和 SHA256 清单。
- 未修改生产行为。

提交标题：

~~~text
docs(dynamic-island): T00 freeze v1 runtime and visual baseline
~~~

### T01：在现有 arch-update.sh 中建立 source/runtime 一致性门禁

目标：

- 消除“仓库修了、运行目录没更新”的不确定性。
- 继续使用现有唯一部署入口。

主要允许修改：

- scripts/arch-update.sh
- scripts/README.md
- 与部署校验直接相关的 tests。

实现要求：

- 部署前记录 tahoe-shell 源目录 manifest。
- 部署后对 ~/.config/quickshell/tahoe 执行确定性一致性检查。
- canonical desired tree 等于 tahoe-shell/ 的部署内容，加上唯一声明的外部覆盖 scripts/check-xwayland-satellite-compat.sh。
- sync 和 manifest 共享同一精确 include/exclude 清单。
- 只排除明确缓存，例如 __pycache__、*.pyc 和 .pytest_cache；不得使用宽泛 runtime 排除。
- 检查必须检测缺失文件、多余文件和内容差异。
- 在状态目录记录 deployed root commit 和 shell manifest hash。
- dry-run 或检查模式不得写用户配置。
- 失败时给出具体不一致文件。

反腐化约束：

- 不新增 deploy-dynamic-island.sh。
- 不在任务脚本里手工调用未经治理的 rsync 路径。
- 不让 DynamicIsland.qml 自己读取 Git。

测试：

- 临时目录部署一致时 PASS。
- 修改一个目标文件时 FAIL。
- 删除一个目标文件时 FAIL。
- 增加多余源码文件时 FAIL。
- 允许的 runtime state 不触发 FAIL。
- scripts 现有测试和 shellcheck 类检查。

实机验收：

- 使用正常 arch-update 路径部署一次。
- 部署后 manifest 匹配。
- 不强制重启 niri。
- 仅在需要时重启 Quickshell。

审查重点：

- 是否破坏 arch-update 的其他部署功能。
- 是否可能删除用户状态。
- manifest 排除规则是否过宽。
- 是否创建了第二部署入口。

提交标题：

~~~text
fix(dynamic-island): T01 verify deployed shell parity
~~~

### T02：冻结现有公开接口和行为契约

目标：

- 在重构状态机前，用测试锁定必须兼容的行为。
- 明确哪些行为是 bug，哪些是兼容契约。

主要允许修改：

- tahoe-shell/tests/test_dynamic_island_*.py
- tahoe-shell/tests/tst_dynamic_island_*.qml
- 必要的 test-only fixture。

禁止修改：

- 生产 QML。

必须锁定：

- 现有 shell.qml IPC 函数名和参数。
- DesktopSettings 现有字段。
- 左右键 action 值。
- disabled 时仍有时间。
- DND 行为。
- notification stable ID 和 replacement。
- media press/release/cancel。
- overlay mask 不覆盖整屏。
- exclusiveZone: 0。
- namespace 不变。

必须新增的 characterization：

- notification active 时 OSD 当前会覆盖的 strict expected-failure 测试。
- workspace active 时通知竞争的 strict expected-failure 测试。
- swipe enter settle 两阶段宽度的 strict expected-failure 测试。
- focus change 导致 output jump 的 strict expected-failure 测试。
- 非 owner 输出 base clock/mask 语义的 strict expected-failure 测试。
- brightness 0 的 strict expected-failure 测试。

规则：

- Python 使用 pytest.mark.xfail(strict=True, reason="target TNN")。
- QML 使用可验证的 expect-fail 机制，并记录目标修复任务。
- expected-failure 必须准确描述预期新行为。
- expected-failure 的原始失败原因必须唯一且可解释。
- 整个测试进程必须以成功状态退出，主分支不能保持红灯。
- 对应修复任务必须删除 expected-failure 标记；strict XPASS 本身应阻止遗漏清理。
- 不通过放宽断言让旧行为变绿。

审查重点：

- 测试是否依赖源码字符串而非真实行为。
- expected-failure 是否会因无关原因失败。
- 是否遗漏 IPC 和设置兼容面。

验收：

- 原有测试全部通过。
- 新行为测试以 strict expected-failure 被追踪，完整 suite 保持绿色。
- 测试输出记录到 commit body。

提交标题：

~~~text
test(dynamic-island): T02 freeze contracts and expected failures
~~~

---

## 19. Phase B：权威数据源修复

### T03：补齐 Windows.qml 的 niri 增量工作区事件

前置：T02 complete。

目标：

- 在现有唯一 niri event stream 中正确处理工作区激活。
- 提供每输出查询能力。

主要允许修改：

- tahoe-shell/services/Windows.qml
- 对应 Windows/niri reducer tests。

实现要求：

- 处理 WorkspaceActivated。
- 评估并处理 WorkspaceUrgencyChanged。
- 评估并处理 WorkspaceActiveWindowChanged。
- 保持 WorkspacesChanged 作为结构更新。
- 使用 workspace idx 作为当前用户可见序号；明确它会随移动和重排变化。
- 使用稳定内部 id 关联 niri 实体。
- 提供只读查询：
  - focusedOutputName。
  - activeWorkspaceForOutput(name)。
  - activeWorkspaceIndexForOutput(name)。
- output hotplug 后清理无效缓存。
- event stream reconnect 后重新建立基线。

反腐化约束：

- 不新增 CompositorBackend。
- 不打开第二个 NIRI_SOCKET。
- 不在 DynamicIsland.qml 解析 raw niri JSON。

测试：

- full WorkspacesChanged。
- single WorkspaceActivated。
- focused true/false。
- 多输出各自 active workspace。
- output remove。
- workspace move/reorder 后 idx 更新、id 保持。
- empty workspace list。
- reconnect。
- malformed event 不破坏现有 model。

审查重点：

- id 与 idx 是否混淆。
- 是否会把一个输出激活误应用到全部输出。
- 是否破坏 WindowOverview 和 TopBar workspace。

验收：

- 新 reducer 测试通过。
- 现有 Windows、TopBar、Overview 测试通过。
- 实机切换工作区时 debug state 连续正确。

提交标题：

~~~text
fix(niri): T03 reduce workspace activation events in Windows
~~~

### T04：在 Controls.qml 内稳定 MPRIS active player

目标：

- 防止 D-Bus model 重排导致岛切换播放器。
- 保持 Controls.qml 为唯一 media owner。

主要允许修改：

- tahoe-shell/services/Controls.qml
- Controls/MPRIS tests。

实现要求：

- 记忆 lastActivePlayerDbusName。
- playing player 可以抢占 paused player。
- 多个 playing player 时使用明确稳定规则。
- remembered player 仍有效时不因 model reorder 切换。
- player 消失时选择下一候选。
- metadata 无效且无控制能力的 player 不应成为 active。
- 现有 ControlCenter 媒体卡继续使用同一 active player。

反腐化约束：

- 不创建 MediaSession.qml 作为第二 owner。
- 不引入 Tide IslandMprisController。
- 不复制 MPRIS model。

测试：

- reorder 不切换。
- playing 抢占 paused。
- current player disappear。
- metadata late arrival。
- paused player with track。
- no players。
- control capability change。

审查重点：

- 是否影响 ControlCenter。
- remembered D-Bus name 是否会永久指向无效 player。
- 是否产生绑定循环。

验收：

- 新旧媒体测试全部通过。
- 实机启动、暂停、关闭两个播放器时选择稳定。

提交标题：

~~~text
fix(media): T04 stabilize the shared MPRIS selection
~~~

### T05：修复 brightness 0 和 OSD baseline

目标：

- 让 0 成为合法亮度值。
- 保持首次样本和 reconnect 不误弹 OSD。

主要允许修改：

- tahoe-shell/services/DynamicIsland.qml
- tahoe-shell/services/Controls.qml 的现有 brightness read/write adapter。
- brightness/OSD tests。

实现要求：

- 区分 unavailable、NaN 和 0。
- baseline 可以为 0。
- 第一次有效样本只建 baseline。
- 真实用户从正值降到 0 时显示 OSD。
- Controls.setBrightness(0) 必须下发真实 0%，不得继续 clamp 到 0.05。
- reconnect 后第一样本不误弹。
- disabled 状态仍更新 baseline。

反腐化约束：

- 不新增 brightness service。
- 不绕开 Controls.qml。

测试：

- unavailable -> 0。
- 1 -> 0。
- 0 -> small positive。
- reconnect at 0。
- island disabled changes。
- repeated same value dedupe。
- setBrightness(0) adapter command。
- setBrightness negative/>1 clamp。

审查重点：

- Number(value) || fallback 是否再次吞掉 0。
- Controls 写入路径是否仍把 0 提升为 5%。
- audio OSD 是否被无关修改。

验收：

- 删除 T02 brightness expected-failure 标记，测试转为普通 GREEN。

提交标题：

~~~text
fix(dynamic-island): T05 preserve zero brightness OSD state
~~~

---

## 20. Phase C：状态内核

### T06：引入单一纯 reducer，保持公开行为不变

目标：

- 从 DynamicIsland.qml 拆出可测试的纯状态转换。
- 不创建第二个生产状态机。

主要允许修改：

- tahoe-shell/services/DynamicIsland.qml
- 新的单一内部 DynamicIslandReducer.js。
- DynamicIsland reducer tests。

实现要求：

- 定义 state shape。
- 定义 event envelope。
- reducer 不访问 QML service。
- reducer 不启动 Timer。
- reducer 返回 nextState 和 effect 描述。
- DynamicIsland.qml 仍是唯一生产 orchestrator。
- 先迁移无争议的基础状态：
  - clock。
  - media availability。
  - manual expanded/collapse。
- 现有公开 properties 保持兼容。

迁移规则：

- 每迁移一个判断，同任务删除旧判断。
- 禁止 oldReducer/newReducer 双算后择一。
- 禁止增加 user-visible V2 toggle。

测试：

- reducer deterministic。
- same input same output。
- state object 不被原地修改。
- clock/media/expanded parity。
- existing IPC tests。

审查重点：

- 是否真的只有一个状态决策源。
- reducer 是否偷偷读取 Date.now 或 service。
- effect 是否可重复执行。
- 是否发生公开属性变化。

验收：

- 现有绿色测试保持绿色。
- T02 与后续任务相关的 strict expected-failure 保持预期状态。
- IPC debug summary 仍可用。

提交标题：

~~~text
refactor(dynamic-island): T06 establish the single event reducer
~~~

### T07：实现 transient 优先级、队列和通知身份恢复

目标：

- 修复通知、OSD、workspace 和 media preview 的竞争。

主要允许修改：

- DynamicIsland.qml
- DynamicIslandReducer.js
- Notifications.qml 的最小 head/lease 查询或确认 API；不得复制 model。
- notification/OSD/arbitration tests。

实现要求：

- 使用第 14.5 节优先级。
- Notifications.qml 继续唯一拥有 notification FIFO。
- DynamicIsland 删除 pendingNotificationIds 或任何等价 notification queue。
- DynamicIsland 只保存当前 active notification identity/lease。
- 阻塞解除后从 Notifications.qml 重新解析当前 head。
- OSD 按 kind coalesce。
- workspace latest only。
- 同一 notification replacement 原位更新。
- transient 结束只经过一个 restore/drain 入口。
- displayingNotificationId 与 active transient 同生命周期。
- 高优先级结束后恢复被阻塞的稳定场景。
- user interaction 期间 lower event 入队或合并，不覆盖。

测试：

- notification vs volume。
- notification vs brightness。
- notification vs workspace。
- two notifications follow Notifications-owned FIFO。
- replacement while displayed。
- replacement while queued。
- notification removed while queued。
- DND enable during display。
- OSD coalesce。
- timer expiry order。
- no stale displayingNotificationId。

审查重点：

- onStateChanged 是否仍有多个 presenter。
- timer callback 是否能清理别的状态。
- 是否仍存在 island-owned notification ID/payload queue。
- active lease 是否通过 Notifications.qml 实时解析，避免 snapshot 过期。

验收：

- 删除 T02 对应 priority expected-failure 标记，测试转为普通 GREEN。
- 现有 notification identity 测试保持通过。

提交标题：

~~~text
fix(dynamic-island): T07 serialize transient arbitration
~~~

### T08：实现 event owner 和多屏会话所有权

目标：

- transient 展示期间不随焦点跨屏跳动。
- 明确 resting、transient 和 expanded 的多屏语义。

主要允许修改：

- DynamicIsland.qml
- DynamicIslandReducer.js
- DynamicIslandOverlay.qml 中的所有权与 base scene 绑定。
- TopBar.qml 的逐输出 base clock/通知入口绑定。
- NotificationToast.qml 的逐输出抑制策略；只有实现规则确需修改时进入最终精确 allowlist。
- multi-output tests。

实现要求：

- event 创建时捕获 output。
- transient owner 生命周期固定。
- 用户点击某输出时建立 session owner。
- expanded 期间 session owner 固定。
- collapse 后释放 session owner。
- output remove 时回退 focused output。
- focused output 不可用时回退第一个有效输出。
- dynamicIslandHideTopbarTime=true 时，每个输出始终保留 base clock scene 和对应 compact mask。
- activity owner 可以在自己的输出把 base clock 替换为 compact media。
- transient/expanded 只在 event/session owner 显示。
- 非 owner 输出在 owner-bound 活动期间继续显示自己的 base clock，不渲染 transient/expanded。
- dynamicIslandHideTopbarTime=false 时由每屏 TopBar 普通时间承担 base scene。
- Notification transient 只在 owner output 显示，不向每屏复制 toast。
- 非 owner 输出保留 TopBar 通知徽标、NotificationCenter 入口和 base clock。
- island disabled 时恢复现有 NotificationToast。

反腐化约束：

- 不为每屏创建 DynamicIsland service。
- 不广播通知到所有 output。
- 不创建第二个 ownership model。
- 不创建第二通知队列。

测试：

- focus changes during notification。
- focus changes during expanded media。
- user opens on non-focused output。
- owner output removed。
- output name empty。
- single output。
- two output resting。
- non-owner mask 只覆盖其 base clock，不覆盖隐藏的 transient/expanded geometry。
- hideTopbarTime=false 时 resting overlay mask 为空而 TopBar 时间可交互。
- non-owner notification badge/history access 保留。
- island disabled restores NotificationToast。

审查重点：

- targetScreenName 是否仍动态覆盖 event owner。
- 多屏是否运行重复 Timer。
- NotificationToast、岛 transient 和 TopBar badge 是否符合逐屏规则且不重复。

验收：

- 删除 T02 对应 output ownership expected-failure 标记，测试转为普通 GREEN。
- multi-output test fixture 全部通过。
- 使用物理双屏或受控虚拟输出完成检查；两者都不可用时任务 BLOCK。

提交标题：

~~~text
fix(dynamic-island): T08 pin events and sessions to an output
~~~

### T09：修复 swipe settle 和输入生命周期

目标：

- 删除两阶段收缩再展开。
- 保持 click/swipe/vertical reject 的现有防误触能力。

主要允许修改：

- DynamicIsland.qml
- DynamicIslandReducer.js
- DynamicIslandOverlay.qml gesture section。
- DynamicIslandMotion.js。
- gesture QML tests。

实现要求：

- begin gesture 记录 start presentation。
- resolve 时一次计算 target scene、width 和 height。
- settle 全程使用 target geometry。
- settle 结束只清理 gesture state。
- pointer 与 wheel session 互斥。
- child media controls 不触发 parent swipe。
- vertical reject 不触发 click。
- next pointer session 不继承 suppression。
- cancel 恢复 start presentation。

测试：

- enter media frame targets。
- enter alternate scene frame targets。
- return to center。
- vertical reject。
- diagonal dead band。
- quick follow-up click。
- wheel settle。
- control press/cancel/destroy。
- output owner during swipe。

审查重点：

- 是否还有 swipePreviewWidth 优先覆盖最终 state。
- Timer 是否清理新 gesture。
- suppression 是否跨 session。

验收：

- 删除 T02 对应 swipe expected-failure 标记，测试转为普通 GREEN。
- 逐帧目标宽度单调或符合预定曲线。
- 无 collapse-expand 二次跳变。

提交标题：

~~~text
fix(dynamic-island): T09 settle swipe directly to its target
~~~

---

## 21. Phase D：UI 全面重做

### T10：建立非生产静态预览器和视觉 token 基线

目标：

- 在接入生产状态前确定新 UI。
- 避免一边改状态机一边凭感觉调整视觉。

主要允许修改：

- tahoe-shell/tests 或专用 preview harness。
- 新的 scene 组件，但不得接入生产 shell。
- SettingsTheme.js 中经过验证的 island 语义色。
- DynamicIslandMotion.js 中新时序 token。
- 视觉 baseline 文档和截图。

必须提供 mock state：

- clock。
- compact media。
- OSD volume/muted/brightness。
- short/long notification。
- notification actions。
- expanded media。
- workspace。
- timer。

必须截图：

- light/dark。
- bright/dark wallpaper。
- Chinese/English。
- 1366/1920/2048。
- scale 1/1.25。

反腐化约束：

- preview 不注册 IPC。
- preview 不打开 Notifications、MPRIS 或 niri socket。
- preview 不进入正式 shell.qml。
- 不创建 DynamicIslandTheme.js。
- 不创建第八 material。

审查重点：

- 是否只存在一套 color/motion token。
- 是否有文字溢出。
- 是否仍像大椭圆。
- 是否与 TopBar 风格冲突。

验收：

- 用户可通过截图比较完整状态矩阵。
- 推荐“深色焦点玻璃”方向被实现为一致组件。
- 生产行为完全未变。

提交标题：

~~~text
feat(dynamic-island): T10 add the reviewed V2 visual preview
~~~

### T11：替换统一 surface 的材质、几何和 scene host

目标：

- 保留同一个 Overlay 窗口。
- 建立 V2 geometry，不立即改变各业务 scene 内容。

主要允许修改：

- DynamicIslandOverlay.qml
- DynamicIslandContent.qml 或新的单一 scene host。
- GlassPanel 使用配置。
- tahoe-shell/docs/tahoe-material-governance.md。
- tahoe-shell/tests/test_tahoe_material_governance.py。
- geometry tests。

实现要求：

- compact y 与 TopBar 内层对齐。
- expanded radius 限制 28-32。
- fill 降到视觉基线范围。
- stroke 恢复为受控 1px 或由视觉验收决定。
- width/height 有屏幕 clamp。
- scene host 使用 Loader。
- 过渡最多保留 current 和 outgoing 两个 scene。
- mask 精确跟随 surface。
- region count 保持 1。
- 将 DynamicIsland 的 1-region pill surface recipe 写入现有材质治理表。

反腐化约束：

- 不创建第二个 Overlay。
- 不引入 V2 PanelWindow。
- 不更改 material profile。
- 不使用 spring 驱动 region geometry。

测试：

- every state geometry。
- narrow screen clamp。
- radius cap。
- mask bounds。
- region count。
- no hidden scene instantiation。
- scripts/check-tahoe-glass-guardrails.sh。
- test_tahoe_material_governance.py。

审查重点：

- old content 和 new host 是否双重渲染。
- Loader 是否在隐藏输出仍 active。
- glass geometry 是否有 spring。

验收：

- 当前功能 scene 仍可显示。
- 外轮廓不再为大椭圆。
- bright wallpaper 上能看见真实玻璃而保持可读。

提交标题：

~~~text
refactor(dynamic-island): T11 install the unified V2 surface
~~~

### T12：重做 Resting Clock、TopBar 集成并删除双视觉路径

目标：

- 启用时只由 Overlay 渲染时钟。
- 禁用时由 TopBar 渲染普通时间。
- 删除启用态与 fallback chip 的视觉割裂。

主要允许修改：

- DynamicIslandOverlay.qml
- 新 RestingClock scene。
- TopBar.qml。
- DynamicIslandChip.qml；仅在本任务确认无引用后删除。
- shell.qml 中相关 wiring。
- clock/topbar tests。

实现要求：

- V2 clock 使用本地化星期和时间。
- compact 高度约 32px。
- width 内容驱动，限制 112-136px。
- TopBar center reserve 覆盖最大 compact media。
- reserve 不随 clock/media 每次切换而推动左右集群。
- island disabled 时显示普通可读时间 Text。
- 保持现有左键、右键和 hover setting 兼容。
- DynamicIslandChip 无生产引用后在同任务删除。

反腐化约束：

- 不保留 showV2Clock 设置。
- 不同时渲染 chip 和 overlay clock。
- 不新增第二个时间 Timer；继续复用现有时间 source。

测试：

- enabled + hideTopbarTime。
- enabled + legacy hide setting false 的兼容迁移。
- disabled fallback。
- 12/24 hour locale。
- Chinese/English weekday。
- center reserve no overlap。
- click actions。

审查重点：

- 时间是否有两个 owner。
- disabled 是否丢失时钟。
- TopBar 左右集群是否在窄屏溢出。

验收：

- 运行时只有一个启用态岛 surface。
- DynamicIslandChip 被删除或确认只保留非生产测试用途；首选删除。
- 视觉截图通过。

提交标题：

~~~text
feat(dynamic-island): T12 replace the clock and top-bar integration
~~~

### T13：重做 OSD scene

目标：

- 替换百分比加环形进度的旧布局。
- 保持 volume/brightness 事件行为。

主要允许修改：

- 新 DynamicIslandOsdView.qml 或等价单 scene。
- DynamicIslandContent/scene host。
- DynamicIsland.qml 的 OSD presentation mapping。
- OSD tests。

实现要求：

- 20px TahoeSymbol。
- 112-128px 水平 progress。
- 右侧精确值。
- volume、muted、brightness 使用同一 scene。
- 连续更新不重新播放整个内容进场。
- brightness 0 正确显示。
- value 和 progress clamp。
- muted 不使用危险红色，除非产品规范另有明确理由。

反腐化约束：

- 不读取 PipeWire 或 backlight。
- 不复制 Controls state。
- 不保留旧 Canvas ring。

测试：

- 0/1/50/100%。
- muted。
- rapid volume sequence。
- volume then brightness coalesce。
- notification blocks OSD。
- reduced motion。

审查重点：

- frequent update 是否重建 Loader。
- progress 和 value 是否表达矛盾。
- 旧 ring 是否仍被实例化。

验收：

- OSD 截图在亮暗壁纸上可读。
- 更新流畅且无内容闪烁。
- 原 OSD 行为测试通过。

提交标题：

~~~text
feat(dynamic-island): T13 replace the OSD scene
~~~

### T14：重做紧凑通知 scene

目标：

- 使用真实应用身份。
- 实现内容驱动的宽高。

主要允许修改：

- 新 DynamicIslandNotificationView.qml。
- DynamicIslandContent/scene host。
- DynamicIsland.qml notification presentation mapping。
- Notifications.qml 只允许补充已有模型缺少的只读查询。
- notification tests。

实现要求：

- 使用 app icon URL。
- icon fallback 使用 TahoeSymbol。
- 显示 appName、summary 和最多一行 body。
- short notification 使用较窄宽度。
- long notification 最大 420px，最多两行紧凑内容。
- notification ID 仍来自 Notifications.qml。
- replacement 原位更新，不重播 enter。
- default click action 使用现有 Notifications API。
- 主体点击语义固定为 default action，后续 T15 不得改写。
- swipe dismiss 使用稳定 ID。

反腐化约束：

- 不创建 island notification model copy。
- 不使用 dbus-monitor。
- 不建立第二通知 queue。
- 不修改 org.freedesktop.Notifications owner。

测试：

- short/long。
- no icon。
- app icon。
- replacement。
- dismiss during queue promotion。
- DND。
- default action。
- non-target output。

审查重点：

- model rebinding 时 dismiss 是否作用到错误 ID。
- app icon 路径是否可能访问任意不安全 URL。
- 文字测量是否绑定循环。

验收：

- 紧凑通知来源清晰。
- 不再只显示通用 bell。
- GNOME 通知 title/body 语义保持。

提交标题：

~~~text
feat(dynamic-island): T14 replace compact notifications
~~~

### T15：增加通知展开和 action，不复制通知中心

目标：

- 允许长通知在岛内查看和快速处理。
- 保持通知中心作为完整历史 owner。

主要允许修改：

- DynamicIslandNotificationView.qml。
- DynamicIsland state/reducer 的 compact/expanded presentation。
- notification action tests。

实现要求：

- 只有 trailing expand chevron 在有 overflow 时切换 expanded。
- 通知主体继续执行 T14 冻结的 default action。
- expanded 最大宽 440px。
- expanded 最大高 176px。
- body 最多三行或受限 Flickable。
- 最多显示三个 action。
- default action 不重复显示为“打开”。
- action 成功后按通知语义 dismiss 或恢复。
- 用户与 action 交互期间停止自动 collapse。
- 失去 notification 时安全恢复。

反腐化约束：

- 不复制 NotificationCenter 卡片。
- 不在岛内显示通知历史列表。
- 不新增 action dispatch API。

测试：

- no overflow no expand。
- overflow chevron expand/collapse。
- body click still invokes default action。
- chevron click never invokes default action。
- one/two/three actions。
- action while replacement。
- notification removed while expanded。
- timeout paused during interaction。
- keyboard focus only when required。

审查重点：

- action identity。
- Flickable 与 capsule swipe 手势冲突。
- expanded notification 是否阻塞 OSD 后正确恢复。

验收：

- 长通知可读。
- action 可用。
- NotificationCenter 未回归。

提交标题：

~~~text
feat(dynamic-island): T15 expand notifications with shared actions
~~~

### T16：重做 Compact Media

目标：

- 创建真正适合顶栏的媒体紧凑态。

主要允许修改：

- 新 DynamicIslandCompactMediaView.qml。
- scene host。
- media presentation mapping。
- compact media tests。

实现要求：

- 22x22 album art。
- 单行 title。
- trailing play/pause TahoeSymbol。
- 可选 2px progress。
- artist 不进入 compact。
- 没有真实 audio data 时无 visualizer。
- 记忆的 active player 来自 Controls.qml。
- media unavailable 时平滑恢复 clock。

反腐化约束：

- 不直接遍历 Mpris.players。
- 不自己选择 player。
- 不新增 media Timer，除非复用现有 position source。

测试：

- art/no art。
- playing/paused。
- long title。
- player disappear。
- reorder。
- progress unsupported。
- reduced motion。
- compact width reserve。

审查重点：

- album Image 是否在隐藏输出加载。
- title 是否导致 geometry 抖动。
- 是否重新实现 active player 选择。

验收：

- 1366 宽不与 TopBar 集群重叠。
- 长标题稳定 elide。
- clock/media 切换无黑屏帧。

提交标题：

~~~text
feat(dynamic-island): T16 replace compact media
~~~

### T17：重做 Expanded Media

目标：

- 替换 Tide 第一版播放器视觉。
- 保持媒体控制生命周期安全。

主要允许修改：

- DynamicIslandMediaView.qml，允许整体重写。
- scene host。
- media interaction tests。

实现要求：

- 64x64 album art。
- 16px title，12px artist。
- timeline 和 elapsed/duration。
- 36px accent play/pause。
- 32px prev/next。
- hit target 至少 44px。
- 使用 TahoeSymbol。
- 删除 Canvas 手绘控制图标。
- 删除假 sine visualizer。
- player 不支持的操作显示 disabled，但仍吸收点击避免落到父层。
- collapse/destroy/cancel 正确清理 userInteracting。

可选：

- 只有 Controls 已有 seek 能力时实现 scrubber。
- 没有 seek 时 timeline 只读。

反腐化约束：

- 不添加 album-art background blur。
- 不添加第二 media controller。
- 不从 Tide 复制 GPL QML。

测试：

- all controls。
- disabled controls。
- press then collapse。
- press then player disappear。
- destroy while grabbed。
- timeline unknown。
- long metadata。
- multi-output hidden scene。

审查重点：

- interaction lifecycle。
- parent MouseArea fall-through。
- hidden Timer/Image 工作。
- 控件是否与 TahoeSymbol 一致。

验收：

- 功能控制不回归。
- 截图达到 V2 视觉基线。
- 无假频谱。

提交标题：

~~~text
feat(dynamic-island): T17 replace expanded media controls
~~~

### T18：删除 expanded_summary 默认路径并收敛 workspace 反馈

目标：

- 删除重复控制中心信息的大面板。
- 保持旧 IPC 不崩溃。

主要允许修改：

- DynamicIsland.qml/reducer。
- DynamicIslandSummaryView.qml；首选删除。
- 新的单一 DynamicIslandWorkspaceView.qml。
- scene host。
- shell.qml 中 expanded summary debug IPC 的兼容处理。
- settings/action mapping。
- related tests。

实现要求：

- 用户无活动时不展开四宫格。
- showExpandedSummary 旧 IPC 按第 14.2 节固定语义作为 deprecated alias 打开现有 ControlCenter，并返回当前稳定 island state。
- workspace transient 默认只在顶栏 workspace 不可见时展示。
- workspace 使用专用 scene，不再走 generic detailRow。
- scene 显示当前用户可见 idx/name，并按激活方向做受控滑动。
- 左滑不再默认进入重复 summary。
- 旧设置值迁移到最近的受支持 action。
- DynamicIslandSummaryView 无引用后删除。

反腐化约束：

- 不在新文件重建另一种四宫格。
- 不把 ControlCenter 嵌入岛。
- 不删除公开 IPC 函数名。

测试：

- old showExpandedSummary IPC。
- no media click。
- workspace topbar visible/hidden。
- workspace move/reorder、direction animation 和多屏截图。
- legacy settings migration。
- swipe page list。

审查重点：

- 兼容函数是否产生不存在状态。
- 是否留下 dead summary state。
- 是否影响 control center 打开定位。

验收：

- 生产状态集中不再出现 expanded_summary。
- 旧自动化调用不会抛异常。
- 无重复状态面板。

提交标题：

~~~text
refactor(dynamic-island): T18 retire the duplicated summary page
~~~

### T19：统一动效、共享元素和 reduced motion

目标：

- 完成 V2 的视觉手感。
- 删除旧 380ms 和全内容 scale 0.9 的机械感。

主要允许修改：

- DynamicIslandMotion.js。
- DynamicIslandOverlay.qml。
- 各 V2 scene 的 animation。
- Motion.js 只允许复用现有 profile helper，不新增 profile。
- motion tests。

实现要求：

- geometry 使用 220-300ms bounded NumberAnimation。
- 所有 duration 和 easing 只能从 Motion.js 或 DynamicIslandMotion.js token 读取；scene 内禁止直接散落 OutCubic 等 easing。
- old content exit 100-120ms。
- new content enter 160-180ms。
- 位移 <= 6px。
- compact/expanded album art 使用连续 anchor 或等价共享感。
- OSD value update 不重复 content enter。
- replacement notification 不重复 content enter。
- reduced motion 符合第 11.3 节。
- hover 默认只增强 interaction。

删除：

- 未使用 overlayExpandedExitHoldMs。
- 无效或重复 animation token。
- whole content 0.9 -> 1 默认缩放。

反腐化约束：

- 不新增 motion profile。
- 不让 glass region 使用 spring。
- 不把 compositor layer animation 加到常驻 island namespace。

测试：

- token convergence。
- reduced motion duration。
- geometry no SpringAnimation。
- repeated OSD no re-entry。
- notification replacement no re-entry。
- swipe uses target settle。

审查重点：

- 几何和内容是否双重驱动。
- 动画中是否改变输入 mask 错位。
- reduced mode 是否仍运行 Timer。

验收：

- 录屏逐帧无二次跳变。
- 不出现文字缩放模糊。
- reduced motion 无空间动画。

提交标题：

~~~text
feat(dynamic-island): T19 converge V2 motion and reduced mode
~~~

---

## 22. Phase E：活动扩展

### T20：增加单一 Timer owner 和 Timer scene

前置：

- T00-T19 全部 complete。
- 核心岛已经稳定。

目标：

- 吸收 Tide timer 的产品价值。
- 不把 timer 生命周期塞回 DynamicIsland.qml。

允许架构：

- 如果仓库仍无 timer owner，创建一个唯一 Tahoe Timer service。
- Timer service 可被岛和未来其他 UI 共享。
- DynamicIsland 只订阅 presentation event。

主要允许修改：

- 新的唯一 tahoe-shell/services/Timer.qml；若 T20 task report 证明现有 owner 更合适，只能改名迁移，不能并存第二 owner。
- tahoe-shell/shell.qml 的单一实例 wiring 和现有 tahoe IPC target。
- tahoe-shell/services/DynamicIsland.qml 与唯一 DynamicIslandReducer.js。
- tahoe-shell/components/DynamicIslandContent.qml 与新的单一 DynamicIslandTimerView.qml。
- tahoe-shell/services/DesktopSettings.qml 和 tahoe-shell/components/settings/pages/DynamicIslandPage.qml，仅增量扩展现有 click-action/settings 路径。
- 对应 timer、IPC、settings action、reducer 和 lifecycle tests。

实现要求：

- duration。
- remaining。
- running/paused/finished。
- start/pause/resume/cancel。
- Timer owner 使用 Quickshell ElapsedTimer/QElapsedTimer 的 monotonic elapsed time；QML Timer 只允许低频刷新显示，禁止 Date.now 或 wall-clock 差值驱动 countdown。
- 产品策略固定为 suspend/session inactive 时暂停消耗，恢复后从原 remaining 继续；不得用 wall clock 猜测睡眠期间经过时间。
- shell reload 的恢复策略明确；默认可选择不恢复 active timer，但必须文档化。
- completion 以 reducer event 进入优先级。
- compact 和 expanded UI 符合第 10.8 节。
- 在现有 tahoe IPC target 增量加入 dynamicIslandTimerStart(seconds)、dynamicIslandTimerPause()、dynamicIslandTimerResume() 和 dynamicIslandTimerCancel()；不创建第二 IPC target。
- 在现有左右点击 action 枚举和同一 dispatch 中加入 `timer`：无 active timer 时打开 timer setup，有 active timer 时展开当前 Timer scene；不创建平行设置入口。

反腐化约束：

- 不复制 Tide timer backend。
- 不在 DynamicIsland.qml 维护第二套 countdown。
- 不创建 Timer IPC target；如需 IPC，扩展现有 tahoe target。

测试：

- start。
- pause/resume。
- cancel。
- completion。
- repeated start policy。
- zero/negative duration validation。
- 四个 timer IPC 函数和非法参数。
- 现有 click-action `timer` 的 inactive/active 分支。
- suspend/inactive pause 与 resume remaining。
- notification during completion。
- reduced motion。
- reload policy。

审查重点：

- Timer 是否只有一个 owner。
- 是否使用 wall clock 导致跳变。
- completion 是否能覆盖 notification。

验收：

- timer 可从现有入口操作。
- completion 排队正确。
- 每秒更新不造成 geometry 重建。

提交标题：

~~~text
feat(dynamic-island): T20 add the shared timer activity
~~~

### T21：增加 Bluetooth 连接 transient

目标：

- 使用 Controls.qml 已有 Bluetooth 数据。
- 不移植 Tide Bluetooth backend。

主要允许修改：

- Controls.qml 只读连接状态或必要信号。
- DynamicIsland presentation adapter。
- Bluetooth transient scene 或 notification scene variant。
- Bluetooth tests。

实现要求：

- 连接中。
- 连接成功。
- 连接失败。
- 断开。
- 显示设备名称和可用图标。
- 相同设备连续事件 coalesce。
- 用户主动连接优先于后台扫描噪声。
- 不把完整设备列表放进岛。

反腐化约束：

- 不打开 bluetoothctl polling loop。
- 不创建 BluetoothConnectionTracker 生产副本。
- 不复制 ControlCenter Bluetooth UI。

测试：

- connect success/fail。
- disconnect。
- device removed。
- repeated state。
- notification priority。
- multi-output owner。

审查重点：

- 是否误把扫描发现当成连接通知。
- 设备对象销毁后的引用。
- Controls 现有蓝牙页面是否回归。

验收：

- 只显示有用户价值的连接事件。
- ControlCenter 和 Settings 蓝牙功能不变。

提交标题：

~~~text
feat(dynamic-island): T21 surface shared Bluetooth events
~~~

---

## 23. Phase F：清理、性能与发布

### T22：删除遗留路径并完成性能硬化

目标：

- 清理已经被 V2 替代的旧代码。
- 确认没有隐藏成本。

主要允许修改：

- DynamicIsland.qml。
- DynamicIslandOverlay.qml。
- DynamicIslandContent.qml。
- 已替代的旧 scene 文件。
- tests 和文档。

必须删除或证明仍需要：

- DynamicIslandChip。
- DynamicIslandSummaryView。
- 旧 generic detailRow。
- 旧 OSD Canvas ring。
- 旧 Canvas media controls。
- 假 visualizer。
- stale state names。
- unused properties。
- unused animation tokens。
- dead signal connections。

性能要求：

- 只实例化 current scene 和过渡 outgoing scene。
- 非 owner output 不加载重 Image。
- hidden media 无 Timer。
- hidden notification 无 Flickable 工作。
- 事件 update 不导致 Glass region 60Hz 重提交。
- quickshell idle CPU、RSS、10 次 lifecycle 后稳定内存和 region commit 必须满足第 15.4 节数值门禁。

测试：

- full Dynamic Island suite。
- qml compile/import。
- dead reference search。
- Tahoe material governance。
- motion token convergence。
- leak/lifecycle tests。

审查重点：

- 删除是否误伤旧 IPC 兼容。
- 是否留有双 state。
- Loader 生命周期。
- region commit 频率。

验收：

- 旧生产 UI 文件无引用后删除。
- 全量测试通过。
- 实机日志无新增 warning。

提交标题：

~~~text
refactor(dynamic-island): T22 remove legacy UI and harden runtime cost
~~~

### T23：完整回归、视觉验收、部署和发布记录

目标：

- 证明 V2 可替代旧版本。
- 完成最终部署一致性。

主要允许修改：

- 测试。
- 视觉 baseline。
- 本路线图的最终验收附录。
- 必要的小范围修复；如果修复超出验收范围，必须拆出新的串行任务，不能塞进 T23。

必须运行：

- 全量 pytest。
- 全量 Dynamic Island QML tests。
- TahoeGlass guardrails。
- niri config validation；若本阶段未改 config，仍记录当前结果。
- deployment parity check。
- quickshell QML warning scan。

必须实机验收：

- 所有第 15.3 节视觉状态。
- 单屏。
- 双屏；硬件不可用时使用受控虚拟输出测试并记录限制。
- focus 切换。
- output hotplug。
- notification replacement/actions。
- DND。
- volume/brightness。
- media player reorder/disappear。
- timer。
- Bluetooth。
- reduced motion。
- 按第 15.4 节执行同场景 10 分钟 long-running idle，并附 CPU/RSS 原始采样与 TahoeGlass region trace。

必须记录：

- before/after crop。
- final dimensions。
- final color tokens。
- final motion tokens。
- test command and result。
- reviewer id。
- deployed manifest hash。
- local HEAD。
- upstream HEAD。

审查要求：

- T23 reviewer 必须是新的独立 agent。
- reviewer 必须检查整个 T00-T23 commit range，而不仅是最后 diff。
- reviewer 必须明确列出剩余风险。

完成条件：

- reviewer APPROVE。
- 最终提交 push。
- HEAD == upstream。
- deployed shell manifest 与 source 一致。
- 运行实例使用新部署文件。
- 没有 Critical/High 遗留。

提交标题：

~~~text
docs(dynamic-island): T23 accept and release the V2 island
~~~

---

## 24. 可选增强池

以下任务不属于 T00-T23 核心完成条件。

只有 T23 complete 后才能开始，并且每项仍执行独立 review、commit、push 和严格串行。

### E00：Recording 状态源

开始条件：

- 先确认 portal/PipeWire 中存在可靠、事件驱动的单一状态源。
- 不允许通过高频进程轮询推测录屏。

可能范围：

- 新的共享 recording state owner，前提是仓库没有现有 owner。
- compact 红点和 duration。
- reduced motion 固定点。

取消条件：

- 无可靠来源。
- 只能依靠 ps/grep polling。
- 会复制 portal 状态。

### E01：歌词

开始条件：

- 明确数据源、网络请求、隐私和缓存策略。
- 明确许可证。
- 明确无歌词时的 UI。

规则：

- 默认关闭外部网络。
- 不把歌词获取塞进 media view。
- 不复制 Tide lyricsmpris。
- 不让歌词取代基本媒体控制。

### E02：真实 CAVA

开始条件：

- 有真实音频级别数据。
- CPU/GPU 和进程生命周期经过测量。

规则：

- 不允许假 sine wave。
- 仅 owner output 可见时运行。
- paused、hidden、reduced motion 时停止。
- CAVA 不可用时 UI 不留空洞。

### E03：自动隐藏和边缘唤出

开始条件：

- 核心岛输入 mask 和多屏 owner 已稳定。
- 有明确用户需求。

规则：

- 不改变 exclusive zone。
- reveal strip 必须覆盖可交互区域。
- timer bubble 等 detached element 必须进入 mask。
- 不影响 TopBar 正常输入。

---

## 25. 风险登记

| 风险 | 严重度 | 预防措施 | 发现后处理 |
| --- | --- | --- | --- |
| 运行副本落后源码 | Critical | T01 parity gate | 停止所有实现，重新部署核验 |
| 第二条 niri stream | Critical | owner table + review grep | 删除平行 backend，回滚任务 |
| 第二通知队列 | Critical | Notifications 唯一 owner | BLOCK review |
| 新旧状态机同时运行 | Critical | T06 单一 reducer 规则 | 不允许提交 |
| 通知身份错删 | Critical | stable ID QML test | 修复并新 reviewer |
| 多屏通知跳动 | High | T08 event owner | 不进入 UI phase |
| UI 重做破坏控制 | High | 每 scene 单独替换 | 回滚该 scene commit |
| 玻璃 region spring | High | governance test | BLOCK review |
| 1366 顶栏重叠 | High | T10/T12 screenshot | 调整 reserve/响应式 |
| hidden output 定时器 | High | Loader + lifecycle tests | T22 前必须清零 |
| GPL 代码复制 | High | 行为重写、来源审查 | 删除复制实现 |
| 主题 token 平行化 | Medium | SettingsTheme 唯一 owner | 合并回现有 token |
| 动效过慢 | Medium | T19 录屏逐帧 | 调整 token，不散落常量 |
| dark/light 对比不足 | Medium | 视觉矩阵 | 调整 fill/text token |
| optional feature 拖延核心 | Medium | E00-E03 后置 | 不阻塞 T23 |

---

## 26. 许可证与来源规则

Tide 项目使用 GPL-3.0。

该判断必须在 T00 通过本地 LICENSE SHA256、上游来源和源码树 SHA256 固化。当前 Tahoe 中所有 Tide-derived 注释、结构和文件必须先列入 provenance 清单；根仓/Tahoe shell 的许可证处理未形成明确结论时，T00 为 BLOCK，不能进入 T01。

本项目路线采用“行为研究后独立重写”：

- 可以研究状态名称、交互流程和公开视觉结果。
- 不复制大段 QML/C++。
- 不复制 Tide backend。
- 不复制 Tide 注释和私有实现结构。
- 每个从 Tide 吸收的行为必须适配 Tahoe 现有 owner。

独立 reviewer 必须检查：

- 是否出现大段结构相同代码。
- 是否复制 Tide 特有变量名和注释。
- 是否错误引入 GPL 文件头或代码。

如果未来决定直接复用 Tide 代码，必须先单独完成许可证决策，不能在普通实现任务中顺手复制。

---

## 27. 最终完成定义

Dynamic Island V2 只有满足以下全部条件才算完成：

1. T00-T23 全部按顺序 complete。
2. 每个任务有独立 reviewer APPROVE。
3. 每个任务有独立 commit。
4. 每个任务 commit 已 push。
5. 没有 force push 或 squash 破坏任务历史。
6. Windows.qml 是唯一 niri model owner。
7. Controls.qml 是唯一 media/audio/brightness owner。
8. Notifications.qml 是唯一 notification owner。
9. DynamicIsland.qml 是唯一 presentation orchestrator。
10. shell.qml 只有一个 tahoe IPC target。
11. scripts/arch-update.sh 是唯一部署入口。
12. 不存在长期 V1/V2 生产开关。
13. expanded_summary 已删除。
14. 旧假 visualizer 已删除。
15. Canvas media controls 已替换。
16. brightness 0 正确。
17. notification/OSD/workspace 优先级正确。
18. transient 不跨输出跳动。
19. swipe 不发生二段式几何跳变。
20. 非 owner output 不丢失基本通知可见性。
21. 1366/1920/2048 视觉验收通过。
22. 1.0/1.25 scale 验收通过。
23. dark/light/reduced motion 验收通过。
24. full test suite 必须通过；环境、工具或硬件不足导致无法执行时 T23 BLOCK，不能以补测承诺代替。
25. source manifest 与 deployed manifest 一致。
26. 运行中的 Quickshell 使用已审查提交。

---

## 28. 执行状态

当前状态：

- 研究：complete。
- 路线图：complete。
- 路线图独立审查：已完成一轮，明确发现已合并；按用户要求不再循环审查本文档。
- 实现：not started。
- 下一任务：T00。

本文档完成 commit/push 后才可开始 T00。自 T00 起，每项任务严格执行独立子代理审查、单一 commit、push 和远端确认，前一任务 complete 前不得启动后一任务。
