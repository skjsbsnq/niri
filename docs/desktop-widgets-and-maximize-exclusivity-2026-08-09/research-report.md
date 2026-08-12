# 研究报告：最大化独占渲染缺陷（B）与桌面小部件系统（A）

日期：2026-08-09
调查方式：全部为只读代码取证 + 在真实运行会话上的实测。所有结论标注 `文件:行号`。
未经验证的推断一律标注「未确认」，不得在实施阶段当作事实使用。

---

## 第 0 部分：本报告的可信度边界

**已实测确认**的结论标记为 `[实测]`，**已读代码确认**的标记为 `[代码]`，
**未验证的推断**标记为 `[未确认]`。执行者在实施时：

- `[实测]` / `[代码]` 结论可直接作为设计依据。
- `[未确认]` 结论**必须先自行验证**，验证失败则回到本报告修订，不得凭推断改代码。

---

## 第一部分：B — 最大化独占渲染的时序缺陷（编号 B-1 ~ B-3）

### 用户报告的三个现象（原文转述）

1. 最大化窗口后面有两层其他应用；点最大化窗口的最小化，动画正常播放，
   但**直到最小化动画结束后**，后面一层的软件才出现，而不是一最小化就出现。
2. 最大化软件盖住后面两层未最小化的软件时，**只要点击其中一个，另一个也会一起露出来**。
3. 把已最小化的软件从 Dock 右侧恢复为正常状态，**那两个正常应用会被隐藏掉**。

### B-0 根因（三现象共享同一机制）`[代码]`

核心是最大化过渡期的「**活动 tile 独占渲染**」。

**独占的执行点** —— `niri/src/layout/scrolling.rs:6126` `tiles_in_display_order()`：

```rust
let count = if priority_idx.is_some() { 1 } else { usize::MAX };
self.tiles_in_render_order_from(priority_idx.unwrap_or(self.active_tile_idx))
    .take(count)
```

`priority_idx` 为 `Some` 时 `.take(1)`，**该列除目标 tile 外全部不产出**。

**独占的开关** —— `scrolling.rs:3443` `maximizing_window_location()`：

```rust
let transition = self.maximize_transition.as_ref()?;
// Typed exclusivity: TimedOutVisibleFallback does not filter live tiles.
if !transition.exclusivity_active() { return None; }
```

**开关的判据** —— `niri/src/layout/maximize_visual_fsm.rs:112-117`：

```rust
pub fn exclusivity_active(&self) -> bool {
    matches!(self.phase,
        MaximizeVisualPhase::PendingConfigure | MaximizeVisualPhase::CommittedSettling)
}
```

**FSM 三相语义** —— `maximize_visual_fsm.rs:25-33`：

| 相位 | 语义 | 独占 |
|---|---|---|
| `PendingConfigure` | 已请求最大化，等目标窗口 commit maximized | 是 |
| `CommittedSettling` | 目标已 commit，**等 tile/view 移动动画 settle** | 是 |
| `TimedOutVisibleFallback` | 客户端超时未 commit，释放独占但保留记录 | 否 |

同一个 `.take(1)` 同时作用于两条路径：

- 渲染路径：`scrolling.rs:3652` `for (tile, tile_off, visible) in col.tiles_in_display_order(maximizing_tile_idx)`
- 命中测试路径：`scrolling.rs:3727` `window_under()` 内同一调用

### B-1 最小化动画结束后后面窗口才出现 `[代码]`

`CommittedSettling` 相的定义是「等 tile/view 移动动画 settle」。最小化动画属于
tile 动画，因此在整段最小化动画期间 `exclusivity_active()` 恒为真，
`.take(1)` 持续生效，同列其余 tile 一帧都不渲染。动画结束、FSM 被
`finish_maximize_transition_if_settled()`（`scrolling.rs:524`）清除后，
其余 tile 才重新进入渲染列表。

**因此现象 1 不是"渲染慢"，而是"被显式过滤掉了"。**

### B-2 点一个另一个一起露出 `[代码]`

独占是**全有或全无**的布尔量：`exclusivity_active()` 一旦转假，
`count` 从 `1` 变 `usize::MAX`，**该列全部 tile 同时恢复产出**，
而非只恢复被点击的那一个。

### B-3 恢复最小化窗口时其它正常应用被隐藏 `[代码]`

恢复路径叠加了三处状态变更，共同把其它窗口挤出可见集合：

1. **恢复可见性租约** —— `niri/src/layout/tile.rs:891-903`
   `apply_restore_visibility_lease()` / `is_suppressed_by_restore_lease()`；
   渲染侧在 `scrolling.rs:3656` 与 `:4892` 有
   `if tile.is_suppressed_by_restore_lease() { continue; }`。
2. **workspace 激活** —— `niri/src/layout/mod.rs:4009-4011`
   `if !minimized { self.activate_workspace_for_window(id); }`。
3. **floating 活动标志翻转** —— `niri/src/layout/workspace.rs:810`
   非最小化分支里 `self.floating_is_active = FloatingActive::No;`。

### B-4 与桌面小部件的耦合（为什么 B 必须先修）`[代码]`

桌面小部件将位于 `WlrLayer.Bottom`（壁纸之上、窗口之下）。当独占生效、
该列窗口被 `.take(1)` 过滤时，**小部件会整片暴露**；独占解除时又被瞬间盖住。
即本缺陷在小部件上线后会从"窗口时序问题"升级为"桌面闪烁"，
且届时难以区分是小部件自身缺陷还是本既有缺陷。**故 B 先于 A。**

### B 项修复方向（设计约束，非实现细节）

目标不变量：

- **BI-1**：最小化/恢复动画期间，未参与该次生命周期变更的 tile 的可见性
  **不得**因最大化独占而改变。
- **BI-2**：独占解除必须**按窗口**判定，不得是整列的全局布尔翻转。
- **BI-3**：渲染路径与命中测试路径的可见性判据必须保持一致
  （当前两处共用 `tiles_in_display_order`，重构后仍须共用同一判据，
  不得分叉成两套逻辑）。

**明确禁止**：新增与 `MaximizeVisualFsm` 并行的第二套状态机
（`maximize_visual_fsm.rs:53-55` 的注释已确立此原则：
"Test/diag observation of the production FSM (**no parallel test state machine**)"）。

---

## 第二部分：A — 桌面小部件系统

### A-0 需求定义（来自用户，不得扩张）

1. 打开侧边栏 → 点击**第三个 tab「小部件」** → 看到可用小部件列表，从上到下排列。
2. 点击列表中的一个 → **自动关闭侧边栏** → 在**桌面空余位置自动添加**该小部件。
3. **长按桌面小部件**进入编辑模式 → 可拖动位置。
4. 编辑模式下**按住边缘调整大小**（"就像窗口一样"）。
5. 输入优先级：**顶栏弹层（控制中心/剪贴板等）打开时，优先收回弹层**；
   其他情况小部件正常接收点击。

**范围边界（硬性）**：以上五条即全部需求。不得追加用户未要求的功能
（例如：小部件商店、云同步、第三方插件机制、动画特效开关、
多桌面/多页小部件、小部件间通信等）。

### A-1 前置调查三点结论

#### 第 1 点：输入区域可行 `[代码]`

`PanelWindow` 具备 `mask` 属性 —— `quickshell/src/window/proxywindow.hpp:58`：

```cpp
Q_PROPERTY(PendingRegion* mask READ mask WRITE setMask NOTIFY maskChanged);
```

`PendingRegion` 能力 —— `quickshell/src/core/region.hpp`：

- 子 region 列表：`:108` `Q_PROPERTY(QQmlListProperty<PendingRegion> regions ...)`
- 布尔运算：`:33-42` `Combine` / `Subtract` / `Intersect` / `Xor`
- 可绑 Item：`:59` `Q_PROPERTY(QQuickItem* item ...)`（小部件可直接交出自身 Item，免手算坐标）
- 圆角：`:74-90` `radius` 及四角独立半径

**现成范例**：`tahoe-shell/components/PopupDismissLayer.qml:100-123`
已用「全屏 Region 减去弹层 cutout」（`intersection: Intersection.Subtract`）。

据此，A-0 第 5 条的输入策略可直接表达为：

```
顶栏弹层打开 → mask 置空（整层不接收，点击直达 PopupDismissLayer）
否则         → mask = 各小部件 Item 的并集（小部件接收，空白穿透到桌面）
```

#### 第 2 点：LeftSidebar 改造零阻力 `[代码]`

`LeftSidebar` 的外部 id 引用**仅 1 处**，且在同一文件内：
`tahoe-shell/shell.qml:949` `popupWidth: leftSidebar.panelWidth`
（实例化在 `shell.qml:911`）。

LazyLoader 化时把 `panelWidth` 提升为 shell 级 readonly 属性即可。
改三分 tab 不影响此引用。

#### 第 3 点：layer-rule 动画支持 Bottom 层 `[代码]`

`niri/src/layer/mod.rs:111-113` `surface_matches()` 按 **namespace 正则**匹配，
与层级无关：

```rust
if let Some(namespace_re) = &m.namespace {
    if !namespace_re.0.is_match(surface.namespace()) {
```

故给小部件层起独立 namespace（建议 `tahoe-widgets`）即可在 KDL 配 layer-rule 动画。

### A-2 硬约束（来自代码与既有事故）

#### AC-1 glass region 上限 32 `[代码]`

`niri/src/protocols/tahoe_glass.rs:26` `pub const MAX_REGIONS_PER_SURFACE: usize = 32;`

超出部分**静默丢弃**（`:1091` 的 `.skip(MAX_REGIONS_PER_SURFACE)`），不报错。
桌面小部件浮于壁纸之上，需要玻璃材质，故每个小部件占 1 个 region
→ **宿主必须实现计数保护并在超限时给出可见反馈**，不得静默失效。

#### AC-2 玻璃 region 几何禁弹簧（既有守护规则）`[代码]`

`GlassPanel` 的 `x/y/width/height/region*` 严禁 `SpringAnimation`
（过冲致 region 超出 surface，niri 拒绝 + 纹理损坏；guardrail `0704ea4`）。

**推论**：小部件的拖动落位、resize 换档、编辑模式抖动，凡影响 region 几何者，
一律用 `Motion.js` 的时长 + Qt 缓动，禁用弹簧。

#### AC-3 首击吞噬与 C7 焦点约束 `[代码]`

`docs/click-first-hit-swallow-and-wallpaper-boot-postmortem-2026-08-02.md` §S2：
`focusable: true` 曾导致 wl 键盘焦点变化被 QtWayland 映射为
`ApplicationInactive`，进而**取消该应用全部窗口按住中的 MouseArea 独占 grab**。

对拖动是致命的：拖动中途焦点变化 → grab 取消 → release 永不到达 → 卡在拖动态。

niri 侧已有缓解 —— `niri/src/niri.rs:7145` `handle_on_demand_focus_press()`：
press 落在**非 on-demand 层**时把焦点清除**延迟到 release**（`defer_clear` 分支），
注释明示目的为 "so this press does not put the keyboard leave between that press
and its release (T-29 first-click swallow)"。

**推论（硬性）**：桌面小部件层必须使用 `KeyboardInteractivity.None`。
键盘交互（如 Esc 退出编辑模式）走 IPC 或全局快捷键，
**不得**给该层设 `focusable`。C7 是 postmortem §5 标注
"改动此块必须重跑嵌套 WAYLAND_DEBUG 复现脚本验证" 的约束，不得随手改。

#### AC-4 拖动必须复用 Dock 既有模式，不得引入 Drag/DropArea `[代码]`

仓库现状 `[实测]`：`DragHandler` / `Drag.active` / `drag.target` 使用次数均为 **0**；
仅 2 处 `DropArea`（`Dock.qml:1302`、`:2027`），且用途是**接收外部文件拖入**
（`drop.urls`），非内部重排。

内部重排的**唯一先例**在 `Dock.qml:1396-1470`，四状态指针模式：

| 回调 | 行号 | 职责 |
|---|---|---|
| `onPressed` | `:1449-1455` | 只记录起点，不激活 |
| `onPositionChanged` | `:1402-1417` | 位移 > 8px 才激活；置 `suppressNextClick` |
| `onReleased` | `:1456-1464` | 提交重排 + 重置 |
| `onCanceled` | `:1465-1473` | **完整回滚**（漏写会导致拖动态永久卡死） |

落点算法（一维）：`Dock.qml:920-934` `pinnedVisualIndexForRowX()` —— 遍历槽位中心。
坐标换算：`Dock.qml:948` `item.mapToItem(pinnedRow, mouseX, mouseY)`
（**必须转到宿主坐标系**；拖动中的卡片自身在移动，用其局部坐标会算错）。

持久化提交：`services/Apps.qml` `movePinnedApp()` —— 纯数组 splice 后整体写回。

拖动期两项必做：
- 抑制 hover：`Dock.qml:1416` `root.resetDockHover()`；
  hover 判定排除拖动态 `:1240` `!root.pointerDragActive && iconMouse.containsMouse`。
- 阻止面板自动隐藏：`Dock.qml:55` `dockHidden: ... && !pointerDragActive && ...`。

#### AC-5 小部件不得自建轮询 `[实测]`

`shell.qml:64` `readonly property bool servicePollingActive: controlCenterOpen`，
7 个服务的 `pollingActive` 绑定于此（`shell.qml:491/619/625/631/694/700/713`：
CommandRunner / Controls / NetworkSettings / SystemFeatures / PowerProfiles /
FanControl / Sound）。

**实测证据**：60 秒内每 0.3 秒采样 quickshell 子进程，仅 4 个稳定 PID、
**零瞬时 spawn**；四者均为事件驱动常驻监听
（`udevadm monitor` / `niri msg --json event-stream` / `wl-paste --watch` /
gammastep 包装）。全常驻 `repeat: true` Timer 仅 3 个且极低频：
`ClipboardHistory.qml:792`（300000ms）、`AppMenu.qml:440`（300000ms）、
`DynamicIsland.qml:2435`（`msecsToNextMinute()`，分钟对齐）。

**推论（硬性）**：小部件**只读**现成 service singleton，
**禁止**自行 spawn 进程或新建常驻 Timer；任何刷新必须门控于宿主可见性
（参照 `LeftSidebarWeather.qml:69` `running: root.visible`）。
编辑模式抖动动画亦须门控于编辑模式，不得常驻。

### A-3 内存前置事实 `[实测]`

| 指标 | 空 shell（仅 `ShellRoot {}`） | 生产 shell | 差值 |
|---|---|---|---|
| RSS | 284 MB | 658 MB | +374 MB |
| **匿名内存** | **26 MB** | **504 MB** | **+477 MB** |
| 文件映射 | 258 MB（全系统共享，PSS 仅 146 MB） | 154 MB | — |

结论：Qt/QML 引擎固定成本仅 26 MB 匿名内存；**477 MB 属 shell 自身**。

已排除的嫌疑 `[实测]`：
- 非 NVIDIA 驱动开销（同机 niri 63 MB / QQ 94 MB / nautilus 51 MB / kgx 49 MB 匿名）
- 非 THP 虚高（358 MB 走大页但逐区 `rss ≈ virt`，为真实使用）
- 非缩略图（落盘 44 KB / 3 文件）
- 非壁纸（`Wallpaper.qml` 仅 2 个 Image，且 `:1301` 已用 `sourceSize` 降解码 4096×2560）
- 非剪贴板（`ClipboardHistory.qml:93` 已做 180 字符截断）
- 非泄漏（20 秒 RSS +96 KB；35 分钟累计 CPU 13 秒 / 0.6%）

**真因**：`LazyLoader` 使用 **0 次**、`visible: false` **0 次**；
`shell.qml` 内 12 个面板启动即实例化并全程常驻。

IPC 因果实验 `[实测]`（`quickshell ipc call tahoe <fn>` 前后测 RSS）：

| 面板 | 打开增量 | 关闭后残留 |
|---|---|---|
| WindowOverview | +15 MB | **+13 MB 不回收** |
| ControlCenter | +7 MB | **+4 MB 不回收** |
| NotificationCenter | +5 MB | 0 |
| ClipboardPopup | +5 MB | 0 |
| Spotlight | +1 MB | 0 |

零外部 id 引用（LazyLoader 化阻力最小）`[实测]`：
WindowOverview / ControlCenter / Spotlight / SettingsPanel / NotificationCenter 均为 **0**；
Launchpad 2、leftSidebar 1、dock 34、dynamicIsland 43。

`WindowOverview` 13 MB 残留的**可能**归属 `[未确认]`：
`ThumbnailProvider.qml:62` `property var cache: ({})`，
`maxQueueLength: 64`、`maxCacheAgeMs: 30000`；
`WindowOverview.qml:117-118`、`:127-128` 关闭时调 `cancelRequests("window-overview")`，
但该函数自述（`ThumbnailProvider.qml:18`）为
"releases only that consumer's work" —— 取消排队请求，
**不等于**清空已完成条目；`pruneStaleThumbnails()`（`:409`）触发点是
`onWindowsServiceChanged`（`:558`），非面板关闭。
缩略图落盘仅 44 KB，故 13 MB 更可能是 QML 对象树 + QQuickPixmapCache 解码纹理。
**此条为推断，实施前须实测确认。**

### A-4 侧栏现有结构 `[代码]`

`LeftSidebar.qml:128` 的 `ColumnLayout`（`anchors.margins: 14`、`spacing: 10`）
现仅两个子项：

| 位置 | 内容 | 行号 |
|---|---|---|
| 顶部 | `segmentBar`「系统 / 天气」，固定高 34 | `:134-227` |
| 剩余 | 内容区 `Layout.fillHeight: true`，含 `LeftSidebarSystem` / `LeftSidebarWeather` | `:229-276` |

分段控件当前**硬编码二分**：
- `:148` `width: (parent.width - 4) / 2`
- `:176` `return 2 + (tab === "weather" ? width : 0);`
- `:205-217` 两个 `SegmentLabel`
- `:224` `root.currentTab = mouse.x < width / 2 ? "system" : "weather";`

改三分需同时改这四处。

面板宽度：`:30` `panelWidth: Math.max(340, Math.min(420, screenWidth - 24))`
→ 减 14px 边距后可用宽约 312–392px。

材质令牌 `[代码]` `components/TahoeGlass.js`：
`MaterialPanel="panel"`、`RadiusPanel=28`、`RadiusPanelCompact=18`；
`GlassPanel.qml` 为 Item + 单个 `TahoeGlassRegion`（`:37`），可嵌套复用。
现有卡片**不用玻璃**：`LeftSidebarSystem.qml` / `LeftSidebarWeather.qml` 中
`GlassPanel` 出现 **0** 次，用不透明 `Rectangle` + `Theme.cardFill`
（`LeftSidebarSystem.qml:30`）。

`layer.enabled` 全仓库仅 2 处（`LeftSidebarWeather.qml:190`、`:232`）。
**小部件禁止使用 `layer.enabled`**（每个离屏 FBO 均耗内存与显存，
小部件数量多则线性放大）。

### A-5 可复用数据源 `[代码]`

`services/` 共 26 个 QML singleton。与首批小部件相关者：

| 服务 | 行数 | 关键属性 | 数据模式 |
|---|---|---|---|
| `Weather.qml` | 973 | `cachePath`、`refreshIntervalMs`（10 分钟）、`dailyLimit`、`hourlyLimit` | 磁盘缓存 + 定时 |
| `Battery.qml` | 123 | `percentage`、`roundedPercentage`、`available`、`ready`（全 readonly 派生） | **UPower 事件驱动，零轮询** |
| `SystemStats.qml` | 566 | `active`、`available`、`hasFastData`、`hasMediumData` | 轮询（须确认门控）`[未确认]` |
| `Notifications.qml` | 789 | `activeModel`、`activeCount`、`historyModel`、`groupedHistoryModel` | 事件驱动 |

`SystemStats` 是否已受 `servicePollingActive` 门控 —— **未确认**，
实施系统监控小部件前必须验证；若未门控，该小部件常驻会引入新唤醒源，
违反 AC-5。

### A-6 尺寸规格设计（照 macOS，不自创）

| 规格 | 网格 | 侧栏内实测可用宽度下的边长 |
|---|---|---|
| small | 2×2 | 约 151–191px（2 列 + 10px 间距） |
| medium | 4×2 | 占满一行 |
| large | 4×4 | 占满一行 |

resize 为**三档切换**，非自由缩放 —— 拖过阈值即换档，比自由缩放简单。

### A-7 首批小部件选择依据

选择标准：数据源已存在、零新增轮询、四种数据模式各覆盖一次
（一次暴露完基类的坑）。

| 小部件 | 规格 | 数据源 | 数据模式 | 风险 |
|---|---|---|---|---|
| 电池 | small | `Battery.qml` | 事件驱动 | 最低，首选验证基类 |
| 天气 | medium | `Weather.qml` | 磁盘缓存 + 定时 | 低 |
| 日历 | medium | 纯本地计算 | 零 I/O | 低（可借鉴 `DynamicIsland.qml:2435` 分钟对齐） |
| 系统监控 | small | `SystemStats.qml` | 轮询 | **须先验证门控** `[未确认]` |

**明确不纳入首批**：任何需缩略图或大图的小部件（照片、窗口预览）。
理由：`cache: false` 全仓库 0 处使用，图片类小部件会放大既有内存问题。

---

## 第三部分：C — 既有文档遗留项的核实结果

用户要求「将这个文档里面的内容也修复好」，指
`docs/click-first-hit-swallow-and-wallpaper-boot-postmortem-2026-08-02.md` §6
「遗留观察项（未修，低优先）」。本次逐条核实结果如下。

### C-1 `prestartedWallpaperReadyTimer` 死代码 —— **成立，需修** `[代码]`

postmortem 原文：「`prestartedWallpaperReadyTimer` 死代码」。

核实：`tahoe-shell/components/Wallpaper.qml` 中该 Timer 定义于 `:1417-1427`
（`interval: 1600`、`repeat: false`），全文件仅有 **一处**引用 ——
`:845` 的 `prestartedWallpaperReadyTimer.stop()`。
**从无 `start()` / `restart()` 调用**，`onTriggered` 内的
`dynamicActive = true` / `restartCoverVisible = false` 永不执行。

结论：确为死代码。属 `constraints.md` G-5（禁止占位/死代码）范畴。

### C-2 record generation 守护恒假 —— **成立，需修** `[代码]`

postmortem 原文：「record generation 守护恒假（722 行）」。

核实 `Wallpaper.qml` 中两个 generation 属性的全部读写点：

| 行号 | 代码 | 作用 |
|---|---|---|
| `:213` | `property int prestartRecordGeneration: 0` | 声明 |
| `:218` | `property int prestartReloadGeneration: 0` | 声明 |
| `:711` | `prestartReloadGeneration = ++prestartRecordGeneration;` | **同时赋为同值** |
| `:728` | `if (prestartReloadGeneration !== prestartRecordGeneration) return;` | 守护 |

因 `:711` 把两者赋成同一个值，且此后无任何一方单独变更，
`:728` 的守护条件**恒为假**，其注释声称的
"A completion from a superseded reload must not mutate state."
（防止被取代的异步 reload 完成后污染状态）**实际从未生效**。

这是 `constraints.md` P-7（C3 异步化双门不变量）的一个残留缺口：
双门中的「完成回调须校验代次」这一门形同虚设。

### C-3 预存失败的测试 —— **已不成立，postmortem 记录过时** `[实测]`

postmortem 原文：「预存失败：`test_r17_dock_layout_motion.py:259`
（quickshell tahoe_glass `mappingGeneration`，与本批无关）」。

核实：实际运行该测试文件 —— **11 passed in 0.02s，全绿**。

结论：该项已在此后的改动中被修复（推测为 quickshell fork 的
`b022253 fix(tahoe-glass): T08 per-wl_surface mapping generation lifecycle`），
postmortem 的记录已过时。**本次任务需更新 postmortem 文档，划掉此项。**

### C-4 其余三项 —— 本次不处理，理由如下

| 遗留项 | 不处理理由 |
|---|---|
| touch/tablet 仍 down 时切焦点（`input/mod.rs:4425`/`:3855`） | postmortem 已注明「镜像需 per-slot 位置缓存，单独立项」；属 P-6（C7）辖区，`constraints.md` 明确本次不应触及该块 |
| warp/`set_location` 后 `pointer_pos` 缓存不回写 | 同属 C7 辖区；且 postmortem 判定 `16696344` 的 hunk 属「过度修复」，需先厘清才能动 |
| supervisor 被 SIGKILL 而引擎孤儿存活 | postmortem 已记载「可达性极低，审查权衡接受」，根治需按 token/cmdline 扫孤儿，属独立课题 |
| 四条理论级 PLAUSIBLE | postmortem 判定「现实触发≈0」 |

---

## 第四部分：实施顺序结论

1. **C 先于 B 与 A** —— C1/C2/C3 均为小范围、零依赖的确定性缺陷，
   合为一个任务先行清理，避免它们在后续 A 项壁纸/异步相关改动中造成干扰。
   C2 尤其重要：它是异步双门的残留缺口，而 A 项涉及配置文件异步读写，
   同类模式若沿用错误先例会扩散。
2. **B 先于 A** —— 理由见 B-4。
3. A 内部：LazyLoader 内存地基 → 基类与宿主 → 首批小部件 →
   **库 tab（添加入口）→ 库实时预览** → 长按编辑与拖动 → resize。
   **添加能力必须先于编辑能力**：在库 tab 完成前，小部件只能靠手工编辑配置文件
   放置，用户无从添加，此时做编辑模式是本末倒置；
   且只有用户能自由添加后（≥3 个小部件），拖动重排才可被有意义地测试。

详见同目录 `roadmap.md`（任务分解）、`constraints.md`（硬约束）、
`execution-plan.md`（执行计划与验收）。


---

## 第五部分：D — 关闭窗口后 GPU 显存泄漏（D-1）

### D-1 现象与量化 `[实测]`

用户报告：nvidia-smi 中 niri 进程显存从开机 ~100 MiB 一路涨到 1 GB+，
关闭窗口后不回落，与「打开/关闭窗口」直接相关。

2026-08-12 在真实会话上的受控实测（nvidia-smi 进程表，PID 1290）：

| 实验 | 结果 |
|---|---|
| 空闲 70 秒 | niri 867 MiB 纹丝不动 |
| 开/关 alacritty（800×635 逻辑）20 轮 | 1326 → 1486 MiB，**每轮恰好 +8 MiB，完美线性** |
| 开/关 300×80 大窗 1 轮 | 一轮净增 **+125 MiB**（与窗口尺寸成比例） |
| `window-close off`（禁用关闭动画）3 轮 | 仍每轮 +8 MiB（与动画无关） |
| 关窗后强制全量重绘（do-screen-transition） | 泄漏不释放（非延迟释放） |
| Firefox 最大化开→关（用户实测） | 一次涨几十 MiB |

结论 `[实测]`：**每关闭一个窗口，niri 进程的显存读数增长与窗口尺寸成正比**
（小窗约 +8 MiB/轮；最大化/大窗一轮几十到一百多 MiB），20 轮无收敛；
后续完整诊断（D-4/D-5）证明这是 **NVIDIA 驱动保留已释放纹理显存**，
回收部分且延迟（用户实测「有时回收、有时不回收」），非 niri 代码泄漏。

### D-2 排除项 `[实测]`（含后来修正的结论）

- 非关闭动画纹理：`window-close off` 后泄漏量完全相同。
- 非「延迟到下一帧才释放」：强制全量重绘后仍不释放。
- 非窗口工作集：窗口已全部关闭仍继续增长。
- ~~非 NVIDIA 驱动堆~~ **此条最初被排除，经完整诊断（D-5）后推翻**：
  早期仅凭「20 轮线性不收敛」判断，遗漏了驱动堆在组合器 GL 用法下的
  高水位特征；带 smithay 计数后确认**就是驱动堆保留**。

### D-3 上游对照 `[代码] + [外部]`

- niri-wm/niri#1869（关窗后显存不释放，plateau 650MB–1GB）→ 26.04 已由
  PR #3404（dead surface hook）修复；本 fork 已包含该修复
  （`niri/src/handlers/compositor.rs:543-567`）。
- niri-wm/niri#4372（26.04 + NVIDIA：Firefox 每实例 +~70 MiB 不释放，
  NVIDIA profile 无效，未结案）——与 D-1 现象高度吻合。
- Smithay/smithay#1562（关窗 VRAM 泄漏，niri/cosmic 均报；niri 侧定论为
  dead surface hook，已修）。

### D-4 根因（2026-08-12）

**结论 `[实测]`：不是 niri / smithay 代码泄漏——API 层资源全部释放
（结构归零 + `glDeleteTextures` 正常调用），但 nvidia-smi 的 niri 显存读数
仍随开/关窗增长且回收部分、延迟。显存保留发生在 NVIDIA 驱动侧。**

**机制归属 `[未确认]`**：上游资料（niri wiki / #1962 / NVIDIA egl-wayland#126）
将其归因于 GL 驱动 per-process reuse heap（`GLVidHeapReuseRatio`），本机安装
该 profile 后短时实验**未观察到立竿见影**，故「具体是 reuse heap」为上游
推断而非本机实测；本机只确认「GL 对象已删、显存读数仍保留」。

候选保留点（D-4 初版三条）经诊断**全部排除**：

1. ~~客户端导入纹理的 GlesTexture clone 被 niri 侧持有~~：live 计数显示
   closing_entries=0、unmap_snapshot_tiles=0、unmapped_windows=0、
   root_surface 回到基线、retained_blur_mib 回到 16.6 基线。
2. ~~`unmapped_windows` / `root_surface` 等 map 持有死对象~~：各 map 长度
   在 churn 后全部回到基线。
3. ~~smithay buffers/dmabuf_cache 未清理~~：`buffers=2` 全程恒定，
   `dmabuf_cache` 回到 30；且 **`glDeleteTextures` 有 161 条 cleanup 事件
   （合计 546 次调用；含大窗轮共 268 条/683 次）**
   （全部发生在受控 churn 期间），证明纹理已在 GL API 层释放。

即：**API 层全部释放，显存仍线性增长 → 驱动层保留**。


### D-5 修复与验证 `[实测] + [外部]`

- **修复**：为 niri 启用 NVIDIA 驱动自带的 `No VidMem Reuse` profile
  （`GLVidHeapReuseRatio=0`）。驱动内置规则只匹配 plasmashell /
  cosmic-comp / Hyprland / Xwayland / libkwin 等，**不含 niri**，需自行配置。
  用户级文件（无需 root）：`~/.nv/nvidia-application-profiles-rc`。
- **验证方法**：装 profile 后重启会话，跑 10 轮小窗 + 1 轮大窗受控循环，
  如实记录 niri 显存增长/回收（对照 D-1 基线的每轮 +8 MiB；
  社区报告预期回落至 ~100–200 MiB，见下实测）。
- **实测补充（2026-08-12，profile 已装）**：+8 MiB/轮增长仍在（10 轮后
  +82 MiB），关闭 3 个大窗口后 niri 仅立即回落 ~30 MiB，随后 2 分钟持平——
  **驱动回收是部分、延迟、时序相关的**（用户亦观察到「有时回收、有时不回收」：
  开机时回收快，长时间/高水位后回收慢且不完整）。`GLVidHeapReuseRatio=0`
  是社区广泛验证的缓解手段（#1962：2.5 GiB→168 MiB），但本机短时实验未观察到
  立竿见影的效果；保留该配置并建议长周期观察。
- **计数口径勘误**：`glDeleteTextures` 的 smithay 本地补丁按「每次 cleanup
  批次的删除数」打印：10 轮小窗阶段共 **161 条 cleanup 事件（合计 546 次
  调用）**，含大窗轮共 **268 条 / 683 次**；`dmabuf_cache` churn 峰值 **34**
  （非 33），`buffers` 在启动瞬间出现过 1、受控循环期间恒为 2。
- **最终代码计数**：`unmapped_inserted/removed` 与 `dmabuf_hook_added/removed`
  在最终交付代码中四路径全部配对（诊断用中间构建曾缺 unmapped 移除计数，
  日志中 `+1/-0` 即来自该中间构建；live 计数不受影响）。
- 上游对照：niri-wm/niri#1962（wiki 记载 profile 方案，2.5 GiB→168 MiB）、
  NVIDIA/egl-wayland#126（NVIDIA 工程师 cubanismo：组合器典型 GL 用法下
  驱动保留启发式不理想，非真泄漏）。
- **D1 交付物**：niri 侧 env 门控显存诊断（`NIRI_LIFECYCLE_DIAG=1` 时输出
  live 计数与关窗事件计数）保留，供以后复核；smithay 本地观察补丁为
  临时手段，已移除不入库。
