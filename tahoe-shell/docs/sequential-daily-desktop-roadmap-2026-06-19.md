# Tahoe 日用桌面串行改进路线图

日期：2026-06-19

状态：研究与计划文档；本文件不代表已实现。后续实现必须按本文顺序推进，完成一个阶段并通过验收后，才能开始下一个阶段。

依据：当前源码优先，其次参考既有文档和 `git log`。本轮读取重点包括 `tahoe-shell/shell.qml`、`tahoe-shell/components/Dock.qml`、`tahoe-shell/components/WindowButton.qml`、`tahoe-shell/components/TopBar.qml`、`tahoe-shell/components/Spotlight.qml`、`tahoe-shell/components/LockScreen.qml`、`tahoe-shell/services/Apps.qml`、`tahoe-shell/services/Windows.qml`、`tahoe-shell/services/AppMenu.qml`、`tahoe-shell/services/InputMethod.qml`、`tahoe-shell/services/Appearance.qml`、`tahoe-shell/services/ClipboardHistory.qml`、`config/niri/tahoe-phase0.kdl`，以及父仓库、`niri/`、`quickshell/` 的近期提交记录。

用户新增问题记录：

- Dock 固定应用无法右键取消固定。当前源码里 `Apps.qml` 已有 `unpinApp()` 和 `togglePinnedApp()`，但 `Dock.qml` 固定图标右键点击分支直接 `return`，没有 UI 入口。
- Dock 在打开窗口/应用过多时会挤出屏幕。用户截图参考：`/home/wwt/Pictures/Screenshots/Screenshot from 2026-06-19 01-04-57.png`。当前源码里 `dockSurface.width` 被限制在屏幕宽度内，但内部 `dockRow` 是居中 `Row`，窗口按钮 `WindowButton.width` 在 `showTitle: true` 时固定 132px，没有压缩、裁剪或滚动策略。

## 当前结论

这个项目已经不是纯壳子：当前源码已有窗口事件流服务、Dock 固定项和运行窗口、Dock 右段 Downloads/Trash、拖拽重排、文件拖到应用打开、拖到废纸篓、顶栏、控制中心、通知历史、锁屏、截图、剪贴板历史、输入法状态、深浅色/夜间模式和若干硬件控制入口。

离完整日用桌面仍差在“可靠闭环”和“复杂场景承载”：Dock 数量过多时缺响应式策略；固定项缺取消固定入口；窗口上下文菜单、窗口总览、搜索 provider、设置/关于、原生 app menu、legacy tray 兼容和系统健康页还不够完整。对标 macOS 26 / Windows 11，优先级应从“看起来像”转成“日常高频操作不会卡住、不会出屏、不会把已修好的持久化和玻璃回归重新打坏”。

旧文档 `desktop-function-gap-plan.md` 和 `gap-analysis.md` 中部分条目已经滞后，例如当前源码已有 `Windows.qml` event-stream、输入法状态、截图、锁屏、剪贴板历史、Dock 右段和 Dock 拖拽重排。后续不得按旧文档重复开工已完成项，必须以源码复核为准。

## 串行执行规则

1. 同一时间只能有一个阶段处于实现中。阶段 N 未验收通过前，禁止开始阶段 N+1。
2. 每个阶段只解决该阶段目标，不夹带无关视觉重做、重命名、格式化或大范围重构。
3. 每个阶段完成后必须跑对应回归检查；失败时只修当前阶段，不继续叠新功能。
4. 已修复的行为优先级高于新功能。若新功能和既有护栏冲突，先调整方案，不硬做。
5. 文档、实现、验收记录必须能对应到源码事实。旧文档只作历史参考。
6. 工作区已经有用户改动时，不回滚、不覆盖；只在当前阶段必要文件内做最小改动。
7. 建议每个阶段独立提交。提交前必须看 `git diff`，确认没有带入其他阶段内容。

## Git Log 回归护栏

以下近期修复不能被后续阶段重新打坏：

- Dock 固定项与状态持久化：`921b9f5 Fix Tahoe dock pin reload`、`64fc080 Harden Tahoe state persistence`、`e814371 Persist Tahoe shell user state`、`4aff384 Fix dock pin persistence and launchpad layout`。任何 pin/unpin/reorder 改动都必须重启 shell 后验证固定列表仍正确。
- Dock 动画与安静状态：`c32411c Revert Tahoe dock wave spacing`、`67f358a Keep dock quiet during drag and click`、`9cbeb90 Keep Tahoe dock glass at rest`、`d77684a perf: reduce Tahoe shell idle churn`。不得让 Dock 宽度依赖 magnification，不得恢复会出问题的 wave spacing，不得把 Dock 静止态改回重玻璃/全宽条。
- Popup 和托盘：`fe74085 Fix Tahoe popup and tray behavior`、`b688ede Tighten Tahoe popup and dock placement`、`9333442 Fix Tahoe popup surface regression`、`27962da Fix Tahoe top bar popup dismissal`。新增菜单必须走现有 popup 关闭模型，不能重新出现原生白菜单或点击外部不关闭。
- TahoeGlass 协议与性能：`6f489e3 Fix TahoeGlass coordinate contract to surface-local logical`、`42d28c9 Commit Tahoe glass updates immediately`、`8b3b864 perf: skip unchanged Tahoe glass commits`、`15911c51 perf: avoid redundant Tahoe glass redraws`。新 popup/region 不得使用错误坐标系，也不能制造持续空提交。
- niri 渲染稳定性：`9dae619f Saturate region rect coordinate additions to avoid i32 overflow`、`110693a Drop overflowing blur rects instead of clamping`、`d41bb91a Make snap assist require output edge`。不得用动画区域或超大 blur rect 重新触发溢出/全屏 blur 类问题。
- VM / 软件渲染兼容：`vmware-icon-vanish-handoff.md` 和源码注释已经说明 Image 几何 spring 可能导致图标纹理消失。Dock 和 WindowButton 的新增交互不能移除 `useSpring` 降级路径。

## 阶段 0：基线与验收框架

阶段 0 验收记录：`phase0-baseline-acceptance-2026-06-19.md`。结果：已完成；本阶段没有功能代码改动，只有记录与计划文档。

目标：在做任何功能实现前，固定当前源码事实、复现用户两个 Dock 问题，并建立本轮最小回归检查。

工作范围：

- 记录当前 `git status --short`，确认哪些文件是用户已有改动。
- 复核 `Dock.qml`、`WindowButton.qml`、`Apps.qml` 中固定项、右键、重排、窗口按钮宽度和 Dock 宽度逻辑。
- 用用户截图场景复现 Dock 溢出：至少覆盖 1366x768、1920x1080、多窗口、固定项较多、Downloads/Trash 可见。
- 跑 `scripts/check-submodules.sh` 和 `scripts/check-tahoe-glass-guardrails.sh`；如果脚本因环境不可用失败，要记录原因，不能静默跳过。
- 手动 smoke：启动 Tahoe session，打开/关闭控制中心、通知中心、Spotlight、Launchpad、托盘菜单、锁屏入口、截图入口。

验收：

- 有明确的“当前能复现/不能复现”记录。
- 确认 Dock 右段、拖拽重排、文件拖放、废纸篓拖放这些源码已有能力没有被误判成未实现。
- 明确当前阶段没有代码改动，只有记录和计划。

退出门槛：阶段 0 通过后，才允许进入阶段 1。

## 阶段 1：Dock 固定应用取消固定

目标：补齐 macOS Dock / Windows taskbar 都有的固定项管理闭环：用户能从 Dock 上移除固定应用。

当前源码事实：

- `Apps.qml` 已有 `unpinApp(app)`、`togglePinnedApp(app)`、`movePinnedApp(fromIndex, toIndex)`。
- `Dock.qml` 固定图标支持左键启动、拖拽重排、文件拖到应用打开。
- `Dock.qml` 固定图标右键当前直接 `return`，因此没有取消固定入口。

建议方案：

- 给固定应用右键增加 Tahoe 风格上下文菜单，第一版只放必要动作：打开、从 Dock 移除。
- Launchpad 是静态入口，不能显示“从 Dock 移除”，也不能被写进用户 pinned 状态。
- 对正在运行但已取消固定的应用，窗口仍应保留在运行窗口区；只移除固定启动图标。
- 右键菜单必须走现有 popup 关闭模型，点击外部关闭，不弹原生白菜单。

验收：

- 固定一个应用，右键能取消固定，取消后 Dock 立即更新。
- 重启 Quickshell/Tahoe session 后取消固定结果仍保留。
- Launchpad 右键不会被移除。
- 固定项拖拽重排仍可用，重启后顺序仍保留。
- 文件拖到固定应用打开仍可用。
- 当前运行状态圆点、窗口区、Downloads/Trash 不受影响。

回归检查：

- 对照 `921b9f5`、`64fc080`、`e814371`、`4aff384`，确认 pin reload 和状态持久化没有回退。
- 对照 `67f358a`、`9cbeb90`，确认右键菜单不会让 Dock 静止态变成重玻璃或全宽 bar。

退出门槛：阶段 1 全部验收通过后，才允许进入阶段 2。

## 阶段 2：Dock 数量过多不出屏

阶段 2 验收记录：`phase2-dock-overflow-acceptance-2026-06-19.md`。结果：已完成；实现 Dock 内部宽度预算、运行窗口 icon-only 降级、 pinned/window 水平受限滚动，并修复验收中发现的滚动容器导致的垂直位置偏移。

目标：无论固定项和窗口数量多少，Dock 内容都不能挤出屏幕，也不能遮挡到不可点击。

当前源码事实：

- `dockSurface.width: Math.min(parent.width - 28, dockRow.implicitWidth + 34)` 只限制外层玻璃宽度。
- `dockRow` 是居中 `Row`，没有 clipping、Flickable 或 overflow menu。
- 运行窗口区 `WindowButton` 当前 `showTitle: true`，宽度固定 132px；窗口多时最容易撑爆。
- 固定图标宽度注释明确警告：宽度不能依赖 magnification，否则会形成 binding loop 并导致 Quickshell 崩溃。

建议方案顺序：

1. 先定义 Dock 内部宽度预算：固定应用区、运行窗口区、右侧工具区、分隔线和 spacing 分别占多少。
2. 当总宽度超过预算时，第一层降级只压缩运行窗口区：窗口按钮从带标题切到 icon-only，不压缩固定图标和 Downloads/Trash。
3. 如果 icon-only 仍超出，再把运行窗口区放进可裁剪的水平 Flickable/滚动区，固定应用区和右段工具继续可见。
4. 必要时增加“更多窗口”入口，但只能作为第三层策略；不能一开始把窗口全部藏进菜单。
5. 不改 Dock magnification 的几何原则：delegate 固定宽度，scale/lift 只影响图标视觉。

验收：

- 在 1366x768、1920x1080、超宽屏三个宽度下，固定项较多和 16 个以上窗口都不出屏。
- Dock 外层宽度不超过屏幕安全边距，内部内容不画出玻璃区域。
- icon-only 降级后窗口仍能识别：hover label 或 tooltip 可见，active/minimized 状态可见。
- 横向滚动/更多入口不会吞掉左键 activate、middle click minimize、right click 后续菜单。
- Dock hover magnification 不触发宽度抖动、binding loop、Quickshell crash。
- Downloads/Trash 一直可见，拖到废纸篓仍可用。

回归检查：

- 不恢复 `c32411c` 已回退的 Dock wave spacing 问题。
- 不破坏 `67f358a` 的拖拽/点击期间安静状态。
- 不改掉 WindowButton/Dock 中关于 magnification 与宽度解耦的注释所保护的行为。
- VM 下 `useSpring=false` 仍能正常显示图标，不出现纹理消失。

退出门槛：阶段 2 全部验收通过后，才允许进入阶段 3。

## 阶段 3：Dock 与窗口上下文菜单

阶段 3 验收记录：`phase3-dock-window-menu-acceptance-2026-06-19.md`。结果：已完成；实现运行窗口右键菜单、目标窗口 by-id 关闭、固定/取消固定、最小化/恢复、工作区移动入口和禁用态，并已部署到当前 Tahoe Quickshell 配置。

目标：把 Dock 从“只能启动/激活/最小化”补到日用窗口管理入口。

当前源码事实：

- `WindowButton.qml` 右键当前直接把窗口对应应用固定到 Dock，没有菜单，也没有取消固定、关闭、移动工作区等动作。
- `Windows.qml` 已有 activate/minimize/restore 和 niri action 入口，但缺少 close/move-to-workspace/move-to-output 等面向 UI 的包装。
- `AppMenuPopup.qml` 目前只提供固定到 Dock、显示窗口、最小化；`AppMenu.qml` 只探测 `com.canonical.AppMenu.Registrar`，还没有真实 dbus-menu。

建议方案：

- 为运行窗口按钮添加上下文菜单：显示/隐藏、最小化、关闭、固定/取消固定、移动到工作区。
- 固定应用菜单和运行窗口菜单共享视觉组件，但动作模型分开，避免固定项阶段的稳定行为被窗口动作污染。
- niri action 包装先覆盖可靠命令；无法稳定映射的动作只显示禁用态，不做假实现。
- 窗口关闭动作必须有可靠目标，不能误关焦点窗口。

验收：

- 右键运行窗口能看到可用动作，禁用动作显示为禁用态。
- 关闭、最小化、恢复只作用于目标窗口。
- 固定/取消固定不会打破阶段 1 的持久化验收。
- 菜单关闭、定位、玻璃区域不回归 popup guardrails。

退出门槛：阶段 3 全部验收通过后，才允许进入阶段 4。

## 阶段 4：窗口总览与任务切换

阶段 4 验收记录：`phase4-window-navigation-acceptance-2026-06-19.md`。结果：已完成；实现基于 `recentWindowList` 的 Tahoe 任务切换器、基于 `windowList`/`workspaceList` 的窗口总览、Quickshell IPC 入口和 Tahoe niri 快捷键，同时保留 niri 原生 overview。

目标：补齐对标 macOS Mission Control / App Expose 和 Windows Task View 的窗口导航能力。

当前源码事实：

- `Windows.qml` 已接 `niri msg --json event-stream`，能拿到窗口 id、appId、title、workspace、output、focused、minimized、layout、focusTimestamp。
- 顶栏已有 workspace 小按钮，Dock 有运行窗口按钮。
- 仍缺 Tahoe 自己的窗口总览、缩略预览、跨 workspace 的可视化导航。

建议方案：

- 先做最小任务切换 UI：基于 `recentWindowList` 的居中 switcher，支持键盘循环、释放确认、鼠标选择。
- 再做窗口总览：按 workspace/output 分组，显示窗口卡片和基础几何位置。
- 最后接缩略图/实时预览；如果需要 screencopy/texture 管线，单独做技术 spike，不和基础 UI 混做。
- 保留 niri 自带 overview/快捷键，不在第一版覆盖 compositor 既有行为。

验收：

- 键盘切换、鼠标选择、最小化窗口恢复、跨 workspace 激活都可预测。
- 窗口列表来自同一 `Windows.qml` 模型，不另起一套状态。
- 多屏、窗口关闭、焦点变化时 UI 不显示陈旧窗口。

退出门槛：阶段 4 全部验收通过后，才允许进入阶段 5。

## 阶段 5：Spotlight/Search Provider 架构

阶段 5 验收记录：`phase5-search-provider-acceptance-2026-06-19.md`。结果：已完成；新增统一 `Search.qml` provider 服务，迁移应用搜索和截图动作，并增加计算器、命令前缀和设置项入口。文件搜索按本阶段建议保留为后续评估项，未在本阶段接入同步文件扫描。

目标：把 Spotlight 从应用启动器扩展成日用搜索入口。

当前源码事实：

- `Spotlight.qml` 当前能搜索应用和截图动作，并有 App Store / Files / Shortcuts / Copy 快捷按钮。
- 还没有独立 `Search.qml` provider 服务，应用、截图、命令、设置、文件等结果没有统一格式。

建议方案：

- 新增统一搜索 provider 模型：`id`、`title`、`subtitle`、`icon`、`kind`、`score`、`activate()`。
- 先迁移应用搜索和截图动作为 provider，不改变用户可见行为。
- 再增加计算器、命令前缀、设置项入口。
- 文件搜索最后做，先评估 `fd`、`locate`、tracker 的性能和隐私边界。

验收：

- 现有应用搜索、Enter 启动第一条、Escape 关闭不回归。
- provider 增加不会阻塞 UI；慢 provider 必须可取消或异步。
- 搜索结果排序稳定，重复结果可去重。

退出门槛：阶段 5 全部验收通过后，才允许进入阶段 6。

## 阶段 6：Settings / About / 系统健康页

阶段 6 验收记录：`phase6-settings-health-about-acceptance-2026-06-19.md`。结果：已完成；新增 Tahoe Settings/About/系统健康 overlay、真实依赖探测服务、持久化桌面偏好，并已部署到当前 Tahoe Quickshell 配置。

目标：把分散的系统能力收束成可检查、可配置、可诊断的桌面设置入口。

当前源码事实：

- 已有 `Appearance.qml`、`InputMethod.qml`、`Controls.qml`、`Battery.qml`、`PowerProfiles.qml`、`FanControl.qml`、`ClipboardHistory.qml`、`Notifications.qml` 等服务。
- Tahoe 菜单仍缺真实 About / Settings 页面。
- 依赖工具状态分散在各服务里，用户不知道缺了 `grim`、`slurp`、`swappy`、`cliphist`、`wl-clipboard`、`fcitx5-remote`、`xembedsniproxy` 等时该如何处理。

建议方案：

- 先做只读健康页：显示 portal、PipeWire、NetworkManager、Bluetooth、UPower、fcitx5、截图工具、剪贴板工具、SNI、legacy tray bridge、xwayland-satellite 状态。
- 再做设置页：外观、夜间模式、通知/DND、输入法、截图保存、Dock 偏好、启动项。
- About 页面显示版本、提交、niri/quickshell 子模块版本、GPU/session/backend 信息。
- 所有状态必须是真检测，不做“看起来在线”的假状态。

验收：

- 缺依赖时页面能明确显示缺什么、影响什么功能。
- 设置项写入 Quickshell state 后重启仍保留。
- Settings/About 可从 Tahoe 菜单和 Spotlight 打开。

退出门槛：阶段 6 全部验收通过后，才允许进入阶段 7。

## 阶段 7：应用兼容性与原生菜单

阶段 7 验收记录：`phase7-app-compat-native-menu-acceptance-2026-06-19.md`。结果：已完成；实现 AppMenu registrar / focused app DBusMenu 探测、真实菜单项渲染与触发、AppMenu/legacy tray 健康诊断，并建立常用应用兼容矩阵。

目标：减少“系统能开但常用应用体验不像桌面”的落差。

当前源码事实：

- SNI 托盘基础可用，`Tray.qml` 使用 `SystemTray.items` 和 `IconImage`，右键走 Tahoe 菜单。
- `AppMenu.qml` 只探测 `com.canonical.AppMenu.Registrar` 是否存在，没有读取并渲染真实 app menu/dbus-menu。
- Steam 等 legacy XEmbed 托盘应用仍可能需要 `xembedsniproxy`。

建议方案：

- 先把 legacy tray bridge 作为健康页/启动检查项，明确 Steam、输入法、同步盘等常见应用的兼容路径。
- 再接真实 app menu/dbus-menu，只做 focused app 的菜单，不在第一版实现复杂全局菜单栏。
- 建立常用应用验收矩阵：浏览器、终端、文件管理器、IDE、聊天、Steam、FClash、输入法、截图/录屏。

验收：

- 常用 SNI 应用图标、attention、菜单可用。
- legacy tray 缺桥接时有明确诊断，不静默消失。
- 原生应用菜单至少能对一个支持 app menu 的应用显示真实菜单项。

退出门槛：阶段 7 全部验收通过后，才允许进入阶段 8。

## 阶段 8：视觉、性能与真机收敛

目标：在核心日用闭环稳定后，再做视觉和性能精修，避免为了观感回退功能。

范围：

- Dock 自动隐藏、窗口预览、角标、Genie minimize、Launchpad 分页/文件夹、Quick Look、录屏、触控板手势。
- 玻璃参数、动画参数、暗色模式细节、多屏缩放、低端 GPU 和 VM fallback。
- 自动化截图基线、真机性能记录、功耗/idle churn 检查。

验收：

- 每项视觉改动都有前后截图和低端/VM fallback 说明。
- `check-tahoe-glass-guardrails.sh` 通过，Quickshell idle 不明显增加。
- 不重新引入 niri blur overflow、TahoeGlass 坐标、Dock glass at rest、VM 图标消失等历史问题。

## 停止条件

- 任一阶段验收失败：停止推进，只修当前阶段。
- 任一阶段触发 Git log 护栏中的历史回归：停止推进，先恢复被破坏的既有行为。
- 发现旧文档与源码冲突：以源码为准，先更新路线图或阶段说明，再决定是否实现。
- 发现用户工作区已有相关改动：先读懂并沿用，不覆盖；无法安全合并时暂停并说明冲突。
