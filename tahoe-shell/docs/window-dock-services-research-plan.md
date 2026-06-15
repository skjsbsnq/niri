# Tahoe Shell 窗口管理、Dock 状态与系统服务研究报告及执行计划

日期：2026-06-15

范围：本报告只研究当前优先级中的三条主线：

1. 窗口管理语义
2. Dock / Shell 状态持久化
3. 系统服务整合

对标对象：macOS 26 / Tahoe 方向的日用桌面体验。

结论先行：当前项目已经有真实 compositor 能力和真实 shell 服务，不是视觉 mock。但二、三、五这三条线还没有形成“桌面产品级 contract”。下一阶段不应继续堆占位 UI，而应优先把 niri 的窗口事件、Shell 的用户状态、Linux 系统服务包装成稳定、可测试、可恢复的三层模型。

## 1. 总体判断

### 1.1 当前状态

当前 Tahoe Shell / niri fork 的核心能力分布如下：

| 模块 | 当前状态 | 主要问题 |
| --- | --- | --- |
| niri 窗口能力 | 已有 minimize / restore / snap / MRU / event stream 基础 | Shell 没完全消费事件流，窗口 action contract 不完整 |
| Shell 窗口模型 | `Niri.qml` 合并 Quickshell `ToplevelManager` 和 `niri msg --json windows` | `NiriIpc.qml` 仍是 1200ms 轮询快照 |
| Dock | 有 pinned apps、运行窗口、放大、bounce、运行点 | pinned 状态来自启发式，不是用户持久状态 |
| 控制中心 | 音量、亮度、Wi-Fi、蓝牙、MPRIS 已接真实后端 | 深色模式、夜间模式、显示器、电源策略等仍缺 |
| 通知 | 已接 `NotificationServer`、历史、DND | 缺按应用分组、持久历史策略、设置入口 |
| 电源菜单 | 锁屏、睡眠、注销、重启、关机已接真实命令 | 锁屏 UI 依赖 swaylock/gtklock，不是 Tahoe 自己的体验 |
| 输入法 / 截图录屏 / 设置 | 基本未完成 | 直接影响中文环境和主力日用 |

### 1.2 核心差距

与 macOS 26 的差距不主要在“有没有玻璃效果”，而在三类 contract：

1. **窗口 contract**：窗口生命周期、焦点、最小化、恢复、工作区、显示器、MRU、z-order、截图/录屏、overview 需要一套事件驱动模型。
2. **用户状态 contract**：Dock、偏好设置、固定项、排序、特殊目录、通知设置、外观设置必须持久化，并且不能被部署脚本覆盖。
3. **系统服务 contract**：输入法、锁屏、截图、显示器、电源、夜间模式、设置、文件/Trash 需要从“调用命令”变成可查询、可显示状态、可失败降级的服务层。

### 1.3 推荐优先级

优先级顺序：

1. **窗口事件模型和统一 action contract**
2. **Dock 持久化和应用/窗口身份模型**
3. **输入法、截图、锁屏、设置、显示器/电源等系统服务**

原因：Dock 和系统服务最终都依赖窗口/工作区/输出设备状态。如果窗口模型继续靠轮询和两个来源临时合并，后续 Dock、Alt-Tab、Mission Control、截图 UI、设置面板都会反复返工。

## 2. 窗口管理研究

### 2.1 已有能力

niri fork 侧已有相当多可以直接利用的能力：

- `niri/niri-ipc/src/lib.rs` 已有 `Request::EventStream`。
- `Event` 已覆盖：
  - `WorkspacesChanged`
  - `WorkspaceUrgencyChanged`
  - `WorkspaceActivated`
  - `WorkspaceActiveWindowChanged`
  - `WindowsChanged`
  - `WindowOpenedOrChanged`
  - `WindowClosed`
  - `WindowFocusChanged`
  - `WindowFocusTimestampChanged`
  - `WindowUrgencyChanged`
  - `WindowLayoutsChanged`
  - `KeyboardLayoutsChanged`
  - `KeyboardLayoutSwitched`
  - `OverviewOpenedOrClosed`
- `Window` 结构已包含：
  - `id`
  - `title`
  - `app_id`
  - `pid`
  - `workspace_id`
  - `is_focused`
  - `is_floating`
  - `is_urgent`
  - `is_minimized`
  - `layout`
  - `focus_timestamp`
- `Action::MinimizeWindow { id }` 和 `Action::RestoreWindow { id }` 已存在。
- xdg shell 和 foreign-toplevel minimize state 已接入。
- `recent-windows` / MRU UI 已在 niri compositor 侧存在，配置中已启用。
- `SnapEdge` 当前是 `Left / Right / Top`，说明左右半屏和顶边最大化已实现，但四角吸附还没有。

这说明窗口管理不是从零开始，关键是 Shell 侧没有把这些能力变成一个实时、统一、可测试的窗口模型。

### 2.2 当前 Shell 实现

当前 Shell 侧主要文件：

- `tahoe-shell/services/NiriIpc.qml`
- `tahoe-shell/services/Niri.qml`
- `tahoe-shell/components/Dock.qml`
- `tahoe-shell/components/WindowButton.qml`
- `tahoe-shell/components/TopBar.qml`

关键观察：

1. `NiriIpc.qml` 通过 `Process { command: ["niri", "msg", "--json", "windows"] }` 获取窗口快照。
2. `pollInterval` 是 1200ms，属于低成本快照轮询。
3. `Niri.qml` 把 Quickshell `ToplevelManager.toplevels` 和 niri IPC windows 合并成 `windowList`。
4. `recentWindowList` 已按 `focusTimestamp` 排序。
5. `WindowButton.qml` 仍直接操作 Quickshell toplevel 的 `minimized` / `activate()`，没有统一走 `Niri.qml` 的窗口 action。
6. `Dock.qml` 运行窗口部分仍使用 `root.niriService.toplevels`，不是统一窗口模型 `windowList`。

这套实现可以把 UI 跑起来，但不适合作为完整桌面的长期基础。

### 2.3 问题分解

#### 2.3.1 轮询模型的问题

轮询快照的问题不是性能本身，而是语义不稳定：

- 窗口打开/关闭最多延迟 1.2 秒。
- 快速 minimize / restore / focus 可能出现短时间 UI 状态错乱。
- Dock、TopBar、Alt-Tab、overview、截图 UI 都会各自补偿延迟，最终产生重复逻辑。
- 无法可靠表达事件顺序，例如窗口先换工作区再改焦点。
- 不能自然处理 niri 重启、IPC 断线、事件乱序、恢复快照。

niri 已经提供 `EventStream`，所以轮询应当退为 fallback，而不是主路径。

#### 2.3.2 双模型合并的问题

`ToplevelManager` 有好处：它提供 Wayland foreign-toplevel 对象，可以调用 `activate()`、设置 `minimized`、设置 dock rectangle。

niri IPC 有好处：它提供稳定 niri id、workspace id、layout、focus timestamp、is_minimized。

当前的合并方式是按 appId/title 进行弱匹配。这个方向可以继续，但必须变成明确的 `WindowRecord` 模型：

```text
WindowRecord
  id                niri window id, primary key when available
  toplevel          Quickshell toplevel object, optional
  title
  appId
  pid
  workspaceId
  outputName
  layout
  geometry
  isFocused
  isFloating
  isMinimized
  isUrgent
  focusTimestamp
  appKey            normalized desktop/app identity
  capabilities      canFocus/canMinimize/canRestore/canClose/canScreenshot...
```

Shell UI 只能消费 `WindowRecord`，不能有的地方消费 toplevel，有的地方消费 ipc window。

#### 2.3.3 action contract 不完整

必须集中到 `Niri.qml` 或新建 `WindowManager.qml`，避免组件直接改 toplevel 状态。

最小 action 集：

```text
focusWindow(windowId)
minimizeWindow(windowId)
restoreWindow(windowId)
toggleMinimizeWindow(windowId)
closeWindow(windowId)
fullscreenWindow(windowId)
moveWindowToWorkspace(windowId, workspaceId)
moveWindowToOutput(windowId, outputName)
toggleFloating(windowId)
activateWorkspace(workspaceId)
openOverview()
closeOverview()
```

如果 niri 已有对应 action，Shell 直接调用。如果没有，需要在 niri IPC 增补，而不是在 Shell 里绕过。

#### 2.3.4 z-order / raise / lower 语义

niri 当前 floating activation 会 raise 到前面，focus-follows-mouse 有 `activate_window_without_raising`。这说明内部已有“激活但不提升”和“激活并提升”的分野。

但 Shell 暂时没有显式的 raise/lower action。macOS 式 Dock 和窗口切换需要明确策略：

- 点击 Dock 中未最小化窗口：focus + raise。
- 点击当前 active 窗口图标：是否 minimize，需要作为 Dock 偏好。
- 恢复最小化窗口：restore + focus + raise。
- 多窗口 app：点击 app 图标显示窗口列表，还是轮转窗口，需要作为行为策略。

如果 niri 不暴露 raise/lower，Shell 只能依赖 focusWindow 的隐式行为，后续会限制 Mission Control 和 Dock 窗口组。

### 2.4 窗口管理执行计划

#### W0：保留现状，建立基线

目标：先不破坏现有 Dock 和 TopBar。

任务：

- 给 `Niri.qml` 当前 `windowList` 定义文档化字段。
- 增加 debug dump 方法：输出当前 windows/workspaces/focused/recent。
- 明确 fallback 规则：事件流不可用时使用当前轮询。
- 为 minimize / restore / focus 做手动验收脚本。

验收：

- 打开 5 个应用，窗口列表字段完整。
- minimize / restore 后 `isMinimized` 状态能恢复。
- 关闭窗口后不会残留 Dock 项。

#### W1：用 niri EventStream 替代主轮询

目标：让窗口模型实时更新。

技术路径：

- 在 `NiriIpc.qml` 中新增长期 `Process`：

```qml
Process {
    running: true
    command: ["niri", "msg", "--json", "event-stream"]
    stdout: SplitParser {
        splitMarker: "\n"
        onRead: root.applyEvent(JSON.parse(data))
    }
}
```

- 保留 `niri msg --json windows` 作为：
  - 首次同步
  - event stream 断线后的重建
  - JSON parse error 后的恢复
- 按 niri `Event` 语义维护：
  - `windowsById`
  - `windows`
  - `workspacesById`
  - `workspaces`
  - `focusedWindowId`
  - `recentWindowList`

注意：niri 文档已说明 event stream 初始事件可能存在工作区/窗口顺序不一致，Shell 必须容忍短暂 dangling workspace id。

验收：

- 打开/关闭/focus/minimize/restore/snap 的 UI 更新延迟小于 150ms。
- 正常运行时不再每 1.2 秒执行 `niri msg windows`。
- 杀掉 event-stream 子进程后能自动回退并重连。
- Quickshell reload 后状态能恢复。

#### W2：统一 WindowRecord 和组件消费路径

目标：让所有 UI 消费同一个窗口模型。

任务：

- `Dock.qml` 运行窗口模型从 `niriService.toplevels` 改为 `niriService.windowList`。
- `WindowButton.qml` 的输入从 `toplevel` 改成 `windowRecord`。
- `WindowButton.qml` 的动作统一调用 `niriService.activateWindow(record)` / `minimizeWindow(record)` / `restoreWindow(record)`。
- `TopBar.qml` active app 使用 `focusedWindow`。
- Quickshell toplevel 仅作为 `WindowRecord.toplevel` 的能力补充，不作为 UI 主模型。

验收：

- niri IPC 有 id 的窗口走 niri action。
- 没有 id 的 legacy/异常窗口仍能通过 toplevel fallback 激活或最小化。
- Dock、TopBar、recentWindowList 对同一个窗口状态显示一致。

#### W3：窗口组、MRU、overview 策略

目标：接近 macOS Dock 和 Mission Control 的行为。

任务：

- Dock 按 `appKey` 聚合窗口。
- app 有多个窗口时点击显示窗口菜单或 Expose-style 选择器。
- 使用 `focusTimestamp` 实现 Shell 层 MRU 列表，但默认继续复用 niri compositor 的 `recent-windows`。
- 为 minimized windows 提供单独样式和恢复顺序。
- 研究是否需要 niri 侧暴露 `raiseWindow` / `lowerWindow` / `cycleAppWindows`。

验收：

- 同一 app 多窗口不会在 Dock 中表现混乱。
- minimized window 能从 Dock 恢复到正确工作区。
- 多工作区、多显示器下 Dock 点击行为可预测。

#### W4：Snap / Spaces / Mission Control 补齐

目标：增强 macOS 级窗口编排。

任务：

- niri 侧扩展 `SnapEdge` 到四角：
  - `TopLeft`
  - `TopRight`
  - `BottomLeft`
  - `BottomRight`
- 增加分屏候选窗口选择逻辑。
- Shell 侧增加窗口概览 UI 时，只消费事件模型，不直接查询 compositor。
- 验证 fractional scale、多显示器、触控板手势。

验收：

- 左/右/四角/最大化 snap 行为一致。
- 概览 UI 不依赖轮询。
- 真机 GPU 下动画不丢帧、不出现 texture 消失。

## 3. Dock / Shell 状态持久化研究

### 3.1 当前实现

当前 Dock 相关文件：

- `tahoe-shell/components/Dock.qml`
- `tahoe-shell/components/WindowButton.qml`
- `tahoe-shell/services/Apps.qml`

关键观察：

1. `Apps.qml` 中 `pinnedApps` 是 `readonly property var pinnedApps: buildPinnedApps()`。
2. `buildPinnedApps()` 通过当前系统存在的 desktop entries 启发式寻找 Files、Terminal、Browser、Settings。
3. `Dock.qml` pinned 区域直接渲染 `appsService.pinnedApps`。
4. 没有用户配置文件。
5. 没有拖拽排序。
6. 没有拖拽 pin / unpin。
7. 没有 Downloads / Trash 右侧特殊区。
8. 运行状态靠 `appHasRunningWindow(app, niriService.windowList)` 的 appId/token 模糊匹配。

这说明 Dock 现在是“自动生成的初始 Dock”，还不是用户 Dock。

### 3.2 为什么 Dock 必须单独建状态模型

macOS Dock 不是简单 app 列表，它至少有四类对象：

1. 固定应用
2. 运行中但未固定应用
3. 特殊项目：Downloads、Trash、recent items、separator
4. 用户行为状态：排序、放大、自动隐藏、是否显示最近应用、点击策略

这些状态不能放在 `Apps.qml` 里，因为 `Apps.qml` 是应用发现服务，不是用户偏好服务。

也不能存到部署后的 `~/.config/quickshell/tahoe/` 目录里，因为当前部署流程会用 `rsync -a --delete tahoe-shell/ ~/.config/quickshell/tahoe/` 覆盖该目录。用户状态必须放在独立路径。

推荐路径：

```text
$XDG_CONFIG_HOME/tahoe-shell/dock.json
```

备用：

```text
~/.config/tahoe-shell/dock.json
```

### 3.3 Dock 数据模型建议

新增服务：

```text
tahoe-shell/services/DockState.qml
```

配置 schema：

```json
{
  "version": 1,
  "pinnedItems": [
    {
      "type": "shellAction",
      "id": "launchpad",
      "label": "Launchpad",
      "icon": "launchpad.png"
    },
    {
      "type": "desktopApp",
      "desktopEntryId": "org.gnome.Nautilus.desktop",
      "fallbackAppId": "org.gnome.Nautilus",
      "label": "Files"
    }
  ],
  "rightItems": [
    {
      "type": "downloads",
      "path": "$HOME/Downloads"
    },
    {
      "type": "trash"
    }
  ],
  "behavior": {
    "groupWindowsByApp": true,
    "showRecentApplications": false,
    "clickActiveWindowToMinimize": true,
    "magnification": true,
    "autoHide": false,
    "position": "bottom"
  }
}
```

实现选型：

- Quickshell 已有 `FileView` 和 `JsonAdapter`，适合直接做 JSON 读写。
- 写入使用 atomic writes。
- 首次启动没有配置时，用当前 `buildPinnedApps()` 生成默认配置。
- 配置损坏时保留 `.broken.TIMESTAMP`，重新生成默认配置。

### 3.4 应用身份模型

Dock 的核心难点不是画图标，而是判断“这个窗口属于哪个 Dock app”。

当前 `Apps.qml` 已有：

- `normalizedAppToken`
- `appIdentityTokens`
- `tokensReferToSameApp`
- `appMatchesToplevel`
- `appHasRunningWindow`

这些函数可以升级为正式 `AppIdentity`：

```text
AppIdentity
  desktopEntryId
  appId
  startupClass
  execToken
  wmClassFallback
  pid
  normalizedTokens[]
```

推荐新增：

```text
tahoe-shell/services/AppRegistry.qml
```

职责：

- 从 `DesktopEntries.applications` 建立 `desktopEntryId -> app`。
- 从 appId/startupClass/exec token 建立反向索引。
- 为窗口计算 `appKey`。
- 为 Dock item 找到最佳 app。
- 处理 app 卸载、desktop file 改名、Flatpak/Snap id 差异。

如果不想马上拆文件，至少应把这组函数从“用于运行点显示”提升为“Dock 和窗口模型共用的身份层”。

### 3.5 Dock 交互执行计划

#### D0：建立 DockState 服务

目标：pinned apps 从只读启发式变成用户配置。

任务：

- 新增 `DockState.qml`。
- 使用 `FileView + JsonAdapter` 管理 `$XDG_CONFIG_HOME/tahoe-shell/dock.json`。
- `Apps.qml.buildPinnedApps()` 改为默认种子，不再作为实时 pinned source。
- `Dock.qml` pinned 区域改为消费 `dockState.pinnedItems`。

验收：

- 修改 pinned 配置后重启 Quickshell 仍保留。
- 执行部署脚本后 pinned 配置不丢失。
- desktop entry 缺失时显示 fallback，不崩溃。

#### D1：固定 / 取消固定 / 排序

目标：达到日用 Dock 的最低要求。

任务：

- pinned item 支持右键菜单：
  - Keep in Dock
  - Remove from Dock
  - Open at Login 后置
  - Show in Files 后置
- 运行窗口可固定到 Dock。
- pinned app 可取消固定。
- 支持拖拽排序。
- Launchpad、Downloads、Trash 这类特殊项不可拖到普通 app 区之外。

验收：

- 拖拽排序后重启仍保留。
- 运行 app 固定后不重复显示两个图标。
- unpin 后如果 app 仍在运行，保留在运行区；关闭后消失。

#### D2：窗口组与点击策略

目标：让 Dock 从“图标栏”变成窗口控制入口。

任务：

- 按 `appKey` 把运行窗口归入 pinned app。
- 一个 app 一个窗口：
  - 未运行：launch
  - 运行未聚焦：focus/restore
  - 运行已聚焦：按偏好 minimize 或打开窗口菜单
- 一个 app 多窗口：
  - 点击显示窗口菜单
  - Alt/Meta 点击可轮转窗口
  - minimized window 单独标记
- 给每个 Dock app 提供窗口计数和 urgent 状态。

验收：

- 同 app 多窗口不重复污染 Dock。
- minimized 多窗口可准确恢复指定窗口。
- urgent window 能在 Dock 体现。

#### D3：右侧特殊区

目标：补齐 macOS Dock 右段核心体验。

任务：

- 增加 separator。
- 增加 Downloads stack：
  - 点击打开弹层或文件管理器
  - 右键菜单：Open in Files、Sort By、View As
- 增加 Trash：
  - 检查 `~/.local/share/Trash/files`
  - 空/满图标切换
  - 右键：Open Trash、Empty Trash
- 支持文件拖到 app 图标：
  - 能解析 desktop file Exec 参数时启动
  - 否则调用 `xdg-open`

验收：

- Downloads 和 Trash 不参与 app 排序。
- Trash 空/满状态准确。
- 文件拖到支持的 app 能打开。

#### D4：偏好与外观

目标：把 Dock 行为纳入设置。

任务：

- 设置项：
  - size
  - magnification
  - auto hide
  - position
  - show recent apps
  - minimize effect
  - click active to minimize
- 与 `shell.qml useSpring` 合并成用户可配置项。

验收：

- 设置改动实时生效。
- VM 默认关闭 spring，真机可打开。
- 配置损坏不会导致 shell 无法启动。

## 4. 系统服务整合研究

### 4.1 当前已完成的真实服务

已有服务不是假的：

| 服务 | 当前后端 | 文件 |
| --- | --- | --- |
| 音量 | Quickshell PipeWire | `services/Controls.qml` |
| 亮度 | `brightnessctl` process | `services/Controls.qml` |
| Wi-Fi | Quickshell Networking | `services/Controls.qml` |
| 蓝牙 | Quickshell Bluetooth | `services/Controls.qml` |
| 正在播放 | MPRIS | `services/Controls.qml` |
| 通知 | Quickshell NotificationServer | `services/Notifications.qml` |
| 电池 | UPower | `services/Battery.qml` |
| 电源动作 | systemd/logind/swaylock/gtklock | `services/Power.qml` |
| SNI 托盘 | Quickshell StatusNotifier | `components/Tray.qml` / `TrayMenu.qml` |

这部分已经可以支撑“能用的 shell”。下一步不是重写，而是补齐系统面。

### 4.2 系统服务缺口

按日用优先级排序：

| 优先级 | 服务 | 当前状态 | 推荐后端 |
| --- | --- | --- | --- |
| S | 输入法状态/切换 | 未做 | fcitx5 DBus / ibus DBus / xkb event fallback |
| S | 截图 UI | niri 有 action，Shell 无 UI | niri screenshot actions + ScreenshotCaptured event |
| S | 锁屏体验 | 调 swaylock/gtklock | 外部安全 locker + Tahoe 主题，不做假锁屏 |
| S | 设置入口 | About/Settings 是占位 | Tahoe Settings QML |
| A | 显示器/缩放 | 未做 UI | niri output IPC / kanshi 可选 |
| A | 电源策略 | 只有动作，没有策略 | logind / UPower / systemd |
| A | 深色/夜间模式 | 控制中心按钮 disabled | gsettings / xdg portal / wlsunset |
| A | 网络详情 | 只有开关和名称 | NetworkManager DBus 或 Quickshell 能力扩展 |
| B | 录屏 UI | 未做 | xdg-desktop-portal / wf-recorder / gpu-screen-recorder |
| B | Quick Look | 未做 | xdg-open + thumbnailer + preview service |
| B | 文件/Trash 深度集成 | Dock 右段未做 | XDG Trash spec |
| C | app menu / dbus-menu | 未做 | dbusmenu / appmenu-gtk-module |
| C | AirDrop / Continuity | 无 Linux 等价 | 暂不做或用 KDE Connect 替代 |

### 4.3 输入法专项

输入法是中文日用的硬门槛，优先级应高于 Stage Manager、AirDrop、视觉微调。

需要区分三层：

1. xkb keyboard layout：niri 已有 `KeyboardLayoutsChanged` / `KeyboardLayoutSwitched`。
2. IME framework：fcitx5 或 ibus。
3. UI indicator：顶栏显示当前输入法/中英状态，支持切换。

执行路径：

#### I0：环境探测

任务：

- 探测进程和 DBus：
  - `fcitx5-remote`
  - `busctl --user list | find fcitx`
  - `ibus engine`
- 判断当前 session 使用 fcitx5、ibus 还是仅 xkb。

验收：

- 顶栏能显示 `ABC` / `中` / engine name 中至少一种。
- 未安装 IME 时显示 xkb layout 或隐藏，不崩溃。

#### I1：fcitx5 优先适配

任务：

- 新增 `services/InputMethod.qml`。
- 先用 `fcitx5-remote` 实现：
  - 查询状态
  - 切换 active/inactive
  - 切换 engine 可后置
- 后续再替换为 DBus 长连接。

验收：

- Ctrl/Meta 空格或点击顶栏能切换输入状态。
- 状态变化 500ms 内反映到顶栏。

#### I2：ibus fallback

任务：

- 检测 ibus。
- `ibus engine` 查询当前 engine。
- 支持切换下一个 engine。

验收：

- GNOME/ibus 环境不显示错误状态。

### 4.4 锁屏专项

不要在 Quickshell 里做“看起来像锁屏”的假锁屏。安全锁屏必须满足：

- shell 崩溃不能解锁。
- layer-shell 被杀不能露出桌面。
- VT 切换、显示器热插拔、睡眠唤醒后仍安全。

推荐路径：

1. 短期继续使用 swaylock/gtklock。
2. 给 swaylock/gtklock 做 Tahoe 主题。
3. Shell 只负责触发锁屏、显示锁定前动画或菜单状态。
4. 如果未来自研锁屏，必须作为独立安全 locker，不是普通 PanelWindow。

执行：

- `Power.qml` 保持 fallback 链。
- 新增设置项选择 locker。
- 新增锁屏前截图/模糊背景生成可以后置。

验收：

- 睡眠唤醒后一定处于锁屏。
- locker 缺失时提示安装，而不是静默失败。

### 4.5 截图与录屏专项

niri 已有 screenshot actions：

- `screenshot`
- `screenshot-screen`
- `screenshot-window`

配置中已有 Print / Ctrl+Print / Alt+Print 绑定。

Shell 缺的是 macOS 式截图 UI：

任务：

- 新增 `ScreenshotOverlay.qml`。
- 提供模式：
  - 全屏
  - 窗口
  - 区域
  - 录屏后置
- 调用 niri action，并监听 `ScreenshotCaptured { path }` event。
- 捕获完成后发通知，带 Open / Show in Files / Copy Path。

验收：

- Print 打开或执行截图 UI。
- 截图完成有通知和文件路径。
- 多显示器和 fractional scale 下区域坐标正确。

### 4.6 Tahoe Settings

当前 `MenuPopup.qml` 中 About / Settings 只是关闭弹窗。需要一个最小 Settings。

第一版不要试图替代 GNOME Settings / KDE System Settings。先做 Tahoe 自己能控制的设置：

```text
Tahoe Settings
  Appearance
    wallpaper
    glass strength
    dark mode
    animation mode
  Dock
    pinned apps
    magnification
    auto hide
    show recent apps
  Notifications
    DND
    history limit
  Control Center
    visible modules
  Keyboard/Input
    input method indicator
    keyboard layout
  Power
    lock command
    suspend behavior
```

硬件设置如 Wi-Fi 详情、蓝牙配对、显示器布局可以逐步接，不要第一版全做。

验收：

- Tahoe 菜单 Settings 打开真实页面。
- 设置写入 `$XDG_CONFIG_HOME/tahoe-shell/settings.json`。
- 改动能实时影响 shell。

## 5. 分阶段执行总计划

### Phase 0：准备与基线，2-3 天

目标：把当前状态固定下来，避免后续改动没有参照。

任务：

- 写窗口模型字段文档。
- 写 Dock 默认配置 schema。
- 写系统服务矩阵。
- 增加手动验收清单。
- 确认部署目录和用户状态目录分离。

交付：

- `docs/window-dock-services-research-plan.md`
- `docs/manual-validation-checklist.md` 后续可新增

### Phase 1：窗口事件流，3-5 天

目标：Shell 主窗口模型改为事件驱动。

任务：

- `NiriIpc.qml` 支持 event stream。
- 实现 `applyEvent()` 状态机。
- 保留 snapshot fallback。
- 增加断线重连。
- `Niri.qml` 暴露稳定 `WindowRecord`。

风险：

- QML 长期 Process 的重连边界。
- Event stream 初始事件顺序和 snapshot 合并。
- JSON parse error 处理。

验收：

- 无轮询情况下窗口状态实时更新。
- niri 重启或 IPC 断开后自动恢复。

### Phase 2：统一窗口消费路径，3-5 天

目标：Dock、TopBar、WindowButton 全部消费 `WindowRecord`。

任务：

- 改 `Dock.qml` 运行窗口模型。
- 改 `WindowButton.qml` 输入和 action。
- TopBar active app 使用统一 focused window。
- 清理组件内直接操作 toplevel 的逻辑。

验收：

- minimize/restore/focus/close 都走统一 action。
- Dock 和 TopBar 状态无明显不同步。

### Phase 3：DockState，4-7 天

目标：Dock pinned apps 持久化。

任务：

- 新增 `DockState.qml`。
- 建立 `dock.json` schema。
- 首次启动从 `Apps.buildPinnedApps()` 生成。
- 支持 pin/unpin。
- 支持配置损坏恢复。

验收：

- 重启和部署后 pinned 状态不丢。
- 固定/取消固定不造成重复 Dock 项。

### Phase 4：Dock 交互完整化，1-2 周

目标：接近日用 Dock。

任务：

- 拖拽排序。
- app/window grouping。
- 多窗口菜单。
- Downloads / Trash 右段。
- Trash 状态。
- 文件拖放到 app。

验收：

- 单 app 多窗口行为稳定。
- 右段 Downloads/Trash 可用。
- 常见 desktop app 文件打开路径可用。

### Phase 5：系统服务第一批，1-2 周

目标：补齐中文和基础桌面必需服务。

任务：

- `InputMethod.qml`：fcitx5/ibus/xkb indicator。
- `ScreenshotOverlay.qml`：截图 UI。
- 锁屏设置和 locker 检测。
- Tahoe Settings 第一版。

验收：

- 中文输入法状态可见、可切换。
- 截图 UI 可用。
- Settings 不再是占位。
- 锁屏失败可见提示。

### Phase 6：系统服务第二批，2-4 周

目标：接近主力桌面。

任务：

- 显示器/缩放设置。
- 深色/夜间模式。
- 电源策略。
- 通知分组和持久策略。
- Wi-Fi/蓝牙详情页。
- 录屏 UI。

验收：

- 多屏/fractional scale 可配置。
- 睡眠唤醒、低电量、网络断开等状态可见。
- 通知中心可长期使用。

## 6. 风险与决策

### 6.1 最大风险

1. **真机验证不足**  
   VM 能跑不代表真机 GPU、多屏、睡眠、输入设备稳定。

2. **Shell 与 compositor 边界不清**  
   如果 Shell 继续绕过 niri action 直接改 toplevel 状态，窗口行为会越来越难维护。

3. **用户状态被部署覆盖**  
   所有用户配置必须离开 `~/.config/quickshell/tahoe/` 这类部署目录。

4. **锁屏安全**  
   不能用普通 QML panel 冒充安全锁屏。

5. **Linux 服务碎片化**  
   输入法、网络、蓝牙、夜间模式在不同发行版差异明显，必须做探测和 fallback。

### 6.2 明确暂缓

以下内容不应优先：

- AirDrop 复刻。
- Continuity / iPhone Mirroring。
- 完整 app menu / dbus-menu。
- Stage Manager 视觉复刻。
- Quick Look 完整格式支持。
- 自研安全锁屏。

这些不是不重要，而是它们依赖前面的窗口模型、Dock 状态和系统服务基础。

### 6.3 关键技术决策

| 决策 | 建议 |
| --- | --- |
| 窗口状态来源 | niri EventStream 为主，snapshot fallback |
| UI 窗口对象 | 统一 `WindowRecord` |
| Dock pinned 状态 | `$XDG_CONFIG_HOME/tahoe-shell/dock.json` |
| 用户设置 | `$XDG_CONFIG_HOME/tahoe-shell/settings.json` |
| Quickshell 文件读写 | `FileView + JsonAdapter` |
| 输入法 | fcitx5 优先，ibus fallback，xkb fallback |
| 锁屏 | 外部 locker，Shell 不做假锁屏 |
| 截图 | niri action + Shell overlay |

## 7. 日用里程碑

### 7.1 可作为爱好者日用

需要完成：

- W1/W2：事件驱动窗口模型和统一窗口操作。
- D0/D1：Dock pinned 持久化和 pin/unpin。
- I0/I1：输入法状态。
- 截图基础 UI。
- 锁屏失败提示。

预计：2-4 周，取决于真机验证反馈。

### 7.2 可作为主力桌面

需要完成：

- W3：窗口组和多窗口 Dock 策略。
- D2/D3：Dock 右段和窗口组。
- Settings 第一版。
- 显示器/缩放/电源策略。
- 真机多屏、睡眠、长时间运行验证。

预计：6-10 周。

### 7.3 接近 macOS 26 体验

需要完成：

- Mission Control / Spaces 级窗口概览。
- 更完整的 Spotlight providers。
- Quick Look / 文件系统集成。
- 系统设置完整化。
- 通知分组、Focus/DND 策略。
- 视觉和动画真机调参。
- 大量 QA 和故障恢复。

预计：3-6 个月以上，且仍受 Linux 生态差异限制。

## 8. 下一步建议

下一步不要先写新的 UI 面板。建议直接从 W1 开始：

1. 在 `NiriIpc.qml` 中实现 event-stream 子进程和 `SplitParser`。
2. 写 `applyEvent()`，用事件维护 `windowsById`。
3. 保留现有轮询作为 fallback。
4. 把 `Dock.qml` 运行窗口模型从 `toplevels` 迁到 `windowList`。
5. 然后再做 `DockState.qml`。

这是成本最低、返工最少的路线。窗口事件流稳定后，Dock 持久化和系统服务 UI 都会变得更直接。

