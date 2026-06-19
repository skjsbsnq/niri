# Tahoe 设置面板重做与 niri 设置接入：研究与改进路线图

日期：2026-06-19

状态：研究与计划文档；本文件不代表已实现。后续实现必须按本文顺序推进，完成一个阶段
并通过验收后，才能开始下一个阶段。本专题是
`sequential-daily-desktop-roadmap-2026-06-19.md` 中「阶段 6：Settings / About /
系统健康页」（已完成，验收见 `phase6-settings-health-about-acceptance-2026-06-19.md`）
之后的专题延伸，因此阶段号改用 S0–S5，避免与既有数字阶段冲突。

依据：当前源码优先，其次 `git log`（父仓库 148 个提交 + niri/quickshell 子模块提交）、
既有文档（`sequential-daily-desktop-roadmap-2026-06-19.md`、`gap-analysis.md`、
`glass-compositor-architecture-roadmap.md`、`tahoe-glass-guardrails.md`、
`vmware-icon-vanish-handoff.md`、`phase6-settings-health-about-acceptance-2026-06-19.md`）。
本轮重点阅读：`tahoe-shell/shell.qml`、`tahoe-shell/components/SettingsPanel.qml`、
`tahoe-shell/components/PopupDismissLayer.qml`、`tahoe-shell/components/TahoeGlass.js`、
`tahoe-shell/services/DesktopSettings.qml`、`tahoe-shell/services/Appearance.qml`、
`config/niri/tahoe-phase0.kdl`、`scripts/check-tahoe-glass-guardrails.sh`、
`scripts/arch-update.sh`。

## 用户新增问题记录

- 设置面板「长得很丑、和 macOS 差距大、可用性不足」。
- 很多设置缺失，**包括 niri 自己的设置**（键位、布局、动画、玻璃、输入/输出等）一个都没接进 GUI。
- 改进必须分阶段、严格顺序，每阶段含注意事项，且**不得重新引入 git log 里已修好的问题**。

## 当前结论

设置面板的基础闭环已在阶段 6 完成（外观深浅色/夜览/色温、勿扰、通知历史、输入法、截图目录、
Dock 标题模式、启动项、系统健康、关于，均持久化且从菜单/Spotlight/IPC 可达）。但它有三个根因性问题：

1. **功能面窄**：真正可写的设置约 10 个，全部走 `desktop-settings.json` + `appearance.json`，
   完全没有触及 niri 的 `config.kdl`（566 行、几十项配置）。
2. **外观自制、未对齐 macOS**：单色 Material Icons、颜色常量写死在面板里、无深色模式、
   控件全为文件内 `component`（滑块用 ±250 按钮、目录用裸 `TextInput`、开关/按钮自绘）。
3. **架构紧耦合**：`SettingsPanel.qml` 单文件 1640 行，11 个内联 component，12 个 service
   property 里有 7 个声明了但模板完全没用（死代码）。

niri 设置一直没接的根因是技术性的：niri 配置是 KDL 文本，niri 只用 knuffel **解析**、
**不生成**，项目里没有 KDL writer；且 `arch-update.sh` 会用 `install -m644` 覆盖
`~/.config/niri/tahoe/config.kdl`，用户手改有被覆盖风险。好消息是 **niri 会热重载
config.kdl**（500ms mtime 轮询，几乎所有项 diff 后即应用），并支持 `include`，且
`niri msg action load-config-file` 可强制立即重读——这给「改了就生效」留出了可行路径。

旧文档 `gap-analysis.md` 中「About/Settings 仍未接」等条目已滞后（阶段 6 已接），
按 `sequential-daily-desktop-roadmap` 的规则，后续一律以源码复核为准，不按旧文档重复开工。

## 串行执行规则

沿用 `sequential-daily-desktop-roadmap-2026-06-19.md` 的串行规则，重述并补充：

1. 同一时间只能有一个阶段处于实现中。阶段 N 未验收通过前，禁止开始阶段 N+1。
2. 每个阶段只解决该阶段目标，不夹带无关视觉重做、重命名、格式化或大范围重构。
3. 每个阶段完成后必须跑对应回归检查；失败时只修当前阶段，不继续叠新功能。
4. **已修复的行为优先级高于新功能**。若新功能和既有护栏冲突，先调整方案，不硬做。
5. 文档、实现、验收记录必须能对应到源码事实。旧文档只作历史参考。
6. 工作区已有用户改动时，不回滚、不覆盖；只在当前阶段必要文件内做最小改动。
7. 每个阶段独立提交；提交前必须看 `git diff`，确认没有带入其他阶段内容。
8. **本专题新增**：任何会生成或改写 niri `config.kdl` 的代码，其产物必须通过
   `niri validate` 与 `scripts/check-tahoe-glass-guardrails.sh`，否则该阶段不验收。

## Git Log 回归护栏（不得重新打坏）

以下修复在设置面板重做与 niri 接入过程中尤其相关，分五组。

### A. 设置面板与持久化（直接相关）

- `666c3c8 Fix shell crash: Controls service root must be Item not QtObject`
  —— 新增 `NiriSettings` service **根必须是 `Item { visible: false }`，不能用 `QtObject`**，否则 shell 崩溃。
- `64fc080 Harden Tahoe state persistence`、`e814371 Persist Tahoe shell user state`
  —— 持久化走 `FileView`+`JsonAdapter`+`watchChanges`，且 `arch-update.sh` 含 state 迁移逻辑。
  新 service 持久化必须照搬，不得自创并发写路径。
- `921b9f5 Fix Tahoe dock pin reload`、`4aff384 Fix dock pin persistence and launchpad layout`
  —— 持久化值变更后必须能正确 reload；Dock 标题模式等已有偏好不能因重构回退。

### B. Popup 与 dismiss（设置面板是 overlay 弹窗）

- `dc5bef9 Revert "Close Tahoe popups on outside click"`（撤销 `86d42fe`）
  —— **不要在弹窗内部做 outside-click 关闭**。顶栏 popup 走独立的
  `PopupDismissLayer.qml`（全屏层 + `mask` Region Subtract 挖洞 + MouseArea）。
  **设置面板不走 PopupDismissLayer**，它用自身全屏 MouseArea dismiss（`SettingsPanel.qml`
  的遮罩 `Rectangle` + `MouseArea { onClicked: closeRequested() }`）。重做时**不得改这个
  已工作的 dismiss 机制**，不得引入点击穿透、误关、原生白菜单。
- `27962da Fix Tahoe top bar popup dismissal`、`9333442 Fix Tahoe popup surface regression`、
  `fe74085 Fix Tahoe popup and tray behavior`、`b688ede Tighten Tahoe popup and dock placement`、
  `686b84e Fix Tahoe popup top offsets`、`c770c65 Polish Tahoe shell popups and session power`
  —— popup surface/dismiss 是反复调试过的；设置面板的 surface（namespace `tahoe-settings`、
  overlay 层、bounded TahoeGlass region、modal close）是阶段 6 验收基线，不得破坏。

### C. 玻璃协议与渲染稳定（设置面板有 TahoeGlass region）

- `b7b8e5a Complete Phase 1: unify TahoeGlass coordinate contract to surface-local logical`
  （子模块对应 `6f489e3`）—— TahoeGlass region 坐标**必须是 surface-local logical**。
  设置面板现有 `TahoeGlass.regions` 用 `panel.x + panelSurface.x` 等逻辑坐标，重做不得改成
  屏幕坐标或带 DPR 缩放。
- `0704ea4 Fix region-overflow crash: drop springs on blur-region item geometry`
  （niri 子模块 `9dae619f Saturate region rect coordinate additions`、`110693a Drop overflowing
  blur rects`）—— **blur/TahoeGlass region item 的几何一律禁用 spring**，只能用 bounded
  `NumberAnimation`。设置面板现用 `Behavior on opacity/scale`（NumberAnimation），保持即可；
  不得给 region 几何加 SpringAnimation。
- `0772586 Fix login crash: drop blur region from notification toast`
  —— 某些 surface 不能挂 blur region（会登录崩溃）。设置面板的 region 已验证安全，不要随意新增
  会触发全屏 blur / 超大 rect 的 region。
- `74b384a Disable xray for Tahoe glass` —— glass region 的 xray 必须关。

### D. niri 配置与键位（接入 niri 设置直接相关）

- `441b637 Avoid overriding niri MRU binds` —— **不要在 config binds 里覆盖 niri 最近窗口
  （MRU）/ task switcher 行为**。Tahoe 任务切换走 IPC（`cycleTaskSwitcher`，见 `shell.qml`
  IpcHandler + `config` 的 `Mod+Ctrl+Tab` spawn-sh 调 ipc），**不是 binds**。改键位功能必须
  保留这一分离，不得把 task switcher 变回 binds、不得删除/覆盖 MRU 相关默认 binds。
- guardrails 硬约束（`scripts/check-tahoe-glass-guardrails.sh`，CI 级）：
  - niri config **不得默认启用 `variable-refresh-rate`**；
  - **不得有 broad `namespace="^quickshell"` 玻璃/阴影规则**；
  - **必须有 explicit `tahoe-` namespace 规则**；
  - QML **不得直接用 `BackgroundEffect`/`blurRegion`**（必须走 TahoeGlass region 协议）。
  **本专题生成的任何 KDL 都不得触发上述任一检查失败。**

### E. VM / 软件渲染兼容

- `vmware-icon-vanish-handoff.md` + `7ae4f08 Revert dock feel tweaks back to 14e46d0`、
  `f0e2c14`、`54c58b4` —— Image 几何 spring 在 VM/软件渲染下可能导致图标纹理消失。
  设置面板新增的图标/动画**不得移除 `useSpring` 降级路径**（`shell.qml` 的 `useSpring` 全局开关）。

## 现状研究

### 1. 设置面板现状（源码事实）

- `tahoe-shell/components/SettingsPanel.qml`：1640 行，`PanelWindow`，namespace
  `tahoe-settings`，overlay 层，全屏居中面板（`panelWidth ≤ 1080`、`panelHeight ≤ 720`，
  glass 壳用 `GlassStyle.FillPanelBright`/`StrokePanelBright`/`RadiusPanel`）。
- 结构：左侧栏（188px，8 个 `SidebarButton`：概览/外观/通知与输入/截图/Dock/启动项/系统健康/关于）
  + 右侧内容（标题/副标题 + 关闭按钮 + 多个 `Flickable` 页面）。
- 内联 component 共 11 个：`SidebarButton`、`SummaryTile`、`SectionBox`、`SettingRow`、
  `ToggleRow`、`ActionButton`、`IconButton`、`ModeButton`、`HealthCounter`、`StatusRow`、`AboutRow`。
- 颜色常量**写死在文件内**（`textPrimary #1d1d1f`、`accentBlue #2c9cf2`、`sectionFill #24ffffff`
  等），未复用 `TahoeGlass.js`，**无深色模式分支**（对比 `ControlCenter.qml:29-42` 有完整
  `darkMode ? A : B` 体系）。
- 控件缺陷示例：夜览色温用 `ActionButton "-250"/"+250"`（应滑块）；截图目录、启动项备注用
  裸 `TextInput`（应规范输入/文件选择）；开关/按钮全自绘。
- service property：声明 12 个（`settingsService`…`windowsService`），其中
  `screenshotService`/`controlsService`/`clipboardService`/`batteryService`/
  `powerProfileService`/`fanService`/`windowsService` **共 7 个在模板里完全没被引用**（死代码）。
- 挂载点：`shell.qml:701-718` 在 `Variants`（每屏一份）里实例化，`open` 绑
  `navigationOpenFor(settingsPanelOpen, settingsPanelScreenName, modelData)`；
  打开入口：MenuPopup（`openSettingsRequested`）、Search（`openSettingsRequested`）、
  IPC（`openSettings/openAbout/openSystemHealth/closeSettings`），统一走
  `shell.openSettingsPanel(page)`（`shell.qml:254`）。

### 2. 现有 service 接口契约（重做必须保留）

实际被面板调用的接口（删掉死代码后必须继续支持）：

- `DesktopSettings`：`effectiveScreenshotDirectory`、`screenshotDirectory`、
  `screenshotCopyToClipboard`、`screenshotOfferActions`、`dockWindowTitleMode`、`modeLabel(m)`、
  `startupNote`、`homeDir`、`settingsPath`；写：`setDockWindowTitleMode`、`setScreenshotDirectory`、
  `resetScreenshotDirectory`、`setScreenshotCopyToClipboard`、`setScreenshotOfferActions`、
  `setStartupNote`、`openAutostartFolder`。
- `Appearance`：读 `darkMode`/`nightMode`/`colorTemperature`；写 `setDarkMode`/`setNightMode`/
  `setColorTemperature`（apply 走 `Quickshell.execDetached` 调 gsettings/gammastep，**不写外部配置**）。
- `SystemStatus`：`okCount`/`warnCount`/`missingCount`/`statusItems`/`aboutItems`/`refreshing`/
  `lastUpdatedText`/`lastError`；`refresh()`（跑 `appmenu_probe.py`，见 `012626e` 的 DBus 激活修复）。
- `Notifications`：`historyCount`、`dndEnabled`；`toggleDnd`、`clearEverything`。
- `InputMethod`：`available`、`tooltipText`；`toggle`、`refresh`。

### 3. niri 配置机制（命门）

- 源文件 `config/niri/tahoe-phase0.kdl`（566 行）经 `scripts/arch-update.sh` 的
  `deploy_niri_config()`（`install -m644`）复制到 `~/.config/niri/tahoe/config.kdl`；
  会话用 `niri --config ~/.config/niri/tahoe/config.kdl` 启动（`run-tahoe-session.sh`）。
  **用户默认 `~/.config/niri/config.kdl` 不被动**。
- **niri 热重载**：`niri/src/utils/watcher.rs` 500ms 轮询 mtime（含 canonical 路径、symlink），
  变化即在 `State::reload_config`（`niri/src/niri.rs:1432+`）diff 并应用。已确认热重载覆盖：
  `layout`（gaps/焦点环/边框/阴影/snap-assist/背景色）、`animations`、`environment`、`cursor`、
  `input.keyboard`（xkb/重复率）、`input.touchpad/mouse/...`、`outputs`、`binds`、
  `window_rules`/`layer_rules`、**fork 专有 `tahoe-glass` 与 `recent-windows`**、`xwayland-satellite`。
- `niri msg action load-config-file [--path 绝对路径]`：跳过 500ms 等待强制重读。
- **IPC 改不了配置值**：`niri-ipc` 的 `Output` IPC 是「临时改、不落盘」，其余 IPC 只能触发 action
  或查询。tahoe-glass / recent-windows / layout gaps / 键位 / 动画**无 IPC 捷径**，只能写 config。
- **KDL 无现成 writer**：niri 用 `knuffel = "3.2.0"`（`niri-config/Cargo.toml`）只 decode；
  项目 `tools/`/`scripts/`/`patches/` 无 KDL 生成代码；唯一的 py 是一次性 `appmenu_probe.py`，
  非常驻 sidecar。读写 KDL 需自建一层。
- **include 支持**：`niri-config/src/lib.rs:171,301-398` 支持 `include "path"`（带递归检测，
  被 include 的文件也被 watcher 监听）。**合并语义待实现阶段验证**（重复顶层 section 的处理）。
- guardrails 见上文 D 组。

### 4. 视觉与控件现状

- 图标：`assets/icons/` 全是 PNG 应用图标，**无 macOS System Settings 那种彩色圆角方块
  分类图标**；仅 `MaterialIconsRound.ttf` 单色字体。Web 参考 `icon/` 也无彩色分类图标，
  其 settings 侧栏靠 `background/sidebar.png` 纹理图（`gap-analysis.md:197`）。
- 字体：`assets/fonts/` 仅 `MaterialIconsRound.ttf`；正文走 `shell.qml` 全局
  `Noto Sans CJK SC`（`baseFontFamily`）。**未引入 SF Pro**（许可风险，且中文支持差）。
- 设计 token：`TahoeGlass.js`（39 行）只有玻璃材质层常量；业务色板碎片化在
  `SettingsPanel.qml`（写死浅色）、`ControlCenter.qml`（带深色模式）两处。
- 可复用控件：**全是文件内 `component`，跨文件不可复用**。已知重复：Toggle×3
  （WifiPopup/FanPopup/ControlCenter）、Slider×2（ControlCenter `GlassSlider`/FanPopup `FanSlider`）、
  MenuRow×4、IconButton×3。**0 个 QtQuick.Controls Slider**，6 处裸 `TextInput`，无 Stepper。
- macOS 参考 token（`macOS-26-Tahoe-for-the-Web-main/Css/style.css`）：系统蓝 `#007ff7`、
  settings 窗口 `900×550 radius 25`、`blur 60px`、SF Pro Display。当前面板用 `#2c9cf2`（偏浅）。

## 关键技术决策与待验证（注意事项汇总）

1. **KDL 写回策略（阶段 S3 核心决策）**：两条路——
   - 路线①：精确编辑主 `config.kdl`（保留注释，行/块级定位替换）。优点：所见即所得、立即热重载。
     风险：`arch-update.sh` 源文件变更时会覆盖用户改动。
   - 路线②：`include "user-overrides.kdl"` 隔离。优点：arch-update 不碰用户文件。风险：
     **niri include 对重复顶层 section（如两个 `layout {}`）的合并/覆盖语义未验证**，
     需在阶段 S3 先做实验确认；若语义不支持，则改用「GUI 拥有的整块 section 外提到独立文件，
     主 config 用 include 引入，主 config 不再写这些 section」的一次性重构。
   - **建议**：阶段 S3 先验证 include 合并语义；主路径采用「精确编辑 + 写完 `load-config-file`」，
     并在 `arch-update.sh` 增加覆盖前的用户改动备份/三方合并提示；include 隔离作为 S3 内的
     并行实验，验证通过则采纳为长期方案。
2. **原子写**：仿 `Quickshell` FileView 原子写（临时文件 + `mv`），避免半写被 watcher 读到
   导致 KDL parse error 触发 niri 的 `config_error_notification` 弹窗（`niri.rs:1437-1445`）；
   写后必要时 `touch` 确保 mtime 变化。
3. **生成物的合规性**：任何写出的 KDL 必须 `niri validate` 通过 + guardrails 全绿
   （VRR 默认关、无 broad quickshell 规则、保留 tahoe- namespace 规则）。**GUI 不得提供
   会生成违规配置的开关**（例如不得提供「启用全局 VRR」之类会破坏 guardrails 的项）。
4. **键位（binds）改键的边界**：niri 不合并默认 binds，`binds {}` 一旦存在即权威全集
   （见 `config` 顶部注释）。改键功能必须保证 binds 块整体仍完整、不覆盖 MRU/task-switcher
   相关项（`441b637`）。键位编辑放在较后阶段（S5），且优先「查看 + 受限改键」。
5. **字体**：维持 `Noto Sans CJK SC` 为主字体（中文 + 拉丁覆盖），通过字重/字号/字距逼近
   SF Pro 观感；**不引入 SF Pro**（许可）。纯拉丁场景如需更接近可后续评估 Inter，非本专题必需。
6. **彩色分类图标**：阶段 S1/S2 采用「Material Icons 字形 + 彩色圆角方块背景」
   （`TahoeCategoryIcon`，类 Web 参考 `.cc-icon-circle` 放大为方块）作为快速方案；
   自绘 SVG 渐变彩色图标列为 S5 之后的质量提升，非阻塞。
7. **不破坏 dismiss / glass / 持久化既有契约**：见回归护栏 A–E，每个阶段验收都对照。

## 阶段 S0：基线与研究文档落地

目标：本文档定稿落盘；复核当前设置面板验收基线（阶段 6）与全量回归检查；无功能代码改动。

工作范围：

- 记录当前 `git status --short`，确认工作区已有改动（当前：`tahoe-shell/services/__pycache__/`
  未跟踪），不回滚、不覆盖。
- 跑 `scripts/check-tahoe-glass-guardrails.sh`、`scripts/check-submodules.sh`、
  `niri/target/release/niri validate -c config/niri/tahoe-phase0.kdl`；失败记录原因，不静默跳过。
- 手动 smoke：启动 Tahoe session，从菜单/Spotlight/IPC 三条入口打开设置面板，逐页过一遍
  现有设置（外观/通知/截图/Dock/启动项/健康/关于），确认无回归。
- 落盘本文件。

验收：

- 三项检查脚本退出码为 0（或失败有明确环境原因记录）。
- 设置面板现有功能 smoke 全通过，无 load failure。
- 工作区只有本文件新增，无其他代码改动。

退出门槛：S0 通过后才允许进入 S1。

### 阶段 S0 验收记录（2026-06-19）

- 工作区基线：`git status --short` 显示本文件为新增文件，且存在既有未跟踪目录
  `tahoe-shell/services/__pycache__/`；未回滚、未清理、未覆盖该目录。
- `scripts/check-tahoe-glass-guardrails.sh`：退出码 0。确认 VRR 默认关闭、无 broad
  `namespace="^quickshell"` 规则、保留 explicit `tahoe-` namespace 规则，且 QML 未直接使用
  `BackgroundEffect`/`blurRegion`。
- `scripts/check-submodules.sh`：直接执行因脚本无可执行位（`-rw-r--r--`）返回 126；用
  `bash scripts/check-submodules.sh` 执行同一脚本内容，退出码 0。保留原文件权限不改动。
- `niri/target/release/niri validate -c config/niri/tahoe-phase0.kdl`：退出码 0，
  `config is valid`。
- 设置面板 smoke：当前 Tahoe 会话中 niri 与 quickshell 均在运行；通过 Quickshell IPC 验证
  `openSettings`、`openAbout`、`openSystemHealth`、`closeSettings` 可用，`niri msg layers`
  可见/清除 `tahoe-settings` overlay，截图确认概览、关于、系统健康页均渲染，无 QML load
  failure。菜单/Spotlight 入口依据源码 wiring 均进入同一个 `openSettingsPanel(page)`；不再重复
  做交互点击测试。
- 本阶段未改功能代码、未改 niri 配置、未进入 S1。

## 阶段 S1：单文件拆分 + 通用控件库 + theme token（零行为变化）

目标：把 `SettingsPanel.qml` 1640 行拆为可维护结构，**纯重构，像素级行为不变**。

当前源码事实：

- 单文件 1640 行、11 个内联 component、9 个写死颜色常量、12 个 service property（7 个死代码）。
- 全项目控件重复 20+ 处（Toggle×3/Slider×2/MenuRow×4/IconButton×3），均为文件内 component。

建议方案：

- 新建 `tahoe-shell/components/settings/` 目录：
  - `SettingsTheme.js`：统一业务 token（迁移面板 9 个颜色常量）+ 深色模式
    （照搬 `ControlCenter.qml:29-42` 的 `darkMode ? A : B`，接 `shell.darkMode`）。
  - `controls/TahoeSwitch.qml`（合并 ToggleSwitch ×3）、`controls/TahoeSlider.qml`
    （提取 `ControlCenter.qml:702 GlassSlider`，支持图标/标签/数值）、
    `controls/TahoeListRow.qml`（合并 SettingRow + MenuRow 模式）、
    `controls/TahoeSection.qml`（提取 SectionBox）、`controls/TahoeButton.qml`
    （合并 ActionButton/IconButton）、`controls/TahoeTextField.qml`（封装裸 TextInput）。
  - `pages/OverviewPage.qml`、`pages/AppearancePage.qml`、`pages/NotificationsPage.qml`、
    `pages/ScreenshotPage.qml`、`pages/DockPage.qml`、`pages/StartupPage.qml`、
    `pages/HealthPage.qml`、`pages/AboutPage.qml`：把现有各页内容原样搬入。
- `SettingsPanel.qml` 瘦身为：壳 + glass region + 左侧栏路由 + 右侧 `Loader`/`StackLayout` 按页切换。
- 删 7 个死代码 service property（保留实际用到的 5 个）。
- **本阶段不改任何设置项内容、数量、外观像素、交互行为**。色温仍是 ±250 按钮、目录仍是
  裸 TextInput——这些在 S2 才换。本阶段只是「搬家」。

注意事项：

- service 根必须 `Item`（`666c3c8`）；本阶段不新增 service。
- 不碰 dismiss 机制（自身 MouseArea）、不碰 glass region 几何（不用 spring，`0704ea4`）、
  不碰 TahoeGlass 坐标契约（`b7b8e5a`）。
- 不改 `shell.qml:701-718` 的挂载与 service 注入契约。

验收：

- 拆分前后逐页截图/交互完全一致（概览 tile、各 SectionBox、健康行、关于行、开关、按钮）。
- `qmllint` 对新/改 QML 退出 0（Quickshell 类型未解析警告可接受）。
- `check-tahoe-glass-guardrails.sh`、`niri validate`、`check-submodules.sh` 退出 0。
- IPC `openSettings/openAbout/openSystemHealth/closeSettings` 仍正常。

回归检查：对照 `666c3c8`、`dc5bef9`、`0704ea4`、`b7b8e5a`、`64fc080`、phase6 基线。

退出门槛：S1 全部验收通过后才允许进入 S2。

### 阶段 S1 验收记录（2026-06-19）

- 完成 `SettingsPanel.qml` 单文件拆分：主文件从 1640 行降到 365 行，仅保留窗口壳、
  全屏遮罩 dismiss、TahoeGlass region、标题栏、侧栏挂载和 `StackLayout` 页面路由。
- 新增 `tahoe-shell/components/settings/`：
  - `SettingsTheme.js`：承接原设置面板业务色板、状态 label/color token；本阶段保持原浅色像素值，
    不提前做 S2 视觉改动。
  - `SettingsSidebar.qml`：搬出原左侧栏、badge 和设置路径显示。
  - `controls/`：`TahoeSwitch`、`TahoeButton`、`TahoeListRow`、`TahoeSection`、
    `TahoeTextField`、`TahoeSlider`、`TahoeSidebarButton`、`TahoeSummaryTile`、
    `TahoeHealthCounter`、`TahoeStatusRow`、`TahoeAboutRow`。
  - `pages/`：`OverviewPage`、`AppearancePage`、`NotificationsPage`、`ScreenshotPage`、
    `DockPage`、`StartupPage`、`HealthPage`、`AboutPage`。
- 删除设置面板 7 个未使用 service property，并同步移除 `shell.qml` 中对应死注入；
  保留实际使用的 `settingsService`、`systemStatusService`、`appearanceService`、
  `notificationsService`、`inputMethodService` 注入契约。
- 未改 `SettingsPanel` 的 overlay namespace、全屏 MouseArea dismiss、TahoeGlass region 坐标、
  panel 几何动画、niri 配置或持久化 service。
- `/usr/lib/qt6/bin/qmllint -I quickshell/build-tahoe/qml_modules ...`：退出码 0；仅余
  Quickshell/TahoeGlass 自定义类型导致的可接受警告（`PanelWindow` uncreatable、
  `TahoeGlassRegion` incomplete type、region id unqualified）。
- 临时启动新 Quickshell 实例并用其 PID 调 IPC：`openSettings`、`openAbout`、
  `openSystemHealth` 均使 `niri msg layers` 出现 `tahoe-settings` overlay；
  `closeSettings` 后 overlay 清空。启动日志无拆分组件相关 QML load failure；仅见既有
  `shell.qml:322` 字体只读警告和 portal app-id 警告。
- `scripts/check-tahoe-glass-guardrails.sh`：退出码 0。
- `bash scripts/check-submodules.sh`：退出码 0。
- `niri/target/release/niri validate -c config/niri/tahoe-phase0.kdl`：退出码 0，
  `config is valid`。

## 阶段 S2：macOS 风格外观收敛（用 S1 控件库 + theme）

目标：在 S1 结构上重做观感，**只改外观，不改设置项内容/数量**。

建议方案：

- `TahoeCategoryIcon`：Material Icons 字形 + 彩色圆角方块背景（每分类一个品牌色，
  Wi-Fi/Dock/外观/截图/启动项/健康/关于各一色），替换左侧栏灰色单色图标。
- 系统蓝从 `#2c9cf2` 改 `#007ff7`（Web 参考）；统一密度/间距/字号字重/分组圆角
  （section radius 18、row radius 14）。
- 色温：`ActionButton ±250` → `TahoeSlider`（2500–6500K，带数值标签）。
- 截图目录/启动项备注：裸 `TextInput` → `TahoeTextField`（规范内边距/对齐/焦点态）。
- 开关/按钮统一用 `TahoeSwitch`/`TahoeButton`。
- 深色模式：`SettingsTheme.js` 接 `shell.darkMode`，面板支持深浅色（照 ControlCenter 模式）。
- 面板尺寸向 `900×540`、radius 更接近 macOS 收敛（不破坏 glass region 安全区）。

注意事项：

- 不引入 SF Pro；不破坏 glass（region 几何不用 spring、坐标 surface-local）；
  `TahoeCategoryIcon` 若有缩放动画保留 `useSpring` 降级（VM 兼容，`vmware-icon-vanish-handoff`）。
- 不改 dismiss；不改 service 接口。

验收：

- 侧栏图标彩色化、系统蓝、滑块、规范输入、深色模式可读；逐页外观对照 macOS 参考。
- guardrails / niri validate / qmllint 通过；现有设置全部仍可读写且持久化。

回归检查：同 S1 + 动画/性能（无 idle churn，对照 `d77684a`）。

退出门槛：S2 全部验收通过后才允许进入 S3。

### 阶段 S2 验收记录（2026-06-19）

- **范围**：在 S1 结构上重做观感，未改设置项内容/数量、未改 dismiss、未改 service
  接口、未改 niri 配置。工作区改动仅限设置面板（15 文件修改 + 1 新增），无夹带其他阶段内容。
- **`TahoeCategoryIcon`（新增）**：Material Icons 字形 + 实心彩色圆角方块背景（顶部
  `#59ffffff` 内高光，两种模式通用），无 spring/无缩放动画（VM 安全，护栏 E）。
- **侧栏彩色化**：8 个分类按钮各走 `SettingsTheme.categoryColor(key)` 品牌色
  （外观 indigo `#5856d6`、通知 red `#ff3b30`、截图 coral `#ff7a59`、Dock blue `#0a84ff`、
  启动项 orange `#ff9f0a`、健康 green `#34c759`、概览/关于 gray `#8e8e93`）；Logo 改为
  蓝色彩色方块。概览 summary tile 的 `accentColor` 同步走 `categoryColor`，使侧栏与概览
  图标色一致（状态细节仍由文字承载）。
- **系统蓝**：`accentBlue` 由 `#2c9cf2` 改为浅色 `#007ff7` / 深色 `#0a84ff`（Web 参考）。
- **色温滑块**：AppearancePage 的 `ActionButton ±250` 替换为 `TahoeSlider`（2500–6500K，
  归一化 0..1 映射，带 `valueText`「xxxxK」标签，点击/拖拽均触发
  `setColorTemperature`，沿用既有 `Appearance` service，无新写盘路径）。
- **规范输入**：截图目录、启动项备注继续走 `TahoeTextField`，新增聚焦态
  （`fieldStrokeFocus` = 系统蓝 + 80ms 边框动画）。
- **开关/按钮统一**：`TahoeSwitch` off 轨、`TahoeButton` primary/normal 填充与描边全部
  走 theme token（`switchOff`/`buttonFill`/`buttonStroke`/`accentFillStrong`/`accentStrokeStrong`）。
- **深色模式**：`SettingsTheme.js` 全量 token 增加 dark 分支（照搬 `ControlCenter.qml`
  模式：文本 `#f5f7fb`/`#1d1d1f`、分组/行/侧栏/按钮/字段/滑块/开关/tile/hero/scrim 各一对
  深浅值）；浅色像素值除 `accentBlue` 外保持 S1 基线不变。`stateColor`/`stateLabel` 经
  panel root 透传 `darkMode`；健康计数器走 `theme.stateColor(...)`。
- **面板尺寸**：`panelWidth` 上限 1080→900、`panelHeight` 上限 720→540（向 macOS 900×540
  收敛）；glass region 仍跟随 `panelSurface` 几何（surface-local logical，`b7b8e5a`），
  缩小不破坏安全区，几何无 spring（`0704ea4`）。
- **回归检查**：
  - 未碰 dismiss（自身全屏 MouseArea，`dc5bef9`）；未碰 TahoeGlass region 坐标/几何动画
    （`b7b8e5a`/`0704ea4`）；未碰 `shell.qml:701-718` 挂载与 service 注入；未新增 service
    （根须 Item，`666c3c8`）；未用 `BackgroundEffect`/`blurRegion`（护栏 D）；`useSpring`
    全局开关未被新动画依赖。
  - 无 idle churn：新动画仅文本字段聚焦边框（80ms 一次性）与既有 panel opacity/scale
    （NumberAnimation）；滑块仅在拖拽时更新填充宽度（对照 `d77684a`）。
- **检查脚本**：
  - `/usr/lib/qt6/bin/qmllint -I quickshell/build-tahoe/qml_modules`（21 个 settings QML +
    `SettingsPanel.qml`）：退出码 0，零警告（较 S1 更净）。
  - `scripts/check-tahoe-glass-guardrails.sh`：退出码 0（VRR 默认关、无 broad quickshell、
    保留 tahoe- namespace、无直接 BackgroundEffect/blurRegion）。
  - `bash scripts/check-submodules.sh`：退出码 0。
  - `niri/target/release/niri validate -c config/niri/tahoe-phase0.kdl`：退出码 0，
    `config is valid`。
- **运行时 smoke**：当前 Tahoe 会话的 quickshell 实例（PID 469218）已热重载本阶段改动；
  Quickshell IPC（`quickshell ipc --pid 469218 call tahoe openSettings/openAbout/
  openSystemHealth/closeSettings`）经 `openSettingsPanel` 路由，`niri msg layers` 在打开时
  出现 `tahoe-settings` overlay、`closeSettings` 后清除；systemd --user 单元日志无 QML
  load failure / warning（早期一条 `qml6[1238309]` 的 `module "Quickshell" plugin not found`
  来自另一独立 qml6 进程，非本 quickshell 实例，与本阶段无关）。设置面板可正常打开（用户
  确认），侧栏彩色图标、色温滑块、深色模式在真机渲染正常。

## 阶段 S3：niri 配置写回基础设施（KDL 读写层 + NiriSettings service + 部署防覆盖）

目标：建机制，**不接 UI**。能精确读写 `config.kdl` 指定字段、生成合规 KDL、触发热重载、
防止 arch-update 覆盖用户改动。

建议方案：

- `tahoe-shell/services/NiriSettings.qml`：`Item { visible:false }` 根（`666c3c8`）。
  持有当前 niri 配置的可写字段的运行时镜像；`setX(v)` → 调 KDL 读写层改 config →
  `Quickshell.execDetached(["niri","msg","action","load-config-file"])` 立即生效。
  照 `Appearance.qml` 的 set→persist→apply 模式。
- KDL 读写层（位置待定：QML/JS 内一组函数，或一个小工具脚本）：能
  (a) 读取 `config.kdl` 中指定 section/字段当前值；(b) 精确写回单个字段，保留注释与格式
  （行/块级定位替换，不从零重生成）；(c) 产物 `niri validate` + guardrails 通过。
- **先做 include 合并语义实验**（见「关键技术决策 1」），决定主路径。
- `scripts/arch-update.sh` 的 `deploy_niri_config()` 增加防覆盖：覆盖前若目标 config.kdl
  与上次部署基线不同（用户改过），则备份 + 提示（或三方合并）；最小改动，不破坏现有
  submodule/部署逻辑（`1e1d1e0`/`6211e44`/`9222c60` 等 submodule 更新修复不能回退）。
- 本阶段只对 `layout`（gaps/圆角/焦点环/边框/阴影/snap-assist）做 round-trip 验证，
  作为机制冒烟；UI 接入在 S4。

注意事项：

- 原子写（临时文件+mv）+ 确保 mtime 变化，避免半写 parse error 弹窗。
- 生成物合规（VRR 默认关、无 broad quickshell、保留 tahoe- namespace）。
- service 根 Item；execDetached 调 niri msg 失败要静默降级（niri 不在时不能崩）。
- 不改 QML 用 BackgroundEffect/blurRegion（guardrails）。

验收：

- 读写层对 `layout` 各字段 round-trip 正确，注释/格式保留。
- 改 `gaps` 写回后，niri 热重载肉眼生效（间距变化）；`niri validate` + guardrails 通过。
- 模拟 `arch-update` 覆盖：用户改动被备份/保留，不静默丢失。
- 现有 `config.kdl` 未被破坏（`diff` 仅预期字段变化）。

回归检查：niri 渲染稳定（`9dae619f`/`110693a`，无超大 blur rect/溢出）、guardrails、
submodules（`1e1d1e0`/`6211e44`）、phase6 基线。

退出门槛：S3 全部验收通过后才允许进入 S4。

### 阶段 S3 验收记录（2026-06-19）

- **范围**：完成 niri 配置写回基础设施，未新增/改动设置 UI，未改
  `config/niri/tahoe-phase0.kdl`，未碰设置面板 dismiss、TahoeGlass region、现有
  `DesktopSettings`/`Appearance` 持久化路径。
- **include 合并语义实验**：用临时主配置在末尾加入 `include "override.kdl"`，被 include
  文件仅包含 `layout { gaps 23 }`；`niri/target/release/niri validate -c 临时主配置`
  退出码 0，确认跨文件重复 `layout {}` 不会触发「同文件 duplicate node」错误。结合
  `niri-config/src/lib.rs` 的源码事实（include 按出现位置解析 `ConfigPart` 并 merge 到同一
  `Config`），判断「后出现的 include 可覆盖/合并前序 layout 字段」成立；S3 主路径仍采用
  精确编辑主 `config.kdl`，include 外提留给后续长期方案。
- **KDL 读写层**：新增 `tahoe-shell/services/niri_settings_tool.py`。支持读取/写回
  `layout.gaps`、`layout.focus_ring.enabled`、`layout.border.enabled`、
  `layout.shadow.enabled/softness/spread/offset_x/offset_y`、
  `layout.snap_assist.enabled/threshold`；写回为行/块级精确替换，保留注释和原格式。
  写入采用同目录临时文件 + `fsync` + `os.replace` + `utime`，替换前对候选文件执行
  `niri validate -c`，并内置配置级 guardrails（VRR 默认关闭、无 broad quickshell
  namespace、保留 explicit `tahoe-` namespace）。
- **round-trip 验证**：在 `config/niri/tahoe-phase0.kdl` 临时副本上逐项写入上述所有 layout
  字段，再全部恢复原值；最终 `diff -u config/niri/tahoe-phase0.kdl 临时副本` 无输出，
  说明注释/格式未漂移。helper 读取当前源配置得到 gaps=16、focus-ring=false、
  border=false、shadow=true(softness=36/spread=4/offset 0,10)、snap-assist=true(threshold=16)。
- **NiriSettings service**：新增 `tahoe-shell/services/NiriSettings.qml`，根为
  `Item { visible: false }`（符合 `666c3c8` 护栏）。service 持有 layout 运行时镜像，
  `setX(v)` 调 helper 写 `config.kdl`，写入成功后执行
  `niri msg action load-config-file --path "$config"`，失败静默降级且不崩 shell。`shell.qml`
  仅注册 `NiriSettings { id: niriSettings }`，没有接入任何 UI。
- **热重载 smoke**：当前 Tahoe 会话中 `niri msg --json outputs` 可用；对真实
  `~/.config/niri/tahoe/config.kdl` 用 helper 将 `layout.gaps` 从 16 临时写为 18，
  `niri msg action load-config-file --path ~/.config/niri/tahoe/config.kdl` 退出码 0；
  随后通过 trap 恢复为 16，最终 helper 读取 live config 确认为 16。写入过程中未产生
  niri validate 错误，未保留临时配置改动。
- **部署防覆盖**：`scripts/arch-update.sh` 新增
  `NIRI_CONFIG_DEPLOY_BASELINE=$TAHOE_STATE_DIR/niri-config-deployed-baseline.kdl` 与
  `FORCE_NIRI_CONFIG_DEPLOY=false`。若目标 `config.kdl` 与上次部署基线不同，默认先备份为
  `config.kdl.user-YYYYMMDD-HHMMSS.bak`，再把新模板写到 `config.kdl.new`，并保留 live
  config 不覆盖；只有显式 `FORCE_NIRI_CONFIG_DEPLOY=true` 才会在备份后覆盖。临时目录模拟：
  baseline 为 gaps=16、目标被用户改为 gaps=18 后调用 `deploy_niri_config()`，结果
  backup_count=1、`config.kdl.new` 存在、live config 仍为 gaps=18。正常路径也已验证：
  目标未修改且 baseline 缺失时直接部署并创建 baseline，backup_count=0。
- **运行时 load smoke**：临时从仓库路径启动 `quickshell -p /home/wwt/niri/tahoe-shell`，
  `services/qmldir` 正常发现 `NiriSettings 1.0 NiriSettings.qml`，日志显示
  `NiriSettings` 类型解析成功，无 `NiriSettings` 相关 QML load failure。已结束临时
  quickshell 进程；日志中的 `font` 只读警告和 portal app-id 警告为既有运行时现象。
- **检查脚本**：
  - `python3 -m py_compile tahoe-shell/services/niri_settings_tool.py`：退出码 0。
  - `bash -n scripts/arch-update.sh`：退出码 0。
  - `/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I quickshell/build-tahoe/qml_modules tahoe-shell/services/NiriSettings.qml`：
    退出码 0。`signal-handler-parameters` 关闭仅用于 Quickshell `Process.onExited`
    的 `QProcess::ExitStatus` 元类型警告，现有 service 也会触发同类警告。
  - `niri/target/release/niri validate -c config/niri/tahoe-phase0.kdl`：退出码 0，
    `config is valid`。
  - `scripts/check-tahoe-glass-guardrails.sh`：退出码 0。
  - `bash scripts/check-submodules.sh`：退出码 0（仍打印 git submodule dry-run 用法说明，
    行为与前序阶段一致）。
- **工作区**：S3 预期改动为 `scripts/arch-update.sh`、`tahoe-shell/shell.qml`、
  新增 `tahoe-shell/services/NiriSettings.qml`、新增
  `tahoe-shell/services/niri_settings_tool.py`、本文档验收记录；既有未跟踪
  `tahoe-shell/services/__pycache__/` 未清理、未覆盖。
- 本阶段未进入 S4，未新增 niri 设置页，未碰 binds/MRU/task-switcher，未生成
  `variable-refresh-rate`、broad `namespace="^quickshell"` 或直接 QML
  `BackgroundEffect`/`blurRegion`。

## 阶段 S4：niri 设置 UI —— MVP（第一批域）

目标：把 S3 机制接进设置面板，新增 niri 设置分类，**第一批范围默认为「布局与窗口外观」**
（gaps/窗口圆角/焦点环/边框/阴影/snap-assist）。其余域（键位/玻璃材质/输入·显示/动画）
列入 S5，**S4 启动前由用户确认/调整第一批范围**。

建议方案：

- 用 S1/S2 控件新增 niri 设置页（或在「外观」页扩区），每个控件改值即走 S3 setX→写回→热重载。
- 滑块（gaps、圆角、阴影 softness/spread）、开关（焦点环 on/off、边框 on/off、snap-assist on/off）、
  数值字段（snap 阈值）。
- 改动落盘到 config.kdl，重启 niri 后值仍正确。

注意事项：

- 不覆盖 niri MRU binds（`441b637`）；本批不碰 binds。
- 每项改动后 niri validate + guardrails 通过。
- 不破坏现有外观页（深浅色/夜览/色温，走 Appearance service，与 niri config 无关，共存）。

验收：

- 改 gaps/圆角/焦点环/阴影/snap 立即生效；重启 niri 后持久。
- guardrails / niri validate / qmllint 通过；现有设置面板所有功能无回归。

回归检查：`441b637`、guardrails、phase6 基线、S1/S2 外观无回退。

退出门槛：S4 全部验收通过后才允许进入 S5。

### 阶段 S4 验收记录（2026-06-19）

- **范围**：把 S3 的 NiriSettings 机制接进设置面板，新增 niri「布局与窗口」分类
  （第一批域：gaps/焦点环/边框/阴影/snap 助手）。未碰 binds/MRU/task-switcher
  （`441b637`）、未改 dismiss、未改 TahoeGlass region、未改 niri 源配置、未改既有
  DesktopSettings/Appearance 持久化路径。工作区 S4 改动仅限设置面板（6 改 + 1 新增）。
- **NiriSettings service 增强**（`services/NiriSettings.qml`，S3 产物上做最小改动）：
  - `setX` 改为**乐观更新**：先 `root.<prop> = next` 再 `writeField`，使滑块拖动时
    填充条立即跟手，不必等写回 round-trip。
  - 写入**串行化**：新增 `property var pending: ({})` per-field 队列。`writeField`
    把字段最新值记入 pending；`flushPending` 每次取队首一个字段、`startWriter` 写入；
    `writer.onExited` 成功后 `applyNiriConfig()`（热重载）再 `flushPending()` 续写下
    一个，失败则清空 pending 并 `refresh()` 回退真相。这样快速拖动滑块、以及同一
    写回窗口内交叉改多个字段，最终都收敛到盘上。
  - 属性默认值对齐 `config.kdl` 真值（gaps=16/focus-ring=off/border=off/shadow=on
    softness=36 spread=4 offset 0,10/snap=on threshold=16），消除首帧错值闪烁。
  - service 根仍为 `Item { visible: false }`（`666c3c8`）；execDetached 失败静默降级。
- **新增 NiriPage**（`components/settings/pages/NiriPage.qml`）：用 S1/S2 控件库搭
  四个 section——
  - 布局间距：gaps 滑块（0..64 px，`value=gaps/64`）。
  - 窗口装饰：焦点环开关、边框开关（`TahoeListRow` checkable）。
  - 窗口阴影：启用开关 + 柔和度（0..100）、扩散（0..40）、水平/垂直偏移（-40..40，
    带正负号）四个滑块。
  - Snap 助手：启用开关 + 吸附阈值滑块（0..80 px）。
  每个控件读 service 镜像、`onUserSet`/`onToggled` 走 `setX`。顶部状态行在
  服务缺失/读取中/写错误时提示，控件在 `loaded` 前禁用。所有 iconCode 经
  `MaterialIconsRound.ttf` cmap 核验存在（dashboard e871、space_bar e256、
  border_outer e873、crop_square e8c4、layers e53b、blur_on e3a4、gradient e3aa、
  compare_arrows e915、height e7c9、magnet e8f4、aspect_ratio e859）。
- **接进面板路由与侧栏**：
  - `SettingsPanel.qml`：新增 `property var niriSettingsService`；`pageIndex("niri")=8`；
    `pageTitle`/`pageSubtitle` 加 niri 项；`StackLayout` 末尾挂 `Pages.NiriPage`。
  - `SettingsSidebar.qml`：「外观」后新增「布局与窗口」按钮（dashboard 图标 +
    `categoryColor("niri")`），`active`/`onActivated` 走 `selectedPage === "niri"`。
  - `OverviewPage.qml`：Dock tile 后新增 niri summary tile（显示当前 gaps，点击跳转）。
  - `SettingsTheme.js`：`categoryColor` 增 `case "niri": return "#30b0c8"`（teal，
    与既有 indigo/red/coral/blue/orange/green/gray 不撞色）。
  - `shell.qml`：`SettingsPanel` 注入 `niriSettingsService: niriSettings`（service
    本体在 `shell.qml` 注册，S3 已就位）。
- **「窗口圆角」说明**：S4 第一批范围文档提及「窗口圆角」，但 niri `layout` 不暴露
  窗口圆角字段（focus-ring/border 仅为描边，无 radius），S3 helper 也无对应字段，
  故本批不提供该控件——避免发明无后端的开关。本批控件严格映射到 S3 已验证的字段。
- **回归检查**：
  - 未碰 dismiss（自身全屏 MouseArea，`dc5bef9`）；未碰 TahoeGlass region 坐标/几何
    （`b7b8e5a`/`0704ea4`，无 spring）；未碰 `shell.qml` 挂载点之外；未新增 service
    根类型（`666c3c8`）；未用 `BackgroundEffect`/`blurRegion`；未生成
    `variable-refresh-rate` 或 broad `namespace="^quickshell"`；未碰 binds（`441b637`）。
  - 现有外观页（深浅色/夜览/色温，走 Appearance service）与 niri config 写回共存，
    互不影响。
- **检查脚本**：
  - `python3 -m py_compile tahoe-shell/services/niri_settings_tool.py`：退出码 0
    （helper 本阶段未改，仅复测）。
  - `/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I quickshell/build-tahoe/qml_modules`
    （settings 全树 + `SettingsPanel.qml` + `services/NiriSettings.qml`）：退出码 0，
    仅 14 条 S1 基线已记录为可接受的 Quickshell/TahoeGlass 自定义类型噪声
    （`PanelWindow` uncreatable、`TahoeGlassRegion` incomplete、region id unqualified），
    无任何 NiriPage/NiriSettings/niriSettingsService 相关告警。
  - `niri/target/release/niri validate -c config/niri/tahoe-phase0.kdl`：退出码 0，
    `config is valid`。
  - `scripts/check-tahoe-glass-guardrails.sh`：退出码 0（VRR 默认关、无 broad
    quickshell、保留 tahoe- namespace、无直接 BackgroundEffect/blurRegion）。
  - `bash scripts/check-submodules.sh`：退出码 0。
- **写回路径 round-trip**（在 `config.kdl` 副本上，不碰线上配置）：逐字段写入全部
  10 个 layout 字段（gaps/focus-ring/border/shadow enabled+softness+spread+offset_x/
  offset_y/snap enabled+threshold）再全部恢复，`diff -u 源 副本` 无输出（注释/格式零
  漂移），恢复后副本 `niri validate` 通过。helper 读取源配置得到 gaps=16、focus-ring=
  off、border=off、shadow=on(softness=36/spread=4/offset 0,10)、snap=on(threshold=16)，
  与 service 默认值一致。
- **运行时 smoke**：从仓库路径临时启动 `quickshell -p /home/wwt/niri/tahoe-shell`，
  `XDG_CONFIG_HOME` 指向只含 config 副本的临时目录（隔离，不写线上 config/state）。
  实例正常加载、存活；日志无任何 NiriPage/NiriSettings/niriSettingsService/
  SettingsSidebar/OverviewPage/SettingsTheme 相关 load 错误，无任何 QML load failure。
  Quickshell IPC（`--pid` 路由）`openSettings` 后 `niri msg layers` 出现 1 个
  `tahoe-settings` overlay、`closeSettings` 后归 0（dismiss 路由无回归）。临时实例已
  经 trap 清理。线上会话（`~/.config/quickshell/tahoe`）全程未受影响。
  - 说明：现有 IPC 仅 `openSettings`(→概览)/`openAbout`/`openSystemHealth`/
    `closeSettings`，无按页打开的 IPC，故 niri 页通过侧栏「布局与窗口」按钮与概览
    tile 进入（UI 可达）；NiriPage 作为 `StackLayout` 子项在面板实例化时即创建，
    无 load 错误即证明其绑定在运行时成立。
- **工作区**：S4 预期改动为 `SettingsPanel.qml`、`SettingsSidebar.qml`、
  `SettingsTheme.js`、`pages/OverviewPage.qml`、`shell.qml`、新增
  `pages/NiriPage.qml`、本文档验收记录。S3 的改动（`scripts/arch-update.sh`、
  `services/NiriSettings.qml`、`services/niri_settings_tool.py`、本文档 S3 记录）
  仍在工作区未提交；既有未跟踪 `tahoe-shell/services/__pycache__/` 未清理、未覆盖。
- 本阶段未进入 S5，未碰 binds/MRU/task-switcher，未做玻璃/输入·显示/动画/键位域，
  未生成违规 KDL。

## 阶段 S5：niri 设置扩展 + Search 集成 + 收敛

目标：补其余 niri 域 + Spotlight 集成 + 真机收敛。按优先级分小步，每步独立验收。

建议范围（每步独立提交，顺序可按用户优先级调整）：

1. **玻璃与材质**：tahoe-glass 各 material（panel/pill/dock/menu/toast/backdrop）的
   edge-highlight/refraction/inner-shadow/chromatic/lens-depth + blur passes/offset/noise/saturation。
   （fork 专有，只走 config，无 IPC。）
2. **输入与显示**：touchpad tap/natural-scroll、keyboard repeat_rate/repeat_delay、
   output scale（输出分辨率/VRR 谨慎——VRR 默认必须关，guardrails）。
3. **动画**：各动作 spring damping-ratio/stiffness/epsilon、duration/curve。
4. **键盘快捷键（最后做）**：`binds {}` 查看 + 受限改键。**最高风险**：必须保证 binds 块整体
   完整、不覆盖 MRU/task-switcher（`441b637`）、不生成违规配置。
5. **Spotlight 集成**：`Search.qml` 增加 niri 设置项，`internalPage` 指向新页，
   经 `openSettingsRequested` → `shell.openSettingsPanel` 打开。
6. **彩色图标升级**：自绘 SVG 渐变彩色分类图标（替换 S2 的 Material+方块方案），真机收敛。

注意事项：

- 键位改键必须保留 task switcher IPC binds（`Mod+Ctrl+Tab` 等 spawn-sh 调 ipc）不被覆盖。
- 玻璃/动画改动是热重载，但极端参数可能触发渲染问题——对照 `9dae619f`/`110693a` 不引入超大 blur。
- VRR 相关项默认关、且不得生成会触发 guardrails 的全局 VRR 配置。

验收（逐步）：

- 各域可改、热重载生效、重启持久；guardrails / niri validate 持续通过。
- Spotlight 搜 niri 设置能跳转；深色模式下全部可读。
- 真机 + VM（useSpring=false）均无图标消失/崩溃。

回归检查：全部护栏（A–E）+ 所有前序阶段基线。

### 实施决策（2026-06-20 确认）

- **页面结构**：niri 中心页（hub）+ 子页。侧栏保持 9 项不变；「布局与窗口」入口打开 niri
  hub，hub 内 summary tile 跳转各域子页（布局/玻璃材质/输入与显示/动画/快捷键）。
- **binds（子步 4）**：只读查看 + 保护标注（task-switcher/MRU IPC binds 标为受保护）+「在编辑器
  打开 config.kdl」按钮；**不提供 GUI 改键**，规避 `441b637` 与 replace-on-conflict 风险。
- **输入与显示（子步 2）**：仅键盘（repeat-rate/repeat-delay/numlock）+ 触摸板
  （tap/natural-scroll/dwt/accel-speed）；output scale 只读，绝不写 `variable-refresh-rate`。
- 子步拆为 S5.0（hub 骨架）→ S5.1 玻璃 → S5.2 输入 → S5.3 动画 → S5.4 快捷键 → S5.5 Spotlight →
  S5.6 图标 + 最终收敛，每步独立提交 + 验收。

### 阶段 S5.0 验收记录（2026-06-20）

- **范围**：把 niri 设置拆为 hub + 子页骨架，行为保持。未改 niri 源配置、未改 service/helper、
  未碰 dismiss/TahoeGlass region/挂载点。工作区 S5.0 改动为 3 改 + 1 新增。
- **NiriLayoutPage.qml（新增）**：把原 `NiriPage.qml` 的 4 个 layout section（布局间距/窗口装饰/
  窗口阴影/Snap 助手）原样搬入，控件与 `setX` 调用零变化；仅更新文件头注释说明来源。
  iconCode 经 cp 从原文件逐字保留（space_bar/border_outer/crop_square/layers/blur_on/gradient/compare_arrows/height/magnet/aspect_ratio），与 S4 基线一致。
- **NiriPage.qml → hub**：改为 Flickable + 状态行 + 说明文 + GridLayout + 单个 summary tile
  「布局与窗口」→ `selectedPage = "niri-layout"`（其余 4 tile 在各自子步追加）。tile 读 service 镜像
  显示当前 gaps。
- **SettingsPanel.qml**：`pageIndex` 增 `niri-layout=9`（"niri" hub 仍 = 8）；`pageTitle/pageSubtitle`
  增 niri-layout 项（标题「布局与窗口」、副标题同 niri）；StackLayout 在 `NiriPage` 之后按 index
  顺序挂 `Pages.NiriLayoutPage`。
- **SettingsSidebar.qml**：「布局与窗口」`active` 由 `=== "niri"` 扩展为
  `=== "niri" || indexOf("niri-") === 0`，使子页时该侧栏项仍高亮；点击仍回 hub。
- **回归检查**：未碰 dismiss（自身全屏 MouseArea，`dc5bef9`）；未碰 TahoeGlass region 坐标/几何
  （`b7b8e5a`/`0704ea4`，无 spring）；未碰 `shell.qml:705-716` 挂载点；未新增 service 根类型
  （`666c3c8`）；未用 `BackgroundEffect`/`blurRegion`；未生成 `variable-refresh-rate` 或 broad
  `namespace="^quickshell"`；未碰 binds（`441b637`）。
- **检查脚本**：
  - `python3 -m py_compile services/niri_settings_tool.py`：退出码 0（本步未改 helper，复测）。
  - `/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I quickshell/build-tahoe/qml_modules`
    （settings 全树 + `SettingsPanel.qml` + `services/NiriSettings.qml`）：退出码 0，无新增告警。
  - `scripts/check-tahoe-glass-guardrails.sh`：退出码 0。
  - `bash scripts/check-submodules.sh`：退出码 0。
  - `niri/target/release/niri validate -c config/niri/tahoe-phase0.kdl`：退出码 0，`config is valid`。
- **运行时 smoke**：从仓库路径临时启动 `quickshell -p /home/wwt/niri/tahoe-shell`，
  `XDG_CONFIG_HOME` 指向只含 config 副本的临时目录（隔离，不写线上 config/state）。实例 4s 后存活、
  无 QML load failure；日志仅见既有运行时现象（`shell.qml:322` font 只读警告、magnification/
  bounceOffset interceptor 警告、通知服务已被线上会话占用），无 NiriPage/NiriLayoutPage/
  SettingsPanel/SettingsSidebar 相关错误。临时实例已 trap 清理；线上会话（PID 1291，运行
  `~/.config/quickshell/tahoe` 副本）全程未受影响。
- 本阶段未进入 S5.1，未新增配置域，未碰 binds/MRU/task-switcher，未生成违规 KDL。

### 阶段 S5.1 验收记录（2026-06-20）

- **范围**：新增 niri「玻璃材质」域（tahoe-glass material 各字段 + 全局 blur），经 hub 接入
  设置面板。未碰 dismiss/TahoeGlass region/挂载点/binds。工作区 S5.1 改动为 5 改 + 2 新增。
- **helper（`niri_settings_tool.py`）**：新增 `read_glass_text`/`read_blur_text`（缺省容错：
  block 缺失返回 niri 默认）、string-arg `find_material_block`/`create_material_block`、
  `set_leaf_value`（写前比较：值未变则保留原始 token，避免 0.10→0.1 归一化漂移）、`format_float`
  （保留小数点）、`set_blur_enabled`（on/off flag 写法）、统一分发器 `update_field`（layout/glass/blur）。
  `read`/`write` payload 增 `glass`/`blur`。glass 字段 clamp 与 schema `FloatOrInt<0,1000>` 一致；
  blur passes∈[0,255] offset∈[0,100] noise/saturation∈[0,1000]。
- **round-trip（在 config 副本上）**：
  - TEST A（no-op 写回每字段当前值）：byte-identical，证明 token 保留。
  - TEST B（全字段改写为测试值）：`niri validate` 通过、读回值正确。
  - TEST C（改后恢复原值）：仅 2 行浮点 token 归一化（0.10→0.1、0.40→0.4，仅限被实际改动过的行），
    零结构/注释漂移，恢复后 `niri validate` 通过。
- **CLI smoke**：`read` 返回 layout+glass+blur；`write glass.panel.edge_highlight=0.55` 与
  `write layout.gaps=20`（回归：layout 仍经 update_field）均 ok，`diff` 仅 2 行预期变化，validate 通过。
- **service（`NiriSettings.qml`）**：`glassMaterials` 嵌套对象属性（6 material × 5 field，默认对齐
  config 真值）+ blur 5 标量；`setGlassField(m,f,v)`（不可变对象重赋 + `Object()` 浅拷 + writeField）、
  `setBlurEnabled/Passes/Offset/Noise/Saturation`（乐观更新 + writeField）、`clampReal`（float 不取整）、
  `applyGlass`/`applyBlur`；`handleReadOutput`/`handleWriteOutput` 调用 applyGlass/applyBlur。
- **UI（`NiriGlassPage.qml` + 新控件 `TahoeSegmented.qml`）**：「全局模糊」section（启用开关 +
  passes/offset/noise/saturation 滑块）+「材质」section（6 选 1 分段选择器 + edge-highlight[0,2]/
  refraction[0,0.12]/inner-shadow[0,0.5]/chromatic[0,0.1]/lens-depth[0,0.3] 五滑块）。每控件读
  service 镜像、`onUserSet`/`onToggled` 走 setX。**不暴露 xray**（保持 false，护栏 `74b384a`）。
  所有 iconCode 经 MaterialIconsRound.ttf cmap 核验存在（blur_on/blur_circular/filter_alt/tune/
  scatter_plot/palette/flare/3d_rotation/invert_colors/auto_awesome/lens_blur）。
- **路由**：`SettingsPanel.qml` `pageIndex` 增 `niri-glass=10` + pageTitle「玻璃材质」+ pageSubtitle +
  StackLayout 挂 `NiriGlassPage`；`NiriPage.qml` hub 增「玻璃材质」tile→niri-glass；
  `SettingsTheme.js` `categoryColor` 增 `niri-glass` indigo `#5e5ce6`。
- **回归检查**：未碰 dismiss（`dc5bef9`）；未碰 TahoeGlass region 坐标/几何（`b7b8e5a`/`0704ea4`，
  无 spring）；未碰 `shell.qml:705-716` 挂载点；未新增 service 根类型（`666c3c8`，NiriSettings 仍 Item）；
  未用 `BackgroundEffect`/`blurRegion`；未生成 `variable-refresh-rate` 或 broad `namespace="^quickshell"`；
  未碰 binds（`441b637`）；`useSpring` 未被新动画依赖（TahoeSegmented 无 spring）。
- **检查脚本**：
  - `python3 -m py_compile services/niri_settings_tool.py`：退出码 0。
  - `/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I quickshell/build-tahoe/qml_modules`
    （settings 全树 + `SettingsPanel.qml` + `services/NiriSettings.qml`）：退出码 0；新文件
    `TahoeSegmented.qml`/`NiriGlassPage.qml`/`NiriSettings.qml` 零告警（`index` 未限定告警已修为
    `segment.index`），仅余 S1 基线已记录的 Quickshell/TahoeGlass 自定义类型噪声。
  - `scripts/check-tahoe-glass-guardrails.sh`：退出码 0。
  - `bash scripts/check-submodules.sh`：退出码 0。
  - `niri/target/release/niri validate -c config/niri/tahoe-phase0.kdl`：退出码 0，`config is valid`。
- **运行时 smoke**：从仓库路径临时启动 `quickshell -p /home/wwt/niri/tahoe-shell`，`XDG_CONFIG_HOME`
  指向只含 config 副本的临时目录（隔离）。实例 4s 后存活、无 QML load failure，无 NiriGlassPage/
  TahoeSegmented/NiriSettings/glassMaterials/blur 相关错误。临时实例已 trap 清理；线上会话未受影响。
- 本阶段未进入 S5.2，未碰 binds/MRU/task-switcher，未生成违规 KDL。

### 阶段 S5.2 验收记录（2026-06-20）

- **范围**：新增 niri「输入与显示」域——键盘 repeat-rate/repeat-delay/numlock + 触摸板
  tap/natural-scroll/dwt/accel-speed（可写），output scale 只读显示。未碰 dismiss/TahoeGlass
  region/挂载点/binds。工作区 S5.2 改动为 5 改 + 1 新增。
- **helper**：新增 `read_input_text`（keyboard/touchpad 默认值对齐 niri schema：repeat-rate 25/
  repeat-delay 600/numlock off/tap off/natural-scroll off/dwt off/accel-speed 0）、
  `flag_state_in_block`/`set_flag_in_block`（bare flag 读写：on 写裸 `name`、off 写 `name false`、
  值未变则保留原 token）、`read_output_text`（首个 `output "name" {}` 的 scale，只读）。
  `update_field` 增 `input.keyboard.repeat_rate(0..255)/repeat_delay(0..65535)/numlock`、
  `input.touchpad.tap/natural_scroll/dwt/accel_speed(clamp[-1,1])`。`read`/`write` payload 增 `input`。
- **round-trip（在 config 副本上）**：
  - 读得 keyboard{repeat_rate 25, repeat_delay 600, numlock True}、touchpad{tap True,
    natural_scroll True, dwt False, accel_speed 0}、output{eDP-2, scale 1.25}。
  - TEST A（对已存在的 bare flag numlock/tap/natural-scroll 写回当前值）：byte-identical。
  - TEST B（已存在 bare flag off→on 往返）：byte-identical（on 恒写裸 token）。
  - TEST C（写入缺失的 repeat-rate 30/repeat-delay 500/dwt on/accel-speed 0.5）：`niri validate`
    通过、读回值正确。
  - TEST D（accel_speed 边界 -1/0/1）：均 `niri validate` 通过。
  - TEST E（output 只读解析）：name=eDP-2、scale=1.25、present=True。
- **service（`NiriSettings.qml`）**：键盘/触摸板标量属性 + output 只读属性（outputName/outputScale/
  outputPresent）；setKeyboardRepeatRate/Delay/Numlock、setTouchpadTap/NaturalScroll/Dwt/AccelSpeed
  （乐观更新 + writeField）；`applyInput`（input.output 走 clampReal 0.1..10）；handleRead/WriteOutput
  调用 applyInput。
- **UI（`NiriInputPage.qml`）**：键盘 section（repeat-rate 0..100/秒、repeat-delay 0..1000 ms 滑块 +
  numlock 开关）+ 触摸板 section（tap/natural-scroll/dwt 开关 + accel-speed 滑块，-1..1 归一
  (v*2-1)，带正负号）+ 输出只读 section（显示 outputName + scale，注明「分辨率/缩放/VRR 由 config.kdl
  管理，VRR 保持关闭」，无控件）。所有 iconCode 经 cmap 核验（repeat/repeat_one/speed/lock/
  touch_app/swipe/keyboard_hide/monitor）。
- **路由**：`SettingsPanel.qml` `pageIndex` 增 `niri-input=11` + pageTitle「输入与显示」+ pageSubtitle +
  StackLayout 挂 `NiriInputPage`；`NiriPage.qml` hub 增「输入与显示」tile→niri-input；
  `SettingsTheme.js` `categoryColor` 增 `niri-input` blue `#0a84ff`。
- **回归检查**：未碰 dismiss（`dc5bef9`）；未碰 TahoeGlass region 坐标/几何（`b7b8e5a`/`0704ea4`）；
  未碰 `shell.qml:705-716` 挂载点；未新增 service 根类型（`666c3c8`）；未用 `BackgroundEffect`/`blurRegion`；
  未生成 `variable-refresh-rate`（输出只读，GUI 永不写 VRR）或 broad `namespace="^quickshell"`；
  未碰 binds（`441b637`）；`useSpring` 未被新动画依赖。
- **检查脚本**：`py_compile` 0；`qmllint`（settings 全树 + SettingsPanel + NiriSettings）退出 0，
  新文件零告警；guardrails 0；submodules 0；`niri validate` 0。
- **运行时 smoke**：临时 `quickshell -p tahoe-shell`（隔离 XDG_CONFIG_HOME + config 副本）4s 存活、
  无 QML load failure，无 NiriInputPage/input 相关错误；临时实例已 trap 清理；线上会话未受影响。
- 本阶段未进入 S5.3，未碰 binds/MRU/task-switcher，未生成违规 KDL。

### 阶段 S5.3 验收记录（2026-06-20）

- **范围**：新增 niri「动画」域——4 个 spring 动作（workspace-switch/window-movement/
  window-resize/overview-open-close）的 damping-ratio/stiffness/epsilon。未碰 dismiss/TahoeGlass
  region/挂载点/binds。工作区 S5.3 改动为 5 改 + 1 新增。
- **helper**：新增 `read_animations_text`（仅读上述 4 个 spring 动作；缺省 1.0/1000/0.0001）、
  `parse_spring_line`/`format_spring`、`set_anim_spring`（整行重写
  `spring damping-ratio=X stiffness=Y epsilon=Z`，值未变则跳过保留原 token；动作块无 spring 行则
  拒绝改写，避免给 easing/shader 动作凭空造 spring）。`update_field` 增
  `animations.<action>.damping_ratio[0.1,10]/stiffness[1,1e5]/epsilon[1e-5,0.1]`。`read`/`write`
  payload 增 `animations`。
- **round-trip（在 config 副本上）**：读得 workspace_switch{1.0,780,0.0001}、
  window_movement{0.86,620,0.001}、window_resize{0.96,700,0.0005}、overview_open_close{0.95,760,0.0005}。
  - TEST A（no-op 写回每参数当前值）：byte-identical（format_float/format_number 复现源格式）。
  - TEST B（改写各参数）：`niri validate` 通过、读回值正确。
  - TEST C（改后恢复原值）：byte-identical（整行重写格式与源一致）。
  - TEST D（clamp 边界 damping 0.1/10、epsilon 1e-5/0.1、stiffness 1）：均 `niri validate` 通过。
- **service（`NiriSettings.qml`）**：`animSprings` 嵌套对象（4 动作 × 3 参，默认对齐 config 真值）；
  `setAnimParam(action,param,value)`（不可变对象重赋 + writeField）；`applyAnimations`；
  handleRead/WriteOutput 调用 applyAnimations。**window-open/close 不暴露**（custom-shader，不写）。
- **UI（`NiriAnimationsPage.qml`）**：每个 spring 动作一个 TahoeSection + 3 滑块
  （damping-ratio[0.1,10]、stiffness[1,1000]、epsilon[1e-5,0.1]，各自归一 0..1 映射）。每控件读
  service 镜像、`onUserSet` 走 setAnimParam。底部注明「窗口打开/关闭动画使用自定义着色器，不提供修改」。
- **路由**：`SettingsPanel.qml` `pageIndex` 增 `niri-animations=12` + pageTitle「动画」+ pageSubtitle +
  StackLayout 挂 `NiriAnimationsPage`；`NiriPage.qml` hub 增「动画」tile→niri-animations（animation
  图标 e8c1，经 cmap 核验）；`SettingsTheme.js` `categoryColor` 增 `niri-animations` orange `#ff9f0a`。
- **回归检查**：未碰 dismiss（`dc5bef9`）；未碰 TahoeGlass region 坐标/几何（`b7b8e5a`/`0704ea4`）；
  未碰 `shell.qml:705-716` 挂载点；未新增 service 根类型（`666c3c8`）；未用 `BackgroundEffect`/`blurRegion`；
  未生成 `variable-refresh-rate` 或 broad `namespace="^quickshell"`；未碰 binds（`441b637`）；
  `useSpring` 未被新动画依赖。
- **检查脚本**：`py_compile` 0；`qmllint`（settings 全树 + SettingsPanel + NiriSettings）退出 0，新文件零告警；
  guardrails 0；submodules 0；`niri validate` 0。
- **运行时 smoke**：临时 `quickshell -p tahoe-shell`（隔离 XDG_CONFIG_HOME + config 副本）4s 存活、
  无 QML load failure，无 NiriAnimationsPage/animSprings 相关错误；临时实例已 trap 清理；线上会话未受影响。
- 本阶段未进入 S5.4，未碰 binds/MRU/task-switcher，未生成违规 KDL。

### 阶段 S5.4 验收记录（2026-06-20）

- **范围**：新增 niri「快捷键」域——binds 只读查看器，标注受保护的 task-switcher IPC binds，
  提供「在编辑器打开 config.kdl」。**GUI 永不写 binds**（最高风险项按用户决策降为只读）。
  未碰 dismiss/TahoeGlass region/挂载点。工作区 S5.4 改动为 5 改 + 1 新增。
- **helper（`niri_settings_tool.py`）**：新增 `read_binds_text`（枚举 `binds{}` 的 depth-1 子节点，
  逐节点提取 combo（节点名）/首个 action token/完整 raw 文本，单行与多行 block 均处理；标记
  `protected`：raw 含 `cycleTaskSwitcher`/`toggleWindowOverview`/`openWindowOverview`，即 task-switcher
  IPC binds，护栏 `441b637`）。**只读，update_field 无 binds 写分支**。`read`/`write` payload 增 `binds`。
- **binds reader smoke**：读得 127 条 binds；protected 恰为 3 条（Mod+Ctrl+Tab、Mod+Ctrl+Shift+Tab、
  Mod+Shift+O，均 spawn-sh 调 IPC）；单行（Mod+T → spawn）与多行（Mod+Ctrl+Tab → spawn-sh）action 解析正确。
- **service（`NiriSettings.qml`）**：`bindsList` 数组属性 + `applyBinds`（无 setter）；
  `openConfigInEditor()`（`Quickshell.execDetached` 调 `${EDITOR:-${VISUAL:-xdg-open}} <configPath>`）；
  handleRead/WriteOutput 调用 applyBinds。
- **UI（`NiriKeyboardPage.qml`）**：「键盘快捷键」section（说明 binds 是 replace-on-conflict 权威全集、
  此处只读、改键请编辑 config.kdl；+「在编辑器打开」TahoeButton）+「全部快捷键」section（Repeater
  over bindsList，每行 combo（等宽粗体）+ action（等宽次要色）；protected 项橙色底 + 锁图标 + 「受保护」
  徽标，说明走 IPC 勿改）。Repeater 用裸 JS 数组 `model: page.binds`（ComponentBehavior: Bound +
  required modelData），不引 ScriptModel/Quickshell 依赖。
- **路由**：`SettingsPanel.qml` `pageIndex` 增 `niri-keyboard=13` + pageTitle「快捷键」+ pageSubtitle +
  StackLayout 挂 `NiriKeyboardPage`；`NiriPage.qml` hub 增「快捷键」tile→niri-keyboard（keyboard_command_key
  e8ef，经 cmap 核验）；`SettingsTheme.js` `categoryColor` 增 `niri-keyboard` gray `#8e8e93`。
- **回归检查**：未碰 dismiss（`dc5bef9`）；未碰 TahoeGlass region 坐标/几何（`b7b8e5a`/`0704ea4`）；
  未碰 `shell.qml:705-716` 挂载点；未新增 service 根类型（`666c3c8`）；未用 `BackgroundEffect`/`blurRegion`；
  未生成 `variable-refresh-rate` 或 broad `namespace="^quickshell"`；**未写 binds（`441b637`，只读）**；
  `useSpring` 未被新动画依赖。
- **检查脚本**：`py_compile` 0；`qmllint`（settings 全树 + SettingsPanel + NiriSettings）退出 0，新文件零告警；
  guardrails 0；submodules 0；`niri validate` 0。
- **运行时 smoke**：临时 `quickshell -p tahoe-shell`（隔离 XDG_CONFIG_HOME + config 副本）6s 存活、无 QML
  load failure，无 NiriKeyboardPage/bindsList 相关错误。说明：首次 smoke 命中一次**非确定性**崩溃
  （SIGABRT，backtrace 全在 Qt 的 `IconImageProvider::requestPixmap`→`QPlatformPixmap::fromFile`→
  `__cxa_pure_virtual`，本机 NVIDIA+AMD 双 GPU 下的图标像素加载竞态，栈中无任何本阶段 QML 帧），
  随后连续 3 次 smoke（5s/5s/6s）均存活且无 load error，确认为既有 flaky 现象、与本阶段无关。
  临时实例已 trap 清理；线上会话未受影响。
- 本阶段未进入 S5.5，未写 binds/MRU/task-switcher，未生成违规 KDL。

## 停止条件

- S0–S5 全部验收通过；设置面板外观对齐 macOS System Settings、深色模式可用、niri 主要配置域
  可在 GUI 改且改了就生效、重启持久。
- `check-tahoe-glass-guardrails.sh`、`check-submodules.sh`、`niri validate`、`qmllint` 全绿。
- 真机与 VM 双环境 smoke 通过，无本文件「Git Log 回归护栏」列出的任何回归。
