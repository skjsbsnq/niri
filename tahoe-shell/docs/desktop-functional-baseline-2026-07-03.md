# Tahoe 桌面功能入口基线

日期：2026-07-03

状态：Phase 0 baseline。本文基于当前源码静态阅读建立，作为后续反腐化重构、功能增强和 PR 审查的不可破坏清单。本文不代表实机验收结果。

## 使用方式

后续任何改动如果影响本文中的入口，提交说明或任务记录应引用对应条目，并明确：

- 是否触碰入口的主要文件。
- 是否改变主路径或降级路径。
- 是否保持用户可见行为不变。
- 是否继续区分 native 能力、外部入口、只读探测和 fallback。

不得为了视觉、重构或后端替换而移除现有入口、隐藏已有能力、把只读状态伪装成可写控制，或让失败路径变成空白 UI。

## 全局 Shell 协调基线

主要文件：

- `tahoe-shell/shell.qml`
- `tahoe-shell/components/TopBar.qml`
- `tahoe-shell/components/PopupDismissLayer.qml`
- `tahoe-shell/components/TahoeGlass.js`
- `tahoe-shell/components/GlassPanel.qml`

依赖服务：

- `Apps`
- `Windows`
- `ThumbnailProvider`
- `CommandRunner`
- `Controls`
- `DesktopSettings`
- `Notifications`
- `Power`
- `SystemStatus`
- `SystemFeatures`
- `NiriSettings`
- `ClipboardHistory`
- `Screenshot`
- `Search`

成功路径：

- `shell.qml` 是全局 coordinator，维护顶栏弹窗、Dock 菜单、任务切换、窗口总览、设置面板、左侧栏、锁屏和 IPC 的 open state。
- 每个屏幕通过 `Variants { model: Quickshell.screens }` 挂载同一套入口组件。
- `IpcHandler { target: "tahoe" }` 暴露任务切换、窗口总览、设置、锁屏、左侧栏和 Dynamic Island 调试入口。
- `TopBar` 发出的 toggle 信号进入 `shell.qml` 的互斥弹窗逻辑。
- `PopupDismissLayer` 为顶栏弹窗、Dock 菜单和进程菜单提供点击外部关闭。

降级路径：

- 如果目标屏幕无法解析，导航入口回退到第一个 Quickshell screen。
- 如果某个服务未注入，组件通常显示空状态、禁用按钮或不执行动作，而不是抛错终止 shell。
- 玻璃材质通过 `GlassPanel` 和 `TahoeGlass.regions` 进入 compositor；QML fill/stroke 是可见 fallback。

不能破坏的用户可见行为：

- 顶栏弹窗、Launchpad、Spotlight、Dock 菜单、任务切换、窗口总览和设置面板之间的互斥关系必须保持。
- 所有现有 IPC 方法必须继续可用，尤其是 `lock`、`lockFrom`、`openTaskSwitcher`、`toggleWindowOverview`、`openSettings`。
- 不得让打开某个入口时遗留不相关 popup 悬空。
- 不得让 glass region 在关闭动画中越界或变成空白。

## 入口总览

| 入口 | 主路径 | 关键 fallback |
| --- | --- | --- |
| Dock | `Apps` + `Windows` + `ThumbnailProvider` | toplevel fallback、图标/标题缩略图 fallback、默认固定应用 |
| Launchpad | `DesktopEntries` 应用网格 | 空列表/无结果状态、图标 fallback |
| Spotlight | `Search` 多 provider 聚合 | 缺 provider 时跳过、任务索引超时/缺 python 时空结果 |
| 通知 | `NotificationServer` + toast/center | 勿扰只存历史、Dynamic Island 抑制 toast、图标 fallback |
| 控制中心 | `Controls` 聚合硬件和媒体 | 控件禁用、状态文本、外部 app fallback |
| 设置 | `SettingsModel` + page stack | alias/default page、FeaturePage 外部设置/探测 |
| 锁屏 | `WlSessionLock` + PAM | `tahoe-lock.sh` 回退到 `loginctl`/`swaylock` |
| 任务切换 | `Windows.recentWindowList` | 无窗口自动关闭、缩略图图标 fallback |
| 窗口总览 | workspace groups + thumbnails | 未分配窗口组、几何 mini-map fallback |
| 托盘 | Quickshell `SystemTray` | 无 item 隐藏、菜单空状态、文字 fallback |
| 剪贴板 | `cliphist` + `wl-clipboard` | 固定项持久化、缺工具错误文本 |
| 截图 | `grim` + `slurp` via `CommandRunner` | optional copy/notify/swappy 降级、缺主依赖报错 |

## Dock

主要文件：

- `tahoe-shell/components/Dock.qml`
- `tahoe-shell/components/WindowButton.qml`
- `tahoe-shell/components/DockMinimizedShelf.qml`
- `tahoe-shell/components/DockMinimizedWindow.qml`
- `tahoe-shell/components/DockAppMenu.qml`
- `tahoe-shell/components/DockWindowMenu.qml`
- `tahoe-shell/services/Apps.qml`
- `tahoe-shell/services/Windows.qml`
- `tahoe-shell/services/ThumbnailProvider.qml`
- `tahoe-shell/services/DesktopSettings.qml`

依赖服务：

- `Apps`：固定应用、应用解析、图标、启动、pin/unpin、拖放打开文件。
- `Windows`：窗口列表、激活、最小化、恢复、关闭、移动到工作区、Dock rectangle 回灌。
- `ThumbnailProvider`：最小化窗口缩略图。
- `DesktopSettings`：自动隐藏、触发热区、窗口标题模式、最小化窗口架。

成功路径：

- Dock 始终显示 Launchpad 入口、固定应用、运行窗口、下载、废纸篓。
- 固定应用左键启动，右键打开 `DockAppMenu`，支持打开和从 Dock 移除。
- 固定应用可拖动重排，持久化到 `Quickshell.stateDir + "/pinned-apps.json"`。
- 运行窗口左键激活或恢复，已聚焦窗口再次点击可最小化；中键最小化；右键打开 `DockWindowMenu`。
- `DockWindowMenu` 支持显示窗口、最小化、固定/取消固定、关闭、移动到工作区。
- 最小化窗口架通过 `ThumbnailProvider.requestThumbnail(..., "dock-minimized")` 请求预览，点击恢复。
- 下载入口用 `xdg-user-dir DOWNLOAD` + `xdg-open`，废纸篓入口用 `gio open trash:///`，文件可拖到废纸篓执行 `gio trash`。

降级路径：

- niri IPC 窗口和 Quickshell toplevel 会在 `Windows.mergeWindowModels()` 合并；缺 IPC id 时保留 toplevel 能力。
- `Apps.resolveApplication()` 找不到桌面项时构造 fallback application，尽量仍能启动命令。
- 图标解析失败时使用 `defaultWindowIcon` 或内置图标匹配。
- 缩略图失败、队列满或图片加载失败时，`DockMinimizedWindow` 显示图标和标题 fallback。
- 没有运行窗口时隐藏窗口区；没有最小化窗口时隐藏最小化窗口架。

不能破坏的用户可见行为：

- Launchpad 入口必须始终保留。
- 固定应用默认集、用户 pin 状态和旧配置迁移不能丢失。
- Dock 自动隐藏时必须保留底部 reveal zone。
- 窗口按钮必须继续回灌 rectangle，避免最小化/恢复动画丢失来源几何。
- 缩略图失败不能显示空白卡片。
- Dock 菜单打开时必须能点外部关闭。

## Launchpad

主要文件：

- `tahoe-shell/components/Launchpad.qml`
- `tahoe-shell/services/Apps.qml`
- `tahoe-shell/services/DesktopSettings.qml`

依赖服务：

- `Apps.launchpadApps`
- Quickshell `DesktopEntries`
- `DesktopSettings` 的图标主题偏好

成功路径：

- 打开时清空查询、重置分类为 `all`，并聚焦搜索输入。
- 应用来源为 Quickshell `DesktopEntries.applications`，过滤掉 `noDisplay` 或不可启动项。
- 支持分类过滤：all、development、internet、media、office、games、system。
- 输入搜索按名称、id、genericName、startupClass、execString、categories、keywords 匹配。
- 回车启动第一个结果；点击应用启动并关闭 Launchpad。

降级路径：

- 没有应用或搜索无匹配时显示“无结果”。
- 应用图标优先主题图标；失败时回退内置 Dock 图标或默认窗口图标。
- DesktopEntries 数量变化通过定时刷新触发应用列表重建。

不能破坏的用户可见行为：

- Dock 和顶栏都必须能打开 Launchpad。
- 打开 Launchpad 时 Spotlight 和顶栏 popup 必须关闭。
- 搜索框必须在打开后自动获得焦点。
- 不得用整体 compositor scale 让大面积应用图标变软；当前 QML 外层动画路径应保持。

## Spotlight

主要文件：

- `tahoe-shell/components/Spotlight.qml`
- `tahoe-shell/services/Search.qml`
- `tahoe-shell/services/Apps.qml`
- `tahoe-shell/services/Windows.qml`
- `tahoe-shell/services/ClipboardHistory.qml`
- `tahoe-shell/components/Screenshot.qml`
- `tahoe-shell/services/CommandRunner.qml`

依赖服务：

- `Search` provider 聚合。
- `Apps` 应用搜索和启动。
- `Windows` 窗口搜索、激活、恢复。
- `ClipboardHistory` 固定剪贴板搜索。
- `Screenshot` 截图结果。
- `CommandRunner` dependency 状态和任务索引 python 可用性。
- 外部命令：`wl-copy`、`xdg-open`、`python3`、`timeout`。

成功路径：

- 打开时清空查询并聚焦输入。
- provider 顺序保留：command、calculator、screenshot、settings、system actions、windows、pinned clipboard、apps、task index。
- 回车激活第一条结果；点击激活指定结果。
- 系统动作可打开锁屏、窗口总览、任务切换器、Launchpad、控制中心、通知中心、剪贴板和电源确认。
- 设置结果可打开 Tahoe 内置页或外部设置候选。
- 最近文件/文件夹通过短超时 python task index 读取 `recently-used.xbel` 和用户目录浅层文件夹。

降级路径：

- 空查询返回空结果。
- command 结果仅在 `>` 或 `!` 前缀下出现；没有前缀时不会暴露 shell 执行。
- `python3` 不可用时 task index 命令直接空退出，不阻塞 UI。
- provider 缺少依赖时只缺该类结果，Spotlight 本体仍可打开。
- 搜索无匹配时显示“无结果”。

不能破坏的用户可见行为：

- Shell 命令执行必须继续受 `>` 或 `!` 前缀隔离。
- `runShellCommand()` 只能由 command result 激活。
- 任务索引必须继续有超时保护，不能阻塞 UI。
- 结果去重和按 score 排序的行为必须保持。
- Spotlight 打开时 Launchpad 和顶栏 popup 必须关闭。

## 通知

主要文件：

- `tahoe-shell/services/Notifications.qml`
- `tahoe-shell/components/NotificationToast.qml`
- `tahoe-shell/components/NotificationCenter.qml`
- `tahoe-shell/services/Sound.qml`
- `tahoe-shell/services/DynamicIsland.qml`

依赖服务：

- Quickshell `NotificationServer`
- Quickshell notification action/image/body 支持
- `Sound` 用于勿扰时静音事件音
- `DesktopSettings` / `DynamicIsland` 用于 toast 抑制判断
- `Quickshell.stateDir + "/notifications.json"` 持久化勿扰状态

成功路径：

- `Notifications` 注册 session bus 的 `org.freedesktop.Notifications`。
- 新通知被设置 `tracked = true` 并进入 FIFO active queue，同时写入 history snapshot。
- toast 显示队首通知，支持 summary、body、appName、图标/图片、urgency、actions。
- 普通通知按客户端 timeout 或默认 5 秒自动过期，Critical 通知保持到用户处理。
- Notification Center 显示历史、勿扰开关、单条移除和清空。
- 勿扰开启时保留历史、抑制 toast，并尝试设置 `suppress-sound` 和事件音静音。

降级路径：

- 没有图标时 toast/center 显示通知 glyph。
- Dynamic Island 启用时 toast 被抑制，但通知服务和历史仍工作。
- 无历史时 Notification Center 显示“暂无通知”。
- 客户端关闭通知后 `closed` 信号会清理队列并推进下一条。

不能破坏的用户可见行为：

- 不得恢复假的“Session ready”硬编码通知。
- 通知服务必须只有一个 root-level server 实例。
- 勿扰不能丢历史。
- action button 必须继续调用原通知 action。
- Critical urgency 必须继续有可见强调并保持到用户处理。

## 控制中心

主要文件：

- `tahoe-shell/components/ControlCenter.qml`
- `tahoe-shell/services/Controls.qml`
- `tahoe-shell/services/Appearance.qml`
- `tahoe-shell/services/CommandRunner.qml`
- `tahoe-shell/services/Sound.qml`

依赖服务：

- Quickshell `Pipewire`
- Quickshell `Networking`
- Quickshell `Bluetooth`
- Quickshell `Mpris`
- 外部命令：`brightnessctl`、`nmcli`、`pactl`、`gsettings`
- `CommandRunner` dependency registry

成功路径：

- 顶栏或 Dynamic Island 可打开控制中心。
- Wi-Fi tile 显示开启、连接 SSID、信号、已知网络和飞行模式相关状态。
- 蓝牙按钮显示适配器可用性和已连接设备数量。
- 亮度 slider 通过 sysfs monitor 和 `brightnessctl` 读写背光。
- 音量 slider 通过 PipeWire default sink 读写音量和静音状态。
- 媒体 tile 通过 MPRIS 显示曲目、封面和上一首/播放暂停/下一首。
- 展开区提供深色、夜览、计算器、计时器、相机入口。

降级路径：

- 无背光或缺 `brightnessctl` 时亮度 slider 禁用。
- PipeWire 未 ready 或无 default sink 时音量 slider 禁用。
- 无蓝牙适配器时蓝牙按钮禁用，并显示不可用状态。
- NetworkManager/nmcli 不可用时网络相关 detail 记录到 `networkErrorText`。
- 计算器、计时器、相机优先 DesktopEntry，失败后尝试 raw command。

不能破坏的用户可见行为：

- 控制中心入口必须保持可打开，即使具体硬件不可用。
- 不可用控件必须禁用或显示状态，不得假装已控制。
- 用户调节亮度/音量时 UI 应立即反映目标值，并在失败后刷新真实状态。
- 外部工具缺失不能导致控制中心加载失败。

## 设置

主要文件：

- `tahoe-shell/components/SettingsPanel.qml`
- `tahoe-shell/components/settings/SettingsModel.js`
- `tahoe-shell/components/settings/SettingsSidebar.qml`
- `tahoe-shell/components/settings/pages/*.qml`
- `tahoe-shell/services/SystemStatus.qml`
- `tahoe-shell/services/SystemFeatures.qml`
- `tahoe-shell/services/NiriSettings.qml`
- `tahoe-shell/services/AppsSettings.qml`

依赖服务：

- `DesktopSettings`
- `SystemStatus`
- `SystemFeatures`
- `Appearance`
- `Notifications`
- `InputMethod`
- `Controls`
- `Sound`
- `Battery`
- `PowerProfiles`
- `Power`
- `NetworkSettings`
- `AppsSettings`
- `NiriSettings`
- `Weather`

成功路径：

- `SettingsModel.js` 是设置页 registry，`SettingsPanel.qml` 根据 page id 进入对应 StackLayout 页面。
- `settings` alias 解析到默认 `wifi` 页；未知页也回退到默认页。
- 设置面板打开时刷新系统健康状态，并聚焦 FocusScope 以支持 Escape 关闭。
- native 页面包括 Wi-Fi、网络、蓝牙、显示器、声音、电源、多任务、外观、应用、通知、鼠标触摸板、键盘、系统、niri、壁纸、灵动岛、截图、Dock、天气、启动项、健康、关于等。
- `FeaturePage` 承载搜索、在线账号、共享、健康使用、色彩、打印机、辅助功能、隐私等 probe/external 类页面。

降级路径：

- `FeaturePage` 在 `SystemFeatures` 缺失时显示未知/尚未检测，并提供刷新。
- 多个 feature 页面提供 `gnome-control-center <panel>` 外部入口。
- 健康使用页没有屏幕时间后端，只提供 Tahoe 可控制的空闲锁定和勿扰信息/开关。
- niri 快捷键页是只读查看，不写 `binds`。
- 应用权限页必须保留 ordinary desktop app 不可完整强制的提示。

不能破坏的用户可见行为：

- 所有 `SettingsModel.panels` 中 `visible: true` 的页面必须仍可打开。
- 不能把 `FeaturePage` 探测页伪装成 native 后端。
- read-only 页面必须继续明确只读边界。
- 设置面板尺寸、scrim、点击外部关闭和 Escape 关闭必须保持。
- 健康页刷新按钮和状态显示必须保留。

## 锁屏

主要文件：

- `tahoe-shell/components/LockScreen.qml`
- `tahoe-shell/services/Power.qml`
- `tahoe-shell/shell.qml`
- `tahoe-shell/scripts/tahoe-lock.sh`

依赖服务：

- Quickshell `WlSessionLock`
- Quickshell `PamContext`
- PAM config `login`
- `IdleMonitor`
- 外部 fallback：`quickshell ipc`、`loginctl`、`swaylock`

成功路径：

- `shell.requestLock(source)` 通过 `Power.requestAction("lock")` 或直接 `lockScreen.lock()` 进入 Tahoe LockScreen。
- `LockScreen` 使用 `WlSessionLock` 锁定会话，使用 PAM `login` 验证密码。
- IPC 提供 `lock`、`lockFrom` 和 `lockStatus`。
- `IdleMonitor` 在 `TAHOE_IDLE_LOCK_SECONDS` 大于 0 时启用，尊重 inhibitors，idle 后调用 `requestLock("idle")`。
- `Power` 的 lock 动作不需要确认，其它 sleep/logout/restart/shutdown 需要 pending confirmation。

降级路径：

- `tahoe-lock.sh` 先调用 Tahoe IPC lock，再尝试 `loginctl lock-session`，最后 emergency fallback 到 `swaylock`。
- PAM 启动失败或认证失败时显示状态文本，不解锁。
- Escape 清空密码输入，不关闭 lock surface。

不能破坏的用户可见行为：

- 锁屏必须是真 session lock，不得变成普通 overlay。
- 锁屏入口必须继续支持 IPC、power menu 和 idle。
- idle lock 必须继续尊重 inhibitors。
- Tahoe IPC 是快捷键脚本的主路径，`loginctl`/`swaylock` 只能是 fallback。

## 任务切换

主要文件：

- `tahoe-shell/components/TaskSwitcher.qml`
- `tahoe-shell/services/Windows.qml`
- `tahoe-shell/services/ThumbnailProvider.qml`
- `tahoe-shell/services/Apps.qml`
- `tahoe-shell/shell.qml`

依赖服务：

- `Windows.recentWindowList`
- `ThumbnailProvider`
- `Apps`
- niri IPC event stream
- Quickshell `ToplevelManager`

成功路径：

- IPC、快捷键或 Spotlight 系统动作可打开任务切换。
- 打开时选中 focused window；键盘循环时可从下一个/上一个窗口开始。
- Tab、方向键循环；Enter/Space 确认；Escape 取消；释放 Alt/Ctrl/Meta 后自动确认。
- 确认时最小化窗口调用 `restore()`，其它窗口调用 `activate()`。
- 打开或窗口列表变化时统一通过 `ThumbnailProvider.requestThumbnails(..., "task-switcher")` 请求缩略图。

降级路径：

- 没有窗口时立即关闭。
- 缩略图不可用或图片加载失败时显示应用图标，再失败显示窗口 glyph。
- `Windows` 可从 niri IPC 合并到 Quickshell toplevel，IPC 不完整时仍保留可用 toplevel 操作。

不能破坏的用户可见行为：

- `windowList`、`recentWindowList` 和 focused ordering 的对外语义必须保持。
- 任务切换不得绕过 `ThumbnailProvider` 自己 spawn 截图命令。
- 缩略图失败不能阻断窗口切换。
- 键盘释放确认行为必须保持。

## 窗口总览

主要文件：

- `tahoe-shell/components/WindowOverview.qml`
- `tahoe-shell/services/Windows.qml`
- `tahoe-shell/services/ThumbnailProvider.qml`
- `tahoe-shell/services/Apps.qml`
- `tahoe-shell/shell.qml`

依赖服务：

- `Windows.windowList`
- `Windows.workspaceList`
- `ThumbnailProvider`
- `Apps`
- niri IPC layout geometry

成功路径：

- IPC、Spotlight 或顶层函数可打开窗口总览。
- 打开时选中 focused window 或第一个窗口。
- 按 workspace 分组显示窗口，带 output subtitle。
- 点击窗口激活或恢复；Enter/Space 激活选中项；方向键/Tab 循环选择；Escape 关闭。
- 有缩略图时显示窗口预览，并叠加 app icon。
- 没有缩略图时用 niri layout geometry 绘制 mini-map。

降级路径：

- 没有 workspace 数据时创建“所有窗口”组。
- 有 workspace 但某些窗口无法匹配时放入“未分配窗口”组。
- 没有 geometry 时使用居中的默认矩形。
- 缩略图失败时保留 mini-map、图标、标题、appId/minimized detail。

不能破坏的用户可见行为：

- 总览必须继续显示所有窗口，不能因 workspace 缺失丢窗口。
- 缩略图路径必须继续唯一依赖 `ThumbnailProvider`。
- geometry fallback 必须保留，避免预览区空白。
- 激活最小化窗口时必须 restore，而不是只 focus。

## 托盘

主要文件：

- `tahoe-shell/components/TopBar.qml`
- `tahoe-shell/components/Tray.qml`
- `tahoe-shell/components/TrayMenu.qml`
- `tahoe-shell/services/SystemStatus.qml`

依赖服务：

- Quickshell `Quickshell.Services.SystemTray`
- Quickshell `QsMenuOpener`
- SNI item 的 `activate()`、`secondaryActivate()`、`menu`
- `SystemStatus` 仅用于健康页探测 SNI watcher 和 `xembedsniproxy`

成功路径：

- 有 `SystemTray.items` 时顶栏显示托盘图标。
- 左键执行 item activate；中键执行 secondaryActivate；右键在有 menu 时打开 `TrayMenu`。
- `onlyMenu` item 左键打开菜单。
- `TrayMenu` 使用 `QsMenuOpener` 渲染菜单项，支持 separator、checked state、disabled state 和触发 action。

降级路径：

- 没有 item 时托盘区域隐藏。
- 图标加载失败时显示 tooltip/title/id 的首字母 fallback。
- 菜单无 children 时显示“无可用操作”。
- legacy tray bridge 只作为健康页状态，不是现代 SNI 主路径。

不能破坏的用户可见行为：

- 现代 SNI 托盘入口不能依赖 legacy bridge 才显示。
- 右键菜单必须锚定顶栏 item，并能点击外部关闭。
- disabled menu item 不得可点击。
- attention 状态必须继续有可见强调。

## 剪贴板

主要文件：

- `tahoe-shell/services/ClipboardHistory.qml`
- `tahoe-shell/components/ClipboardPopup.qml`
- `tahoe-shell/services/CommandRunner.qml`
- `tahoe-shell/services/Search.qml`

依赖服务：

- `cliphist`
- `wl-copy`
- `wl-paste`
- `CommandRunner`
- `Quickshell.stateDir + "/clipboard-pins.json"`

成功路径：

- `ClipboardHistory` 检测 cliphist/wl-clipboard，启动 `wl-paste --watch cliphist store` watcher。
- popup 打开时刷新历史。
- 历史列表最多解析 60 项，显示 preview、文本/二进制 icon、pin/copy/delete。
- 固定项持久化到 Tahoe state，可在 popup 和 Spotlight 中复制。
- 清空历史执行 `cliphist wipe`，固定项保留。
- 文本历史项通过 `cliphist decode | wl-copy` 复制。

降级路径：

- 缺 `cliphist` 或 `wl-copy` 时 popup 显示错误文本和不可用状态。
- 缺 `wl-paste` 时 watcher 不启动，但仍可尝试显示已有历史。
- 二进制项不可固定，避免把不可安全解码内容写入 pins。
- 固定项只依赖 Tahoe state；复制固定项需要 `wl-copy`。
- pin decode 失败时显示“固定失败”并重置 pending 状态。

不能破坏的用户可见行为：

- 清空历史不能删除固定项。
- 固定项上限、文本大小上限和去重必须保留。
- 缺依赖时必须明确显示原因，不能静默空白。
- Spotlight 复制固定项必须复用 `ClipboardHistory.copyPinnedEntry()`。

## 截图

主要文件：

- `tahoe-shell/components/Screenshot.qml`
- `tahoe-shell/services/CommandRunner.qml`
- `tahoe-shell/components/settings/pages/ScreenshotPage.qml`
- `tahoe-shell/services/DesktopSettings.qml`
- `tahoe-shell/components/TopBar.qml`
- `tahoe-shell/services/Search.qml`

依赖服务：

- `grim`
- `slurp`
- optional：`swappy`
- optional：`wl-copy`
- optional：`notify-send`
- optional：`xdg-open`
- optional：`xdg-user-dir`
- `DesktopSettings` 截图目录、复制到剪贴板、通知动作偏好

成功路径：

- 顶栏截图按钮和 Spotlight 截图结果都调用 `Screenshot.captureSelection()`。
- 主路径通过 `CommandRunner.runScreenshotSelection()` 执行脚本。
- 保存目录优先使用用户配置，否则使用 `xdg-user-dir PICTURES` 或 `$HOME/Pictures/Screenshots`。
- `slurp` 选择区域，`grim -g` 保存 PNG。
- 如果启用复制且 `wl-copy` 可用，复制 PNG 到剪贴板。
- 如果 `notify-send` 支持 actions，可提供标注、打开、复制动作；标注使用 `swappy`。

降级路径：

- 缺 `grim` 或 `slurp` 时截图不可用，返回错误并可通知用户。
- 用户取消 `slurp` 时静默退出，不产生失败通知。
- 缺 `wl-copy` 时仍保存文件，但不复制。
- 缺 `swappy` 时标注动作不可用或无效果。
- 缺 `notify-send` 时只保存文件，不显示通知动作。

不能破坏的用户可见行为：

- 截图入口必须同时保留顶栏和 Spotlight。
- 保存目录设置必须继续生效，并允许重置到默认。
- `grim`/`slurp` 是主依赖，optional 工具缺失只能降级 optional 功能。
- 截图命令不得阻塞 shell UI。

## Phase 0 PR 检查清单

后续任务涉及任一入口时，应逐项确认：

- 入口仍可从原位置打开。
- 原有快捷键或 IPC 入口未删除。
- 主路径和 fallback 路径都被保留或明确等价替换。
- 缺依赖时仍有状态文本、禁用态或 fallback UI。
- 缩略图、图标、通知、剪贴板和截图失败时不出现空白卡片。
- read-only/probe/external 页面没有被包装成 native 可写页面。
- 新逻辑复用现有服务，不新增平行的窗口缩略图、截图、权限或配置写入通道。
