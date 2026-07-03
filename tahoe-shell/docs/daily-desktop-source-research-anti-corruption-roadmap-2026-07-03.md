# Tahoe 日用桌面源码研究与反腐化改进路线图

日期：2026-07-03

状态：研究文稿兼改进路线图。本文基于源码静态阅读，不代表已经完成实现或实机验收。

## 范围与约束

本研究以本地源码为第一依据，文档只作为辅助背景。重点回答三个问题：

1. 当前项目离完整日用桌面还有哪些不足。
2. 用户日常使用中，按源码能看到哪些不稳定、不完整或维护成本偏高的点。
3. 视觉质感还能往哪里提升，同时如何通过局部反腐化重构提升可维护性。

本轮明确不研究、不规划以下事项：

- 触摸板手势。
- 多显示器完整体验。
- 实际运行测试、真机验收、性能实测。
- GPU/渲染能力自适应优化。该项不是后续路线图待办，不做自动 GPU 探测、自动降级或按渲染器切换动画策略。

所有后续改动必须遵守：

- 不破坏现有功能。
- 不移除现有用户入口。
- 不削弱已经可用的能力。
- 不把 read-only 状态伪装成可控制能力。
- 不做大重写，只做可回滚的局部反腐化重构。
- 优先加测试、guardrail、状态模型和文档，再移动职责。

## 总体判断

项目已经超过“窗口管理器配置”阶段。它由 `niri` compositor fork、`quickshell` fork、`tahoe-shell` QML 桌面壳、niri 配置和部署脚本组成，已经覆盖个人日用桌面的很多表面能力。

源码显示，`niri` 本身定位仍是 compositor，不是完整桌面环境。`niri/README.md:56` 写明它稳定可日用，但 `niri/README.md:63` 说明 niri by itself is not a complete desktop environment。`niri/docs/wiki/Important-Software.md:1` 也把通知、portal、认证代理、Xwayland 等列为日用补齐项。

Tahoe Shell 已经补了大量桌面壳能力。`tahoe-shell/shell.qml:16` 起可以看到顶栏弹窗、Dock、Launchpad、Spotlight、通知中心、控制中心、任务切换器、窗口总览、设置面板、左侧栏、锁屏等全局状态和入口。

因此当前状态可以概括为：

- compositor 和 shell 的日用表面已经比较完整。
- 任务窗口链路、锁屏、通知、Dock、搜索、设置已有真实实现，不是纯 mock。
- 但完整桌面的薄弱点集中在系统后端闭环：设置、权限、搜索索引、应用管理、启动项、共享、账号、打印、色彩、辅助功能等很多仍依赖外部工具、探测脚本或外部 GNOME 设置入口。
- 工程上最大风险不是“功能少”，而是跨层胶水变多后，状态来源、外部命令、配置写入、视觉材质和 shell 全局协调逐步腐化。

## 已经比较扎实的部分

### 1. 桌面壳表面覆盖很广

`tahoe-shell/shell.qml` 汇聚了日用桌面的主要交互入口：

- 顶栏和各类 popup。
- Dock、Dock AppMenu、Dock window menu。
- Launchpad。
- Spotlight。
- Notification Center。
- Control Center。
- Task Switcher。
- Window Overview。
- Settings Panel。
- Left Sidebar。
- Lock Screen。

这说明项目不是简单主题包，而是完整 shell 方向。

### 2. 通知服务是真实现

`tahoe-shell/services/Notifications.qml:8` 明确是 real desktop notification service。`NotificationServer` 注册 session bus 的 `org.freedesktop.Notifications`，支持 body、actions、image，并维护 live notification objects。

这部分已经接近日用桌面要求，不是 shell 自己伪造 toast。

### 3. 锁屏链路相对完整

`tahoe-shell/components/LockScreen.qml:9` 使用 `WlSessionLock`，`LockScreen.qml:56` 使用 PAM `login`。`tahoe-shell/shell.qml:783` 挂载 `LockScreen`，`shell.qml:787` 的 `IdleMonitor` 支持 idle lock 并尊重 inhibitors。

`tahoe-shell/scripts/tahoe-lock.sh:29` 先走 Tahoe IPC lock，再 fallback 到 `loginctl lock-session`，最后 emergency fallback 到 `swaylock`。这说明锁屏主路径已经向 Tahoe 自身收敛。

### 4. 窗口管理链路不是纯 UI 猜测

`tahoe-shell/services/Windows.qml:9` 定义 unified niri window model，消费 `niri msg --json event-stream`。`Windows.qml:90`、`Windows.qml:109`、`Windows.qml:123` 分别支持 activate、minimize、restore。

`niri/niri-ipc/src/lib.rs:88` 有 `WindowThumbnail` request，`lib.rs:322` 有 `MinimizeWindow`，`lib.rs:331` 有 `RestoreWindow`。`niri/src/layout/mod.rs` 和 `niri/src/layout/minimize_window_animation.rs` 也能看到最小化/恢复动画路径。

这意味着 Dock、任务切换、缩略图等不是只依赖 app 图标，而是和 compositor 状态连起来了。

### 5. 窗口缩略图已进入 compositor 渲染路径

`niri/src/ipc/server.rs:455` 接收 `Request::WindowThumbnail`，校验路径、尺寸并调度渲染。`niri/src/niri.rs:5897` 的 `window_thumbnail()` 会调用 mapped window 的 render 路径并写 PNG。

Shell 侧 `tahoe-shell/services/ThumbnailProvider.qml:7` 是 centralized window thumbnail queue，带缓存、失败状态、队列长度和 timeout。这是任务桌面质感的重要基础。

### 6. 玻璃质感不是单纯 QML 半透明

`tahoe-shell/components/TahoeGlass.js:7` 定义 material vocabulary：`panel`、`pill`、`dock`、`menu`、`toast`、`launcher`、`backdrop`。

`tahoe-shell/components/GlassPanel.qml:33` 通过 `TahoeGlassRegion` 把 material、radius、blur、shadow、clip、interaction、materialAlpha 交给 compositor。

`niri/resources/tahoe-glass-v1.xml:17` 定义私有 Tahoe glass protocol，compositor 拥有 blur、tint、refraction、clipping、shadow rendering。

`niri/src/render_helpers/shaders/postprocess.frag:47` 起实现了 glass surface detail、rim、height、normal、light、refraction、lens、inner shadow 等材质细节；`niri/src/render_helpers/shaders/clipped_surface.frag:43` 支持 chromatic RGB split。

这说明视觉方向已经有工程基础，不是只调 CSS/QML 颜色。

## 离完整日用桌面的主要不足

### 1. 设置中心广度有了，但很多页不是原生后端

`tahoe-shell/components/settings/SettingsModel.js` 中很多系统域已经列出，但以下页仍是 `component: "feature"`：

- `search`：`SettingsModel.js:150`
- `online-accounts`：`SettingsModel.js:163`
- `sharing`：`SettingsModel.js:176`
- `wellbeing`：`SettingsModel.js:189`
- `color`：`SettingsModel.js:235`
- `printers`：`SettingsModel.js:248`
- `accessibility`：`SettingsModel.js:261`
- `privacy`：`SettingsModel.js:275`

`tahoe-shell/components/settings/pages/FeaturePage.qml:27` 根据 panelId 映射 feature IDs，`FeaturePage.qml:118` 提供“外部设置”按钮并打开 `gnome-control-center`。`FeaturePage.qml:159` 还明确写着健康使用没有内置屏幕时间后端。

结论：设置中心看起来已经接近系统设置，但很多页本质是状态探测和外部入口，不是 Tahoe 自己的设置后端。

### 2. 外部依赖多，用户体验随系统安装状态退化

`tahoe-shell/services/CommandRunner.qml:791` 的 dependency probe 覆盖大量外部命令和服务：

`grim`、`slurp`、`swappy`、`wl-copy`、`wl-paste`、`cliphist`、`notify-send`、`xdg-open`、`xdg-user-dir`、`xdg-mime`、`nmcli`、`bluetoothctl`、`busctl`、`python3`、`fcitx5-remote`、`loginctl`、`systemctl`、`niri`、`powerprofilesctl`、`brightnessctl`、`flatpak`、`snap`、`gsettings`、`pactl`、`wpctl`、`tracker3`、`gnome-control-center`、`goa-daemon`、`colormgr`、`lpstat` 等。

健康页能探测这些依赖是好事，但它也暴露了一个事实：很多桌面能力不是 Tahoe 原生闭环，而是命令胶水。缺失时功能会降级、消失或只显示说明。

### 3. 应用权限是可见性，不是完整控制权

`tahoe-shell/services/apps_settings_probe.py:201` 用 `xdg-mime` 查询默认应用，`apps_settings_probe.py:285` 用 `xdg-mime default` 写入默认应用。

权限部分读取 portal permission store、Flatpak static permissions、Snap connections。`apps_settings_probe.py:547` 的 `permissions_for()` 里，`fullyEnforceable` 只对 Flatpak/Snap 为 true；`apps_settings_probe.py:579` 明确说明普通桌面应用的权限不能被 Tahoe 完整强制执行。

UI 也没有隐瞒这一点：`tahoe-shell/components/settings/pages/AppPermissionsPage.qml:69` 写普通桌面应用“权限不能被 Tahoe 完整强制执行”，`AppPermissionsPage.qml:169` 也显示权限控制范围限制。

结论：这是正确诚实的 UI，但它离完整桌面的“统一权限控制中心”还有距离。

### 4. 搜索像优秀启动器，不是完整文件/内容索引

`tahoe-shell/services/Search.qml:917` 把 command、calculator、screenshot、settings、system actions、windows、pinned clipboard、apps、task index 合并。

但 task index 是 `Search.qml:744` 里的 `timeout 1s python3`。Python 代码在 `Search.qml:764` 起，有 0.82 秒 deadline，主要读 `recently-used.xbel`、用户目录和浅层文件夹。`SystemFeatures.qml:89` 探测 `tracker3`，但搜索实现没有真正接入 Tracker 全文/元数据索引。

结论：当前搜索日用能启动应用、找窗口、找设置、算表达式，但不应被视作完整桌面搜索。

### 5. 启动项管理很薄

`tahoe-shell/components/settings/pages/StartupPage.qml:25` 只是“XDG autostart 管理入口”，`StartupPage.qml:30` 打开 `~/.config/autostart`，`StartupPage.qml:46` 保存启动项备注。

这不是完整 autostart manager。缺少：

- 列出现有 `.desktop` 启动项。
- 启用/禁用。
- 新增应用到启动项。
- 显示 Exec、OnlyShowIn、Hidden 等字段。
- 校验 autostart 文件有效性。

### 6. 快捷键可视化是只读，不是完整配置 UI

`tahoe-shell/services/NiriSettings.qml:81` 明确 binds mirror 是 read-only。`NiriSettings.qml:456` 只是打开 config in editor。

`tahoe-shell/components/settings/pages/NiriKeyboardPage.qml:7` 说明 niri `binds {}` 是 replace-on-conflict authoritative block，GUI 不写它。`tahoe-shell/services/niri_settings_tool.py:846` 也只有 binds enumeration，没有 write path。

这是一条合理护栏，但对普通日用桌面来说，快捷键管理仍未闭环。

### 7. 窗口模型有真实基础，但合并逻辑有边界风险

`tahoe-shell/services/Windows.qml:386` 的 `mergeWindowModels()` 合并 niri IPC windows 和 Quickshell toplevels。`Windows.qml:488` 的 `findMatchingToplevel()` 先用 appId + title，再 fallback 到 appId。

风险：

- 同一应用多个窗口标题相同或快速变化时可能误关联。
- 只有 toplevel 没有 niri IPC id 的窗口，能力会降级。
- niri event stream 本身说明不是始终原子：`niri/niri-ipc/src/lib.rs:122` 到 `lib.rs:125` 说明事件顺序可能导致 window 暂时引用已移除 workspace。

这不是阻断，但会影响“桌面确定性”和调试成本。

### 8. 缩略图能力强，但失败路径会被用户感知

`niri/src/niri.rs:2046` 的 `window_thumbnail()` 只对找到且在 output 上的窗口成功，否则 `window not found or not on an output`。`niri/src/niri.rs:5933` 还要求窗口有 renderable thumbnail contents。

Shell 端 `ThumbnailProvider.qml:171` 会在队列满时失败，`ThumbnailProvider.qml:321` 每个 job 通过 `timeout 8s niri msg --json window-thumbnail` 执行。

这意味着任务切换和 overview 如果广泛依赖缩略图，必须有统一 fallback 视觉，不能每个组件各自处理。

### 9. desktop portal、窗口列表和录屏集成仍有补丁味

`niri/src/dbus/gnome_shell_introspect.rs:30` 说明 Shell 通常会把 Wayland app ID 匹配到 `.desktop` file，但 niri 这里还没做，所以 `xdg-desktop-portal-gnome` 的 window list 缺少 icons。`gnome_shell_introspect.rs:54` 还有 `WindowsChanged` signal 的 FIXME。

`niri/src/dbus/mutter_screen_cast.rs:72` 对 stream target 写着 FIXME：scale changes 等还未更新。

`niri/src/niri.rs:4934` 对动画期间 frame callbacks 有 FIXME，`niri.rs:4950` 还说明 hidden window screencast/frame callbacks 未完整实现，当前是 more eager redraw “happens to work by chance”。

这些不一定挡住日用，但会影响门户、录屏、窗口选择、窗口图标等完整桌面集成体验。

### 10. legacy tray 和 appmenu 仍依赖桥接状态

现代 SNI 托盘由 Quickshell 服务支持，`tahoe-shell/components/Tray.qml:4` 使用 `Quickshell.Services.SystemTray`。但 `tahoe-shell/services/SystemStatus.qml:162` 仍检查 `org.kde.StatusNotifierWatcher`，`SystemStatus.qml:172` 起检查 `xembedsniproxy` 作为 legacy tray bridge。

AppMenu 也依赖 helper、`python3`、`busctl` 和 registrar。`tahoe-shell/services/AppMenu.qml:35` 会刷新探测，`AppMenu.qml:149` 启动 `appmenu_probe.py`，`AppMenu.qml:178` 每 5 秒 polling。

结论：这类兼容能力有价值，但不是完全原生稳定层。

## 用户日常使用视角下的主要风险

### 风险 A：功能入口存在，但失败原因分散

用户会看到 Wi-Fi、蓝牙、截图、剪贴板、应用权限、AppMenu、搜索、打印、色彩、共享等入口，但这些入口背后的失败原因分散在 QML、shell script、Python helper、external command、DBus service 中。

现有健康页能降低排障成本，但长期应把 dependency status、action status、error detail 统一为一个可复用状态模型。

### 风险 B：普通用户以为能“管理权限”，实际只能读状态

应用权限页已经诚实提示普通桌面应用不能完整强制限制。后续任何 UI 都必须继续保持这种诚实性。不能为了完整感把 read-only portal/Flatpak/Snap 状态包装成统一可写权限开关。

### 风险 C：设置页外观完整，后端完成度不均衡

用户打开设置时会看到类似完整系统设置中心的分类。但部分页面只是 feature probe 或外部 GNOME 设置按钮。这会形成心理落差。

路线图应优先把最常用、最有闭环价值的页做实，而不是继续扩展占位入口。

### 风险 D：窗口任务体验依赖多来源合并

Dock、TaskSwitcher、WindowOverview 等都基于窗口模型。只要模型误合并、缺 id、event stream 短暂不一致，就会影响激活、最小化、恢复、缩略图、recent ordering。

这部分应作为反腐化优先级之一。

### 风险 E：视觉质感能力强，但材料和组件使用需要治理

compositor glass 已经具备高级参数，但如果每个组件随意调 radius、fill、stroke、interaction、materialAlpha，会造成“局部很炫、整体不统一”。材质体系需要一份稳定规范和单一来源。

### 风险 F：配置写入需要继续保持保守

`niri_settings_tool.py` 的写入是 whitelist 风格，这是正确方向。后续不要为了“完整设置 UI”扩大到任意 KDL 写入，尤其不要写 `binds` 权威全集，除非先有 AST 级编辑、冲突检测、备份、恢复和测试覆盖。

## 视觉质感提升方向

本节只讨论视觉材料、组件一致性和交互质感；不包含 GPU/渲染能力自适应优化。

### 1. 建立更严格的材质语义

当前 material vocabulary 已经存在，但还需要明确每种 material 的使用边界：

- `panel`：常驻面板、设置页容器、控制中心主体。
- `pill`：顶栏胶囊、动态岛、短状态承载。
- `dock`：Dock 背板和窗口架。
- `menu`：右键菜单、AppMenu、TrayMenu、popup 菜单。
- `toast`：通知 toast 和短暂反馈。
- `launcher`：Launchpad、Spotlight 这类中心浮层。
- `backdrop`：全屏 dim/scrim/overview background。

目标不是增加更多材料，而是避免同一种 surface 用多个近似材料，或不同语义 surface 共用同一视觉参数。

### 2. 状态反馈使用 compositor material，而不只是 opacity/scale

协议已经支持 `interaction`：`niri/resources/tahoe-glass-v1.xml:64` 说明它驱动 hover、press、enter animation 的 material easing。渲染端 `niri/src/render_helpers/tahoe_glass.rs:278` 会把 interaction boost 到 contrast、edge_highlight、refraction、inner_shadow、chromatic、lens_depth。

后续应把 hover、press、active、selected、urgent、focused 等状态映射到统一 interaction token：

- hover：轻微 edge highlight 和 inner shadow。
- press：短暂 refraction/contrast 增强。
- active/focused：更稳定的 edge highlight 或 stroke，不靠大面积变亮。
- urgent：不要只闪红，可以用 toast/material + status color 双通道。

### 3. 保持 region geometry 稳定，避免玻璃跳变

`niri/src/protocols/tahoe_glass.rs:173` 会校验 region，超出 surface、空 region、总面积异常都会被 drop。Dock 已经在 `tahoe-shell/components/Dock.qml:333` 注释里处理“niri rejects glass regions that extend outside the layer surface”。

后续所有玻璃组件应遵守：

- 不让 glass region 在 enter/exit 过程中越界。
- 尽量动画 materialAlpha，而不是动画 region bounds。
- 必须动画 geometry 时，确保 region 始终在 layer surface 内。
- 大型中心浮层不要整体 compositor scale，否则图标和玻璃会软，`tahoe-shell/components/Launchpad.qml:35` 已有类似经验。

### 4. fallback 视觉要和 TahoeGlass 主路径一致

`tahoe-shell/components/GlassPanel.qml:25` 仍保留 QML fill/stroke fallback。`config/niri/tahoe-phase0.kdl:88` 的注释说明 TahoeGlass regions 和 layer-rule background-effect fallback 是两条路径。

后续要避免主路径和 fallback 参数逐步漂移：

- material token 必须同时覆盖 TahoeGlass 和 fallback。
- fallback 不追求完全等价，但要保持 alpha、radius、stroke、阴影层级一致。
- 每个 surface 不要自己硬编码近似 fill/stroke。

### 5. 图标、缩略图和文字层级是质感关键

源码已有大量 macOS/Tahoe 风格图标资产，但日用桌面的质感不只来自玻璃。更应优先治理：

- 同一应用在 Dock、Launchpad、Search、WindowOverview 的 icon source 一致。
- 缩略图失败时有统一 placeholder，不出现尺寸跳动或空白卡。
- 设置页不要过度使用彩色分类 icon，系统设置应更安静、更可扫描。
- 大 surface 中的文字层级不要 hero 化，控制中心、设置、菜单应密度更高。

### 6. Shader 参数应保持“可读优先”

`config/niri/tahoe-phase0.kdl:97` 明确 chromatic 默认保持 0，避免文字出现 color fringes。`niri/src/render_helpers/shaders/postprocess.frag:177` 对 refraction clamp 到 0.12，`lens_depth` clamp 到 0.3。

后续视觉提升应通过场景化材料、状态反馈、边缘细节和层级关系实现，不应简单拉高 chromatic、refraction、blur。

## 反腐化局部重构路线图

路线图按“先护栏、再拆分、再增强”的顺序执行。每个阶段都必须保持功能兼容，不移除现有入口。

### Phase 0：建立基线和不可破坏清单

目标：

- 把当前功能入口列成 baseline。
- 明确哪些行为必须保持。
- 明确哪些路径是 fallback，哪些是主路径。

任务：

1. 新增或更新一份 `tahoe-shell/docs/desktop-functional-baseline-*.md`。
2. 覆盖 shell 主入口：Dock、Launchpad、Spotlight、通知、控制中心、设置、锁屏、任务切换、窗口总览、托盘、剪贴板、截图。
3. 对每个入口记录：
   - 主要文件。
   - 依赖服务。
   - 成功路径。
   - 降级路径。
   - 不能破坏的用户可见行为。

验收：

- 文档能作为后续 refactor checklist。
- 后续每个 PR/任务都能引用 baseline 中的受影响入口。

### Phase 1：统一 dependency/action 状态模型

问题：

`CommandRunner.qml`、`SystemFeatures.qml`、`SystemStatus.qml`、各服务页都在用自己的状态文本和依赖判断。长期会造成状态不一致。

目标：

- 不改变任何命令执行行为。
- 先统一状态 schema，再逐步复用。

建议结构：

- `services/StatusTypes.js`
  - `ok`、`warn`、`missing`、`broken`、`unknown`
  - `title`
  - `detail`
  - `impact`
  - `action`
  - `missing`
  - `updatedAt`
- `services/DependencyRegistry.qml` 或继续由 `CommandRunner.qml` 暴露，但内部结构收敛。

局部重构步骤：

1. 抽出纯 JS status helpers，不移动命令执行。
2. 让 `CommandRunner` 和 `SystemFeatures` 复用同一格式。
3. 设置页和健康页只读 status object，不拼接零散字符串。

不得做：

- 不删除任何现有 dependency probe。
- 不改变命令名称。
- 不改变用户可见按钮。

### Phase 2：窗口模型 merge 逻辑纯函数化

问题：

`tahoe-shell/services/Windows.qml` 同时负责 IPC process、event parsing、workspace sorting、toplevel merge、action dispatch。窗口模型是任务桌面的核心，不能继续让关键合并规则隐在大 QML 文件里。

目标：

- 保持 `Windows.qml` 对外 API 不变。
- 把 merge 和 normalization 变成可测试纯函数。

建议结构：

- `tahoe-shell/services/windows/WindowModel.js`
  - `normalizeIpcWindow(raw)`
  - `mergeWindowModels(toplevels, ipcWindows)`
  - `findMatchingToplevel(ipcWindow, toplevels, used)`
  - `buildWindowModel(ipcWindow, toplevel, fallbackIndex)`
- `tahoe-shell/tests/fixtures/windows/*.json`
  - 同 app 多窗口。
  - 相同 title。
  - title 变化。
  - no IPC id。
  - minimized。
  - urgent。
  - workspace missing transient。

验收：

- `Windows.qml` 对外属性名保持不变：`windowList`、`minimizedWindowList`、`recentWindowList`、`focusedWindow` 等。
- activate/minimize/restore/close 行为不变。
- 新增测试只覆盖纯函数，不要求启动 compositor。

### Phase 3：窗口缩略图 provider 成为唯一入口

问题：

当前 `ThumbnailProvider.qml` 已经集中，但后续 WindowOverview、TaskSwitcher、Dock 如果各自新增抓图逻辑，会腐化。

目标：

- 明确所有窗口预览都只能通过 `ThumbnailProvider`。
- 统一 fallback 视觉和错误状态。

任务：

1. 给 `ThumbnailProvider.qml` 写接口文档：
   - `requestThumbnail(window, width, height)`
   - cache key。
   - failure state。
   - cleanup 行为。
2. WindowOverview/TaskSwitcher 若接入缩略图，只调用 provider。
3. 建立 placeholder 组件，例如 `WindowPreviewFallback.qml`。

不得做：

- 不新增第二套截图接口。
- 不绕过 niri IPC 直接 screencopy。
- 不让组件自己 spawn `niri msg window-thumbnail`。

### Phase 4：设置中心 registry 和页面职责收敛

问题：

`SettingsModel.js` 已经有 panel registry 雏形，但 `SettingsPanel.qml` 仍承担页面堆叠、状态、服务注入、导航等很多职责。FeaturePage 同时承载多个系统域，容易让“占位页”和“真实页”混在一起。

目标：

- 让每个设置页清楚标识：native、feature-probe、external-link、read-only。
- 不移除任何现有页。
- 不伪装未完成后端。

建议结构：

- `SettingsModel.js` 增加字段：
  - `capability: "native" | "probe" | "external" | "readonly"`
  - `backend`
  - `externalPanel`
  - `writeScope`
- `FeaturePage.qml` 改名或拆出：
  - `FeatureProbePage.qml`
  - `ExternalSettingsPage.qml`
  - `ReadOnlyCapabilityPage.qml`

执行顺序：

1. 只加字段，不改 UI。
2. UI 显示能力级别和后端状态。
3. 再逐步替换 FeaturePage 的多重 if。

验收：

- 所有现有设置入口仍可打开。
- `search`、`online-accounts`、`sharing`、`wellbeing`、`color`、`printers`、`accessibility`、`privacy` 不再被误解成完整 native page。

### Phase 5：搜索 provider 拆分，但保持排序和行为

问题：

`Search.qml` 同时实现 command、calculator、screenshot、settings、system action、window、clipboard、app、task index。功能多后，很容易破坏排序、危险命令隔离或结果去重。

目标：

- 不改变用户搜索结果的主要排序。
- 把 provider 拆成纯函数模块或小 QML service。
- 保持 shell command 只在 `>` 或 `!` 前缀下出现。

建议结构：

- `services/search/CommandProvider.js`
- `services/search/CalculatorProvider.js`
- `services/search/SettingsProvider.js`
- `services/search/WindowProvider.js`
- `services/search/AppProvider.js`
- `services/search/TaskIndexProvider.qml`

特别护栏：

- `Search.qml:469` 的 command prefix 规则必须保留。
- `Search.qml:1084` 的 `runShellCommand()` 必须只由 command result 激活。
- 任务索引继续保持 timeout，不因拆分变成阻塞 UI。

### Phase 6：应用设置和权限能力模型化

问题：

Apps 页面已经能读默认应用、portal、Flatpak/Snap、存储等，但普通应用不可强制权限控制。这个边界必须在数据模型中显式表达。

目标：

- 把 `fullyEnforceable`、`sandboxType`、`portalStatus`、`staticPermissions`、`snapConnections`、`storage` 建成稳定 schema。
- UI 根据 schema 决定是开关、只读 row、警告 row 还是外部入口。

任务：

1. 给 `apps_settings_probe.py` 输出 schema 写文档。
2. 增加 fixture tests，覆盖：
   - ordinary desktop app。
   - Flatpak。
   - Snap。
   - portal store missing。
   - xdg-mime missing。
3. UI 禁止把 ordinary app permission 显示成可强制开关。

不得做：

- 不虚构普通应用 sandbox。
- 不把 Flatpak/Snap 静态权限当作 Tahoe 可完全写入的权限。

### Phase 7：niri 配置写入继续白名单化

问题：

`niri_settings_tool.py` 是重要但敏感的配置写入工具。当前 whitelist 写入 layout/glass/blur/input/animations/output.scale，binds 只读。这应继续保持。

目标：

- 加强测试和 managed block 边界。
- 不扩大到任意 KDL 编辑。
- 不写 binds。

任务：

1. 给每个可写 field 建表：
   - field name。
   - KDL path。
   - range。
   - validation。
   - rollback behavior。
2. 增加 malformed KDL、comments、multi-line、missing block fixtures。
3. `config_guardrails()` 继续阻止危险 broad namespace 和 VRR 默认开启。

不得做：

- 不实现快捷键写入。
- 不把整个 `config.kdl` 当自由文本重排。
- 不删除用户注释。

### Phase 8：shell 全局协调拆小，但保留 ShellRoot API

问题：

`shell.qml` 是全局 coordinator，管理 popup open state、screen selection、IPC、服务注入、Variants、组件实例。继续增加功能会让它变成无法维护的中心文件。

目标：

- 不拆掉 `ShellRoot`。
- 不改变 Quickshell IPC target。
- 局部抽出 popup/navigation state helper。

建议方向：

- `components/ShellPopupState.qml`
  - topbar popup open/close。
  - tray menu state。
  - closeTopBarPopups。
- `components/ShellNavigation.qml` 或 JS helper：
  - navigationScreenName。
  - screenName。
  - navigationOpenFor。

执行顺序：

1. 先复制测试或文档化现有 popup 互斥规则。
2. 抽 helper，但 `shell.qml` 的函数名保持 wrapper。
3. 组件继续调用原函数，不批量改调用点。

### Phase 9：视觉材质治理，不做 GPU 自适应

问题：

TahoeGlass 已经有强材质能力，但 QML tokens、KDL material profiles、shader 参数、fallback fill/stroke 需要长期保持同步。

目标：

- 建立 material governance。
- 统一 surface recipes。
- 不做 GPU/渲染能力自适应优化。

任务：

1. 新增 `tahoe-shell/docs/tahoe-material-governance.md`。
2. 列出每个 material 的用途、默认 radius、fill/stroke fallback、interaction range。
3. 给主要 surface 建 recipes：
   - TopBar。
   - Dock。
   - ControlCenter。
   - NotificationToast。
   - Launchpad。
   - Spotlight。
   - MenuPopup。
   - SettingsPanel。
4. 检查 `TahoeGlass.js`、`config/niri/tahoe-phase0.kdl`、`niri-config` defaults 三者是否漂移。

不得做：

- 不加入自动 GPU 探测。
- 不按 renderer 自动改 `useSpring`。
- 不为了视觉刺激提高 chromatic/refraction 默认值。
- 不删除现有 fallback。

### Phase 10：桌面完成度路线优先级

在反腐化基础上，日用桌面能力应按以下优先级补齐：

1. 设置中心真实后端：
   - autostart manager。
   - default apps schema 和测试。
   - privacy/apps read-only vs enforceable 能力区分。
   - printers/color/accessibility 的明确外部入口和状态模型。
2. 搜索：
   - provider 拆分。
   - 最近文件/文件夹结果质量。
   - 可选 Tracker backend，但必须可缺失降级。
3. 窗口任务：
   - WindowOverview/TaskSwitcher 复用 ThumbnailProvider。
   - 统一 thumbnail fallback。
   - merge fixtures。
4. 视觉质感：
   - material governance。
   - region geometry 稳定。
   - interaction state 一致。
   - icon/thumbnail/text density polish。

## 建议的验收命令

本文没有执行实际测试。后续每个实现任务至少应按改动范围运行：

```bash
bash scripts/check-tahoe-glass-guardrails.sh
python3 tahoe-shell/services/niri_settings_tool.py read --config config/niri/tahoe-phase0.kdl
python3 -m pytest tahoe-shell/tests
```

涉及 niri Rust 代码时：

```bash
cargo test --manifest-path niri/Cargo.toml -p niri-ipc
cargo test --manifest-path niri/Cargo.toml -p niri-config
cargo test --manifest-path niri/Cargo.toml -p niri
```

涉及 shell QML 结构时，应至少做静态加载检查或现有 quickshell 启动检查；但按本研究范围，实机视觉/交互测试不计入当前结论。

## 最终取向

项目现在最需要的不是继续堆新面板，也不是把玻璃效果调得更夸张，而是把已经做出来的桌面能力变成可维护的产品结构：

- 真实能力和占位能力分清。
- 外部命令和依赖状态收敛。
- 窗口模型可测试。
- 缩略图入口唯一。
- 设置写入保持保守白名单。
- 视觉材质有统一治理。
- 所有局部重构都保持现有功能不破坏、不移除、不削弱。

这样做能逆转腐化趋势，同时给后续补齐完整日用桌面留下清晰、安全的扩展空间。
