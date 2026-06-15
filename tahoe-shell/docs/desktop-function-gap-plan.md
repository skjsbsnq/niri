# Tahoe 桌面功能补齐差距清单

日期：2026-06-15

基于：`tahoe-shell/`、`niri/` fork、`config/niri/tahoe-phase0.kdl`、`tahoe-shell/docs/gap-analysis.md`。

本文档目的：把当前优先开工的 4 类功能缺口整理成和 `gap-analysis.md` 同风格的可执行清单。本文只跟踪功能补齐，不再把 Phase 3/Phase 5 未打勾项、真机验收和测试清单作为本轮阻塞项。

---

## 一、窗口管理与 niri IPC 服务层

### 当前状态

- `tahoe-shell/services/Niri.qml` 只接了 Quickshell 的 `ToplevelManager.toplevels` 和 `WindowManager.windowsets`。
- Dock 可以显示窗口、activate、restore/minimize 状态。
- niri fork 已经有 `WindowsChanged`、IPC window state、minimize/restore 等基础。
- 2026-06-15 已开工：新增 `services/NiriIpc.qml`，先用 `niri msg --json windows` 快照轮询；`services/Niri.qml` 已暴露 `windowList`、`focusedWindow`、`recentWindowList`，Dock 运行状态和顶栏当前应用已开始优先读取统一窗口模型。
- 2026-06-15 已补配置：`config/niri/tahoe-phase0.kdl` 显式启用 `recent-windows`，只配置高亮、预览和时序参数；快捷键保留 niri 默认 MRU 绑定，避免覆盖 compositor 自带 Alt/Mod+Tab 和同应用切换逻辑。窗口切换先复用 niri compositor 侧 MRU 逻辑，不在 Quickshell 里重复实现键盘释放确认。

### 功能缺口

- 没有直接接 niri IPC socket / `niri msg --json` 事件流。
- shell 拿不到稳定的窗口几何、输出、workspace、焦点变化、布局变化实时数据。
- 没有桌面级窗口切换 UI，例如 Alt-Tab / Cmd-Tab 风格 switcher。
- 没有明确的 stacking WM 行为补齐：点击 raise、raise/lower、窗口激活顺序、最小化窗口恢复后的层级策略。
- 还不能支撑窗口预览、Stage Manager、Mission Control、精确 Dock target rect 等后续能力。

### 为什么优先

这是后续桌面功能的底座。继续只靠 `ToplevelManager` 可以做外观和基础 activate，但做不了准确窗口预览、切换器、Stage Manager、Dock Genie target、复杂 workspace UI。

### 建议实现顺序

1. 新增 `services/NiriIpc.qml`，先用 `niri msg --json windows` 做一次性快照。
2. 在服务层统一窗口模型，保留 Quickshell toplevel 对象，同时合并 niri IPC 中的 id、app_id、title、workspace、output、focused、is_minimized、geometry。
3. 接入 niri event stream，如果当前 fork/CLI 可用，优先使用事件流；否则短期用低频刷新作为降级。
4. 将 Dock 的运行状态判断从 appId 模糊匹配逐步迁移到统一窗口模型。
5. 显式配置 niri `recent-windows` 视觉/时序参数作为第一版 Alt-Tab UI；快捷键继续使用 niri 默认 MRU 绑定。Quickshell 侧保留 `recentWindowList` 给后续自定义外观或 Stage Manager 使用。
6. 补 compositor 侧需要的 action：raise/lower 或 activate 后 raise，视 niri fork 当前语义决定。

### 完成标准

- shell 有一个统一的窗口状态服务，不再只有 `ToplevelManager` 裸数据。
- Dock、窗口列表、切换器都读同一份窗口模型。
- 能知道当前 focused window、窗口所在 workspace/output 和基础几何。
- 最小窗口切换 UI 可用。
- activate/restore 后窗口层级行为可预测。

---

## 二、系统级桌面能力

### 当前状态

- 控制中心已经有真实音量、亮度、Wi-Fi、蓝牙、MPRIS。
- 通知 toast 已经接 `NotificationServer`。
- 顶栏已有系统托盘、workspace、通知、Spotlight、时钟、控制中心入口。

### 功能缺口

- 没有电池状态和电池弹层。
- 没有电源菜单：锁定、注销、重启、关机、睡眠。
- 没有自有锁屏 UI，目前锁屏即使可用也不是 Tahoe shell 自己的体验。
- 没有输入法状态和输入法切换入口。
- 没有 DND / 勿扰模式，通知只有当前 toast，没有通知历史中心。
- 没有夜间模式 / 深浅色模式开关。
- 没有截图、录屏、Quick Look。

### 为什么优先

这些不是拟真细节，而是桌面日用入口。没有电源、锁屏、电池、输入法和通知历史，用户仍需要回到外部环境或命令行完成常见操作。

### 建议实现顺序

1. 新增 `services/Power.qml`：封装关机、重启、注销、睡眠、锁屏命令；先用 systemd/logind 常规命令，所有危险操作走确认弹窗。
2. 新增 `PowerMenu.qml`：从顶栏 Tahoe 菜单或控制中心入口打开。
3. 新增 `services/Battery.qml`：优先接 UPower DBus；不可用时降级为空状态。
4. 顶栏补电池图标/百分比/充电状态，点击打开电池 popup。
5. 通知服务补 history model、clear all、按 appId 分组的最低实现。
6. 增加 DND 状态，至少能阻止 toast 弹出并保留历史。
7. 输入法状态后置，先调研当前环境是 fcitx5、ibus 还是其他。

### 完成标准

- 顶栏能显示电池，电池 popup 有电量、充电状态、电源来源。
- 有可用电源菜单，关机/重启/注销/睡眠/锁屏至少有安全确认。
- 通知不再只有单条 toast，能打开历史列表并清空。
- DND 能阻止 toast 干扰。
- 输入法状态至少有可见指示和后续接入方案。

---

## 三、Dock 完整化

### 当前状态

- Dock 有固定 app、真实窗口列表、运行状态、activate/restore。
- Dock magnification 和 bounce 动画已做。
- 分隔线存在，但右侧功能区为空。

### 功能缺口

- 没有 Downloads / Trash / 最近项目右段。
- 没有 Dock 图标拖拽重排。
- 没有拖入 Dock 固定应用。
- 没有 App 角标。
- 没有 Dock 自动隐藏。
- 没有拖文件到 Dock 图标打开。
- 当前运行状态和 app 匹配仍依赖 appId 映射，复杂应用可能误判。

### 为什么优先

Dock 是这个桌面的主要任务栏。现在它能完成窗口闭环，但还不像一个完整桌面 Dock。右段和拖拽能力会明显提高日用效率。

### 建议实现顺序

1. 先补右段静态功能区：Downloads、Trash。
2. Downloads 打开文件管理器对应目录；Trash 打开 trash URI 或文件管理器回收站入口。
3. 固定 app 配置集中化，保存在项目可控配置文件或 Quickshell 可写状态中。
4. 加 Dock 图标拖拽重排，先只支持固定 app 间重排。
5. 加从 Launchpad / `.desktop` 结果拖入 Dock 固定。
6. 接通知或窗口状态后再做角标。
7. 自动隐藏放最后，避免先影响窗口操作和 layer-shell 占位。

### 完成标准

- Dock 右段有 Downloads 和 Trash，并能打开真实目标。
- 固定 app 可以重排，重启 shell 后顺序保留。
- 可以把应用固定到 Dock，也可以移除固定。
- Dock 运行状态基于统一窗口模型，误判明显减少。

---

## 四、搜索与菜单

### 当前状态

- Launchpad 已有 `.desktop` 应用搜索和 Enter 启动第一条。
- Spotlight 已有 overlay、应用搜索结果、Enter 启动、Escape/外部点击关闭。
- `MenuPopup.qml` 仍是写死的假菜单。

### 功能缺口

- Spotlight 只搜应用，不搜文件、设置项、计算、命令。
- 没有搜索 provider 分层，后续扩展会堆到一个组件里。
- 没有最近搜索/最近应用。
- 没有菜单栏 app menu 接入。
- Tahoe 菜单没有真实 About、Settings、电源入口。
- 没有右键上下文菜单。

### 为什么优先

Spotlight 和菜单是桌面导航入口。应用搜索已经完成，继续扩成 provider 架构，可以同时服务 Spotlight、Launchpad、菜单和 Dock 固定。

### 建议实现顺序

1. 新增 `services/Search.qml`，定义 provider 结果格式：`id`、`title`、`subtitle`、`icon`、`kind`、`score`、`activate()`。
2. 把应用搜索从 `Apps.qml` 抽成 App provider，Spotlight 和 Launchpad 共用。
3. 增加 calculator provider，支持基础四则运算。
4. 增加 command provider，支持显式前缀，例如 `>`。
5. 增加 settings/action provider，先覆盖电源菜单、控制中心、通知中心、壁纸等 Tahoe 自己的入口。
6. 文件搜索后置，先调研 `fd`/`locate`/tracker 的可用性和性能。
7. `MenuPopup.qml` 先做真实 Tahoe 菜单：About、Settings、Lock、Sleep、Restart、Shutdown；app menu/dbus-menu 作为后续专项。

### 完成标准

- Spotlight 不再直接依赖 `Apps.qml`，而是读取统一 Search 服务。
- Spotlight 至少支持应用、计算、命令、Tahoe 动作入口。
- Tahoe 菜单点击项有真实行为，不再只是关闭弹窗。
- app menu/dbus-menu 有明确调研结论，即使不在本轮实现。

---

## 本轮不跟踪

- Phase 3 / Phase 5 中已经实际验收但未打勾的项目。
- 最终真机验收。
- 测试清单完成率。
- 纯视觉拟真，例如图标统一、字体替换、动态壁纸。

---

## 推荐开工顺序

1. `NiriIpc.qml` 和统一窗口模型。
2. 最小 Alt-Tab / 窗口切换 UI。
3. `Power.qml`、`Battery.qml` 和电源菜单。
4. Dock 右段 Downloads / Trash。
5. `Search.qml` provider 架构和 Spotlight 扩展。
6. Tahoe 菜单真实动作。
