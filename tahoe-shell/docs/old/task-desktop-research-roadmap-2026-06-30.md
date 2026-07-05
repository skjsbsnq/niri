# Tahoe 任务桌面源码研究与反腐化改进路线图

日期：2026-06-30

状态：阶段 0、阶段 1、阶段 2、阶段 3、阶段 4、阶段 5、阶段 6、阶段 7 已完成。

## 范围

本研究以本地源码为准，文档只作为辅助背景。按要求，本轮不把以下内容计入完成度缺口：

- 触控板手势
- 多显示器完整体验
- 实机硬件检测和真机稳定性验收

本文不是提交说明，也不是立即执行清单。它是后续维护和改进的路线图，尤其用于指导“不能破坏、不能移除、不能削弱现有功能”的局部反腐化重构。

## 总结判断

这个项目已经不是演示原型。它由 `niri` compositor fork、`quickshell` fork、`tahoe-shell` QML 桌面壳、niri 配置和部署脚本组成，已经覆盖一个单用户 Wayland 任务桌面的主要日常路径。

按源码判断：

- 任务桌面功能完成度：约 70-80%。
- 工程成熟度和可维护性：约 55-65%。

换句话说，它已经接近日常个人使用，但还没有达到“完整、稳定、低维护成本的桌面产品”状态。主要差距不是少几个可见控件，而是入口统一、后端收敛、错误可见性、配置安全性和长期维护结构。

## 已经完成得比较实的部分

### 1. compositor 侧窗口任务模型是实的

`niri-ipc` 已扩展窗口状态，包含 `is_minimized`、`focus_timestamp` 和窗口缩略图请求。`tahoe-shell/services/Windows.qml` 通过 `niri msg --json event-stream` 消费 compositor 事件流，统一生成窗口列表、最近窗口、最小化窗口、工作区、焦点状态和窗口几何。

这说明任务桌面不是只靠 QML 猜测窗口状态，而是有 compositor 事实来源。

### 2. 最小化/恢复链路比较完整

源码里已经能看到完整链路：

- niri IPC 有 minimize/restore/focus/close 等 action。
- compositor 内部有窗口最小化状态。
- shell 能区分 minimized 和 non-minimized 窗口。
- Dock 有最小化窗口架。
- 最小化窗口能通过 compositor 渲染缩略图。
- 恢复窗口会回到 niri action 路径。

这部分不是纯 UI 假象，而是任务桌面的核心能力。

### 3. 日常桌面表面已经很广

`tahoe-shell` 已经实现：

- Dock
- Launchpad
- Spotlight 类搜索
- 任务切换器
- 窗口总览
- 通知服务和通知中心
- 控制中心
- 电池、Wi-Fi、风扇、剪贴板、托盘弹窗
- 设置面板
- 系统健康检查
- 截图入口
- 剪贴板历史
- AppMenu 探测
- 锁屏 UI

因此下一阶段不应该继续优先堆新面板，而应该优先稳定化和结构收敛。

### 4. 锁屏 UI 已经存在，但入口未统一

`LockScreen.qml` 使用 `WlSessionLock` 和 PAM，是 shell 自己的锁屏 UI。`Power.qml` 也能优先调用 `lockService.lock()`。

阶段 2 前，`config/niri/tahoe-phase0.kdl` 中仍有快捷键直接调用 `swaylock`。这说明项目不是“没有锁屏”，而是锁屏入口曾经分裂；阶段 2 已把该快捷键改到 Tahoe lock path。

### 5. 健康检查有价值

`SystemStatus.qml` 会检查 portal、PipeWire、NetworkManager、Bluetooth、UPower、fcitx5、截图工具、剪贴板工具、SNI、legacy tray bridge、xwayland-satellite、niri IPC 等状态。

这对当前项目很重要，因为 shell 层确实依赖大量外部命令和用户服务。健康页降低了排障成本，但还没有消除依赖分散本身。

## 离完整任务桌面的主要差距

### 1. 锁屏、idle、睡眠、会话生命周期没有收敛

现状是：

- 电源菜单可以走 Tahoe lock screen。
- 阶段 2 前，niri 快捷键仍可能走 `swaylock`。
- 阶段 2 前，idle 自动锁屏路径没有形成统一主路径。

完整任务桌面应该只有一个主锁屏策略：

- 快捷键锁屏
- 电源菜单锁屏
- idle timeout 锁屏
- suspend/resume 相关锁屏
- session lock 请求

保留 fallback 可以，但 fallback 不能继续作为主入口。

### 2. 窗口总览和任务切换器没有复用真实缩略图

compositor 已经提供窗口缩略图能力，Dock 的最小化窗口架已经在用。

但：

- `WindowOverview.qml` 当前主要画窗口几何小地图和图标。
- `TaskSwitcher.qml` 当前主要显示图标卡片。

这会削弱任务桌面的完成感。用户在切换任务时需要识别窗口内容，而不是只识别 app 图标和标题。

### 3. 搜索还不是完整桌面搜索

当前搜索更像 app/settings/命令/计算器/截图入口。作为 Spotlight 雏形可用，但还不是完整任务桌面搜索。

缺口包括：

- 最近文件
- 文档
- 文件夹
- 当前打开窗口
- 剪贴板固定项
- 系统动作
- 更细的设置子页结果

此外，命令执行能力必须保持显式和隔离，不能让普通搜索自然滑向危险 shell 执行。

### 4. QML 中外部命令太分散

多个服务直接在 QML 中调用外部命令：

- 截图：`grim`、`slurp`、`swappy`、`wl-copy`、`notify-send`
- 剪贴板：`cliphist`、`wl-copy`、`wl-paste`
- AppMenu：Python helper 和 `busctl`
- 控制中心：NetworkManager、brightness、Bluetooth、power profile、输入法等

这能快速做出功能，但长期维护成本高。问题包括：

- 每个服务各自探测依赖。
- 错误映射不统一。
- 超时和重试策略不统一。
- UI 很难准确知道失败原因。
- 后续换后端时改动面大。

### 5. 设置写配置的能力有边界风险

`NiriSettings.qml` 和 `niri_settings_tool.py` 有一些好设计：

- 写入前 `niri validate`
- 原子写入
- guardrail
- 写入队列

但弱点是 KDL 编辑依赖 regex 和 brace scanning。这对 Tahoe 受控模板可以接受，但不适合作为通用 niri 配置编辑器。

后续需要二选一：

- 明确只编辑 Tahoe 拥有的配置块。
- 或改成 AST 级 KDL 编辑。

### 6. XWayland 和 legacy 兼容性仍依赖补丁与脚本状态

项目维护 patched `xwayland-satellite` 和 glamor wrapper，这是现实且务实的方案。

但这也意味着桌面可用性依赖：

- 本地补丁是否仍适配上游版本
- wrapper 是否部署
- 环境变量是否正确
- xembedsniproxy 等桥接是否运行

这类路径需要可诊断、可恢复、可回归测试，否则每次更新都可能引入隐性退化。

### 7. 窗口缩略图 IPC 边界偏宽

当前 compositor 侧窗口缩略图请求校验了绝对路径和尺寸，但没有把输出路径限制在专用 runtime 目录。shell 自己使用 `$XDG_RUNTIME_DIR/tahoe/window-thumbnails` 是合理的，但 IPC 边界本身仍然过宽。

后续应收紧为：

- 只允许写入 compositor/shell 管理的 runtime 缩略图目录；或
- compositor 自己管理缓存路径并返回路径；或
- 使用 fd 传递，避免任意路径写入。

## 腐化和维护风险

### 1. `shell.qml` 正在变成 god object

`shell.qml` 同时维护：

- top bar 弹窗
- Dock app menu
- Dock window menu
- process menu
- task switcher
- window overview
- settings panel
- left sidebar
- launchpad
- spotlight
- dynamic island 入口
- IPC handler
- per-screen variants

这不是已经不可救，而是已经进入危险区。继续按现在方式堆功能，会不断新增 bool、screen name、anchor rect、close exception 和重复 toggle 逻辑。

这是第一优先级的反腐化目标。

### 2. 弹层协调逻辑重复

很多事件处理都在重复同一套流程：

1. 判断当前屏幕是否已打开。
2. 保存 anchor rect。
3. 关闭其它 top bar popup。
4. 切换目标 popup。
5. 关闭 Launchpad 和 Spotlight。

这类逻辑应该收敛为 helper 或轻量 popup coordinator。保持现有属性和组件不变，先减少重复流程。

### 3. 大 QML 文件混合 UI、状态和后端调用

风险最高的方向：

- `Apps.qml` 同时处理 app indexing、pin、icon、fallback。
- `Controls.qml` 同时处理控制中心状态和多种系统命令。
- `Dock.qml` 同时处理布局、交互、窗口状态和菜单入口。
- `DynamicIsland.qml` 状态机复杂。
- `NiriSettings.qml` 和 Python helper 混合 UI、队列、配置编辑和验证。

后续拆分必须沿真实所有权拆，不能为了“看起来干净”做大手术。

### 4. 静默失败太多

QML 层存在不少 catch 后吞错、命令失败后只更新很弱状态的情况。健康页能补一部分，但用户触发动作的位置仍应该能看到失败原因。

优先改进：

- 截图失败
- 剪贴板 decode/copy/delete 失败
- AppMenu 探测失败
- 网络和蓝牙命令失败
- 缩略图生成失败

### 5. 脚本承担了太多产品集成职责

`scripts/arch-update.sh` 负责构建 fork、部署 shell、部署 niri 配置、生成 session entry、维护 patched xwayland-satellite、处理本地改动保护等。

这很实用，但也说明产品集成被压在一个大脚本里。后续应拆成更聚焦的脚本或子命令：

- 构建/更新 niri
- 构建/更新 quickshell
- 部署 shell
- 部署 niri config
- 维护 xwayland-satellite patch
- session entry 管理
- diagnostics

## 不可破坏约束

后续所有重构必须遵守：

- 不移除现有功能。
- 不削弱现有入口。
- 不把已可用路径替换成未验收路径。
- 不删除 fallback，除非新路径已有健康检查和验收记录。
- 不改变用户可见行为，除非路线图明确列为产品变更。
- 不把多个独立风险合并到一次大重构里。
- 先抽 helper 和 provider，再迁移调用点。
- 迁移时保留旧 API 或兼容包装。
- 每个阶段都要有可验证的验收清单。

## 反腐化局部重构路线图

### 阶段 0：只做文档和边界确认

目标：先冻结判断，不急着动代码。

阶段 0 验收记录：`task-desktop-phase0-acceptance-2026-06-30.md`。结果：已完成；本阶段没有功能代码改动，只补齐路线图状态、边界确认和后续改动映射规则。

任务：

- 保存本研究文稿。
- 明确哪些属于完整任务桌面的缺口。
- 明确哪些属于维护性和腐化风险。
- 明确不得移除、不得削弱现有功能。
- 确认第一批重构只做低风险结构收敛。

验收：

- 路线图存在于仓库文档中。
- 后续代码改动必须能映射到本文某个阶段。

退出门槛：阶段 0 已通过。后续进入阶段 1 前，代码改动必须在变更说明或验收记录中明确引用本文阶段编号；不能同时夹带其它阶段目标。

### 阶段 0 完成确认（2026-06-30）

- 研究文稿已保存为 `tahoe-shell/docs/task-desktop-research-roadmap-2026-06-30.md`。
- 完整任务桌面缺口已冻结在“离完整任务桌面的主要差距”章节：会话生命周期、缩略图复用、搜索范围、外部命令收敛、设置写入边界、XWayland/legacy 兼容性、缩略图 IPC 边界。
- 维护性和腐化风险已冻结在“腐化和维护风险”章节：`shell.qml` god object、弹层协调重复、大 QML 混合职责、静默失败、集成脚本过载。
- 不可破坏约束已冻结在“不可破坏约束”章节：不移除、不削弱、不替换已可用路径、不删除 fallback、不改变用户可见行为、每阶段有验收清单。
- 第一批重构已限定为阶段 1 的低风险结构收敛：只抽 `shell.qml` 弹层 helper 和公共关闭逻辑，保留现有 property、signal、component binding、IPC 方法和多屏语义。
- 后续代码改动映射规则已确认：每个实现或验收记录必须引用本文阶段编号；不属于阶段 1-7 的改动先更新路线图或新增阶段，不直接夹带实现。

### 阶段 1：`shell.qml` 弹层状态反腐化

目标：阻止 `shell.qml` 继续靠复制 bool/toggle/close 逻辑膨胀。

阶段 1 验收记录：`task-desktop-phase1-acceptance-2026-06-30.md`。结果：已完成；本阶段只重构 `shell.qml` 的弹层协调 helper 和调用点，不拆 popup 组件、不改现有 signal/property/IPC 方法、不改变多屏语义。

允许做的改动：

- 抽出 `closeLaunchpadAndSpotlight()` 之类的公共收敛函数。
- 抽出 top bar popup 的 toggle/open helper。
- 把重复的 app menu、application menu、control center、notification、battery、Wi-Fi、fan、clipboard toggle 逻辑迁移到 helper。
- 保留现有所有 property 名称、signal、component binding 和 IPC 方法。

禁止做的改动：

- 不拆掉现有 popup 组件。
- 不移除任何 popup。
- 不改变现有信号名。
- 不改变 Dock、LeftSidebar、ProcessMenu 的功能入口。
- 不把多屏逻辑重新设计，本轮只保持原语义。

验收：

- TopBar 所有弹窗仍能打开、关闭、再次点击关闭。
- 打开任一 top bar popup 时，Launchpad 和 Spotlight 仍会关闭。
- Tray menu 仍保留当前 item 并能正常关闭。
- Dock app menu、Dock window menu、ProcessMenu 的 dismiss 行为不变。
- IPC 打开 settings、health、about、weather、dynamic-island 的路径不变。

退出门槛：阶段 1 已通过。阶段 2 只能处理锁屏入口统一；不得夹带缩略图 provider、命令 provider、搜索扩展或设置写入边界改造。

### 阶段 1 完成确认（2026-06-30）

- `shell.qml` 新增 `closeLaunchpadAndSpotlight()`，统一需要同时收起 Launchpad 和 Spotlight 的路径。
- `shell.qml` 新增 top bar popup helper：`topBarPopupOpenValue()`、`setTopBarPopupOpen()`、`topBarPopupOpenForName()`、`toggleTopBarPopup()`。
- TopBar 的 app menu、application menu、control center、notification center、battery、Wi-Fi、fan、clipboard toggle 已迁移到 `toggleTopBarPopup()`。
- Tray menu 打开路径已迁移到 `openTopBarTrayMenu()`，仍在打开前保存 item 和 anchor，并保留关闭时清空 item 的现有行为。
- Dynamic Island 打开 control center / notification center 的路径复用同一 top bar popup toggle helper。
- Dock app menu、Dock window menu、ProcessMenu 的组件、入口、dismiss layer 和 by-screen 判断未改。
- IPC 中 settings、health、about、weather、dynamic-island 入口未改，仍调用既有 `openSettingsPanel(page)`。

### 阶段 2：锁屏入口统一

目标：让快捷键、电源菜单和 idle 锁屏进入同一 Tahoe lock path。

阶段 2 验收记录：`task-desktop-phase2-acceptance-2026-06-30.md`。结果：已完成；本阶段只统一 Tahoe 锁屏入口、idle 锁屏和健康页可见性，不做缩略图 provider、命令 provider、搜索扩展或设置写入边界改造。

任务：

- 把 `Super+Alt+L` 从直接调用 `swaylock` 改成 Tahoe lock 入口。
- 明确 `swaylock` 是否只作为 emergency fallback。
- 增加 idle helper 或接入现有 session lifecycle。
- 健康页显示 Tahoe lock path 是否可用。
- 写一份锁屏验收记录。

禁止：

- 不删除 Tahoe `LockScreen.qml`。
- 不把 PAM 认证替换成未经验证的新路径。
- 不让电源菜单和快捷键继续分裂。

验收：

- 快捷键锁屏显示 Tahoe UI。
- 电源菜单锁屏显示 Tahoe UI。
- idle 锁屏显示 Tahoe UI。
- 解锁失败和成功都有正确状态。
- fallback 只在 Tahoe lock path 不可用时使用。

### 阶段 2 完成确认（2026-06-30）

- `shell.qml` 新增 Tahoe lock IPC：`lock()`、`lockFrom(source)`、`lockStatus()`。
- `shell.qml` 新增 `requestLock(source)`，快捷键/IPC 和 idle 锁屏都通过 `Power.requestAction("lock")` 进入既有 `LockScreen.qml`。
- `shell.qml` 接入 Quickshell Wayland `IdleMonitor`，默认 `TAHOE_IDLE_LOCK_SECONDS=600`，设置为 `0` 可关闭 idle 锁屏。
- `config/niri/tahoe-phase0.kdl` 中 `Super+Alt+L` 已从直接 `swaylock` 改为 Tahoe lock helper/IPC。
- 新增 `tahoe-shell/scripts/tahoe-lock.sh`，fallback 顺序为 Tahoe IPC → `loginctl lock-session` → `swaylock` emergency fallback。
- `SystemStatus.qml` 健康页新增 `Tahoe 锁屏路径` 状态，显示 LockScreen、IPC、idle monitor、快捷键 helper 和 emergency fallback 状态。
- `swaylock` 已明确只作为 Tahoe lock path 不可用时的 emergency fallback；不再是主锁屏入口。
- `LockScreen.qml` 未删除，PAM 认证路径未替换。

### 阶段 3：缩略图 provider

目标：把窗口缩略图从各组件直接拉取，收敛成可复用、可限速、可缓存的服务。

阶段 3 验收记录：`task-desktop-phase3-acceptance-2026-06-30.md`。结果：已完成；本阶段新增统一 ThumbnailProvider，迁移 Dock minimized shelf、TaskSwitcher 和 WindowOverview，并收紧 niri IPC 缩略图写入路径边界。

任务：

- 新增 `ThumbnailProvider` 服务。
- 统一缩略图路径、生成、缓存、失效、清理。
- 限制并发，避免每个 item 各自起 `niri msg window-thumbnail`。
- Dock minimized shelf 先迁移到 provider，但视觉行为保持不变。
- TaskSwitcher 和 WindowOverview 后续复用真实缩略图。
- niri IPC 收紧路径边界。

禁止：

- 不削弱 Dock minimized shelf 现有缩略图。
- 不让缩略图失败导致窗口项不可用。
- 不用无界进程队列。

验收：

- Dock minimized shelf 视觉不退化。
- 缩略图失败时仍显示 app icon fallback。
- TaskSwitcher 可显示真实窗口缩略图。
- WindowOverview 可显示真实窗口缩略图。
- 连续打开 overview/task switcher 不产生无界进程。
- IPC 不能写到允许目录之外。

### 阶段 3 完成确认（2026-06-30）

- 新增 `tahoe-shell/services/ThumbnailProvider.qml`，统一 `$XDG_RUNTIME_DIR/tahoe/window-thumbnails/window-<id>.png` 路径、生成队列、30 秒缓存、状态缓存、失效和关闭窗口清理。
- `ThumbnailProvider` 使用单一 `Process` 串行执行 `niri msg --json window-thumbnail`，队列按窗口 id 去重并限制为 64 个唯一窗口，避免每个 item 各自启动无界进程。
- `DockMinimizedWindow.qml` 不再直接构造 `niri msg window-thumbnail` 命令；Dock minimized shelf 通过 provider 获取缩略图，失败时仍显示原 app icon/title fallback。
- `TaskSwitcher.qml` 已接入 provider，窗口卡片优先显示真实缩略图，失败或未就绪时保留 app icon fallback，窗口激活/恢复逻辑未改。
- `WindowOverview.qml` 已接入 provider，窗口卡片优先显示真实缩略图，失败或未就绪时保留原几何小地图 fallback，窗口激活/恢复逻辑未改。
- `Windows.qml` 不再拥有缩略图路径和文件清理职责，窗口事实来源和窗口动作 API 保持不变。
- niri IPC 的 `WindowThumbnail` 请求新增 `$XDG_RUNTIME_DIR/tahoe/window-thumbnails` 路径边界校验，并在最终 PNG 写入函数中重复保护；包含单元测试覆盖允许路径、父目录逃逸、其它绝对目录和嵌套目录。
- `SystemStatus.qml` 健康页新增 `窗口缩略图 provider` 状态，显示 provider、CLI 和 IPC 路径边界是否可用。

### 阶段 4：命令和依赖 provider

目标：把 QML 中分散的外部命令调用收敛到一层可诊断 provider。

阶段 4 验收记录：`task-desktop-phase4-acceptance-2026-06-30.md`。结果：已完成；本阶段新增统一 CommandRunner，迁移截图、剪贴板、AppMenu、网络 fallback、电源、输入法、电源模式和亮度相关命令/依赖状态，健康页改为读取同一套依赖状态。

任务：

- 新增轻量 `CommandRunner` 或 `SystemActions` 服务。
- 统一依赖探测结果。
- 截图、剪贴板、AppMenu、网络、蓝牙、电源、输入法逐步迁移到 provider。
- 健康页读取同一套依赖状态。
- action 返回结构化结果：成功、失败、缺依赖、超时、用户取消。

禁止：

- 不改变现有工具选择。
- 不取消现有 fallback。
- 不把失败继续静默吞掉。

验收：

- 截图仍使用当前设置和工具。
- 剪贴板历史仍使用 `cliphist` 和 `wl-clipboard`。
- 健康页信息不减少。
- 缺依赖时 UI 能显示明确原因。

### 阶段 4 完成确认（2026-06-30）

- 新增 `tahoe-shell/services/CommandRunner.qml`，统一命令存在性探测、依赖 status items、常用命令构造和 detached action 结果包装。
- `CommandRunner` 输出结构化 action result，状态包含 `success`、`failure`、`missing`、`timeout`、`cancelled`。
- `shell.qml` 已实例化 `CommandRunner` 并注入 Screenshot、ClipboardHistory、AppMenu、Controls、Power、PowerProfiles、InputMethod 和 SystemStatus。
- 截图入口仍使用原 `grim`、`slurp`、`swappy`、`wl-copy`、`notify-send` 脚本和当前截图设置；缺 `grim`/`slurp` 时返回 missing result，并记录明确原因。
- 剪贴板历史仍使用 `cliphist`、`wl-copy`、`wl-paste`；复制、删除、清空动作通过 provider 返回结构化结果，弹窗继续显示缺依赖原因。
- AppMenu 仍使用 `services/appmenu_probe.py` 和 `busctl`，缺 `python3` 或 `busctl` 时应用菜单状态显示明确原因。
- Controls 中 Wi-Fi `nmcli` fallback、preferred Wi-Fi autoconnect 和亮度写入接入 provider；Quickshell 网络和蓝牙状态源未替换。
- Power 中 Tahoe lock screen 主路径未改；睡眠、退出、重启、关机等外部命令通过 provider 包装并保留原 fallback。
- PowerProfiles 仍保持 `busctl` 优先、`powerprofilesctl` fallback。
- InputMethod 仍使用 `fcitx5-remote` 探测和切换，并通过 provider 暴露缺依赖/daemon 未响应状态。
- `SystemStatus.qml` 不再重复维护网络、蓝牙、截图、剪贴板、AppMenu、输入法等依赖探测，健康页合并显示 `CommandRunner` status items 与本地系统状态。

### 阶段 5：设置和 niri config 写入边界收敛

目标：降低 regex/brace scanning 编辑 KDL 的长期风险。

阶段 5 验收记录：`task-desktop-phase5-acceptance-2026-06-30.md`。结果：已完成；本阶段不把设置 UI 扩张为全量 KDL 编辑器，而是标注 Tahoe 拥有的可写顶层块，并让写路径只修改这些标注范围。

任务：

- 标注 Tahoe 拥有的 config block。
- 只允许 UI 写 Tahoe 拥有范围，或改用 KDL AST。
- 保留 `niri validate`。
- 保留原子写入。
- 增加配置 fixture。
- 对未知结构给出拒绝写入和恢复建议。

禁止：

- 不破坏用户手写的其它 niri config。
- 不在 validate 失败时覆盖 live config。
- 不把设置 UI 扩张成不可靠的全量 KDL 编辑器。

验收：

- 现有设置项仍可写入。
- 非 Tahoe 管理段落保持不变。
- 生成非法配置时拒绝替换。
- 错误信息能指出失败区域。

### 阶段 5 完成确认（2026-06-30）

- `config/niri/tahoe-phase0.kdl` 已用 `// tahoe-managed: begin <block>` / `// tahoe-managed: end <block>` 标注 UI 可写的 `input`、`layout`、`blur`、`tahoe-glass` 和 `animations` 顶层块。
- `niri_settings_tool.py` 写入前会把字段映射到对应 Tahoe 管理块，并拒绝未标记、缺少 begin/end marker 或存在重复同名顶层块的未知结构。
- 读路径继续兼容现有 config；拒绝只发生在写路径，避免设置页因为旧配置直接无法读取。
- `niri validate` 和原子写入路径保持不变；validate 失败时临时文件会清理，live config 不会被替换。
- 新增 `tahoe-shell/tests/fixtures/niri-settings/managed.kdl` 和 golden fixture，覆盖现有设置项写入、非 Tahoe 管理段落保持不变、未标记结构拒绝、重复块拒绝和 validate 失败不覆盖。
- 拒绝写入错误会指出字段、目标块和缺失 marker，并给出重新部署 Tahoe config 或手动添加 marker 的恢复建议。

### 阶段 6：搜索扩展为任务索引

目标：让 Spotlight 从应用启动器扩展为任务搜索入口。

阶段 6 验收记录：`task-desktop-phase6-acceptance-2026-06-30.md`。结果：已完成；本阶段只扩展 Search provider 和 shell 动作路由，不削弱现有 app/settings/screenshot/calculator/command 前缀行为，不进入阶段 7 的 XWayland/legacy 产品化。

任务：

- 增加打开窗口 provider。
- 增加最近文件 provider。
- 增加文件夹 provider。
- 增加剪贴板固定项 provider。
- 增加系统动作 provider。
- 命令执行保持显式前缀和危险提示。
- 慢 provider 必须限时，不能阻塞 app 搜索。

禁止：

- 不削弱当前 app/settings/screenshot/calculator 行为。
- 不让普通查询默认执行 shell command。

验收：

- 应用搜索仍快速。
- 设置搜索仍可打开子页。
- 窗口结果可激活或恢复窗口。
- 最近文件可通过 `xdg-open` 打开。
- 慢 provider 超时不影响主搜索。

### 阶段 6 完成确认（2026-06-30）

- `Search.qml` 新增窗口 provider，读取 `Windows.qml.recentWindowList` / `windowList`，结果激活继续走既有 `activate()` / `restore()` compositor 路径。
- `Search.qml` 新增固定剪贴板 provider，读取 `ClipboardHistory.pinnedEntries`，激活继续走 `copyPinnedEntry()`。
- `Search.qml` 新增系统动作 provider，覆盖锁屏、窗口总览、任务切换器、Launchpad、控制中心、通知中心、剪贴板历史，以及睡眠/退出/重启/关机确认入口。
- `shell.qml` 为 Search 注入窗口、剪贴板和 CommandRunner 服务，并新增 `runSearchSystemAction()` 路由；电源类动作复用 Tahoe 菜单现有确认 UI。
- `Search.qml` 新增异步任务索引慢 provider：90ms debounce，`timeout 1s python3` 子进程，Python 内部 0.82s deadline，读取 `recently-used.xbel` 和 XDG/用户常用目录，按 query 缓存结果。
- 最近文件和文件夹结果激活统一通过 `xdg-open` 打开。
- 命令执行仍只接受 `>` / `!` 显式前缀，普通查询不会生成 shell command 结果；命令结果增加危险执行提示。
- 应用、设置、截图和计算器 provider 保留原结果与激活路径；慢 provider 只通过缓存追加结果，不阻塞主搜索返回。

### 阶段 7：XWayland、托盘、AppMenu 兼容性产品化

目标：让兼容性不再依赖隐含脚本状态。

阶段 7 验收记录：`task-desktop-phase7-acceptance-2026-06-30.md`。结果：已完成；本阶段新增 XWayland 兼容诊断脚本，健康页和 `arch-update.sh` 复用同一检查，并补齐 AppMenu bridge 明确失败原因。

任务：

- 给 patched `xwayland-satellite` 增加明确状态检查。
- 检查 patch hash、上游 ref、wrapper 路径和可执行状态。
- 增加 minimize 和 clipboard bridge 回归检查。
- legacy tray bridge 状态继续在健康页展示。
- AppMenu bridge 不可用时给出明确原因。
- 逐步拆分 `arch-update.sh` 的职责。

禁止：

- 不删除当前 patched satellite 路径。
- 不让 X11 app 兼容性静默退化。

验收：

- 用户能看出 XWayland path 是 ok、missing、stale 还是 broken。
- 更新后如果 patch 失效，会明确失败。
- legacy tray 缺失时能给出修复路径。

### 阶段 7 完成确认（2026-06-30）

- 新增 `scripts/check-xwayland-satellite-compat.sh`，统一检查 patched `xwayland-satellite` binary、glamor wrapper、build stamp、patch hash、上游 ref、niri config 指向和运行中进程。
- XWayland 兼容诊断输出健康页可解析的 `STATUS|...` 行，状态包含 `ok`、`missing`、`stale`、`broken`。
- minimize 回归检查覆盖 `set_minimized`、`WM_CHANGE_STATE`、`wm_action_minimize`、`xdg_toplevel::Request::SetMinimized` 和测试锚点。
- clipboard bridge 回归检查覆盖 `UTF8_STRING`、`text/plain;charset=utf-8`、`selection_cancelled` 和 `ForeignSelection` 锚点。
- `SystemStatus.qml` 的 XWayland 状态改为调用同一诊断脚本；开发态查找 repo 根目录，安装态查找已部署的 `~/.config/quickshell/tahoe/scripts/check-xwayland-satellite-compat.sh`，缺少诊断脚本时仍保留降级状态和修复路径。
- `SettingsTheme.js` 增加 `stale` / `broken` 状态标签和颜色；健康页摘要中 stale 计入注意，broken 计入缺失。
- `arch-update.sh` 新增严格 XWayland 兼容检查，并在部署 Tahoe shell 时安装健康页诊断脚本；静态 missing/stale/broken 会明确失败，当前运行旧 satellite 只提示重启 niri 或重新打开 X11 app。
- legacy tray bridge 健康页状态保留，继续展示 `xembedsniproxy` 安装、运行和自启动状态，以及缺失时的修复路径。
- AppMenu bridge 依赖检查新增 helper 文件可读/可运行原因；`AppMenu.qml` 在 helper 缺失或损坏时直接显示同一明确原因。
- `scripts/README.md` 已记录新的 XWayland 兼容诊断脚本和 `--strict` 语义。

## 推荐执行顺序

1. 文档和边界冻结。
2. `shell.qml` 弹层 helper 局部重构。
3. 锁屏入口统一。
4. 缩略图 provider 和 IPC 边界收紧。
5. 命令/依赖 provider。
6. 设置写配置边界收敛。
7. 搜索扩展。
8. 兼容性和脚本产品化。

这个顺序的核心原则是：先阻止继续腐化，再统一高频入口，再整理后端能力。

## 每次重构的通用验收清单

每次代码改动后至少检查相关子集：

- QML 能启动。
- app menu 弹窗可开关。
- application menu 弹窗可开关。
- control center 可开关。
- notification center 可开关。
- battery/Wi-Fi/fan/clipboard popup 可开关。
- tray menu 可开关且 item 不丢。
- Launchpad 和 Spotlight 互斥关系不变。
- Dock pinned app menu 可开关。
- Dock window menu 可开关。
- minimized shelf 可恢复窗口。
- task switcher 可打开、循环、确认。
- window overview 可打开并激活窗口。
- settings/about/health/weather/dynamic-island 页面可打开。
- left sidebar 和 process menu 可打开关闭。
- screenshot action 仍可执行。
- clipboard copy/delete/pin 仍可执行。
- notification toast 和 notification center 不退化。
- lock/unlock 可用。
- niri config 写入后能通过 `niri validate`。

## 最终判断

Tahoe Niri 应该按“正在成熟的桌面产品”管理，而不是继续按视觉原型管理。

`niri` fork 的任务桌面基础比较扎实，compositor 层改动相对成体系。真正需要警惕的是 `tahoe-shell`：功能已经很丰富，但状态协调、外部命令和大 QML 文件正在推高维护成本。

后续最重要的不是立刻重写，而是有纪律地局部反腐化：保持所有现有功能不变，先抽出重复协调逻辑，再把外部命令和缩略图这类横切能力收敛成服务。这样才能继续补完整任务桌面的缺口，同时不让项目因为功能叠加而变脆。
