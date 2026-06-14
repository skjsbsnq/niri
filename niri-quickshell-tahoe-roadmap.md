# niri + Quickshell Tahoe 改造路线图

日期：2026-06-14

## 来源文档

本路线图整理自同目录下两个文档：

- `niri-quickshell-tahoe-research.md`
- `niri-quickshell-tahoe-handoff.md`

这两个文档分别提供了技术研究结论、源码地图、阶段优先级、交接状态和验收标准。本文件只做任务拆分和执行顺序整理，方便后续按阶段推进。

## 总目标

把 `niri + Quickshell` 改造成接近 macOS 26 Tahoe / Liquid Glass 的 Wayland 桌面体验。

核心分工：

- niri fork 负责 compositor 级能力：窗口状态、浮动/堆叠、最小化/恢复、snap assist、窗口动画、blur/glass shader、IPC 和 Wayland protocol 状态。
- Quickshell shell 负责外壳 UI：顶栏、Dock、控制中心、Launchpad、通知中心、窗口列表、工作区 UI。
- `macOS-26-Tahoe-for-the-Web-main/` 只作为素材和交互参考：图标、壁纸、视觉参数、动画节奏、Dock magnification、snap preview 行为等。

## 总体原则

- 先做最小闭环，再追求拟真。
- 开发和阶段验证优先放在当前 Windows 工作区 + Hyper-V Arch Linux VM 中完成。
- 全部阶段完成前不把真机作为日常开发环境；真机只用于最后的完整体验验收和性能确认。
- Hyper-V 的图形栈、虚拟 GPU、DRM/KMS 行为不一定等同真机。若 niri、blur、shader 或动画在 Hyper-V 中异常，先记录为环境风险，不立即推翻实现方向。
- 短期不 fork Quickshell 核心，只写独立 `tahoe-shell/` QML 配置。
- niri 是必须 fork 的部分，因为真正的最小化、恢复、snap preview、堆叠桌面行为和 Liquid Glass shader 属于 compositor 能力。
- 不直接把 Web 项目的 HTML/CSS/JS 塞进 niri 或 Quickshell。
- 不优先做 GNOME/KDE fork、全局菜单栏、锁屏、登录管理器、完整服务端窗口装饰。

## 环境策略

阶段开发环境：

- Windows：读源码、编辑文件、整理资源、写路线图、提交 git 并 push 到 GitHub。
- Hyper-V Arch Linux：最小 Arch 安装，只从 GitHub clone/pull 代码，并通过脚本一键安装/更新/运行。
- 真机 Linux：所有阶段完成后再使用，只做最终完整验收。

Hyper-V 阶段允许通过的内容：

- niri 是否能基本启动。
- Quickshell 是否能显示顶栏、Dock、控制中心。
- `ToplevelManager` 是否能读窗口。
- `WindowManager` 是否能读 workspace。
- IPC action 是否工作。
- minimize/restore/snap 的逻辑是否正确。
- QML UI 和大部分动画是否能跑通。

Hyper-V 阶段只做参考的内容：

- blur/glass 的最终观感。
- shader 性能。
- GPU/FPS 表现。
- 多显示器和 fractional scale 的最终可靠性。
- Genie effect 的最终流畅度。

这些项目最终以真机验收为准。

## 代码同步与安装策略

同步方式固定为 GitHub：

- Windows 是主开发环境，所有源码、配置、脚本修改都在 Windows 工作区完成。
- 修改完成后从 Windows commit 并 push 到 GitHub。
- Hyper-V Arch Linux 不手动改项目文件，只执行 clone、pull 和安装脚本。
- Hyper-V Arch Linux 中的项目状态以 GitHub 仓库为准。
- 真机最终验收时也从同一个 GitHub 仓库拉取代码，避免 Hyper-V 和真机环境使用不同版本。

建议仓库结构：

```text
repo-root/
- niri/
- quickshell/
- tahoe-shell/
- scripts/
  - arch-bootstrap.sh
  - arch-update.sh
  - run-tahoe-session.sh
  - README.md
- docs/
  - niri-quickshell-tahoe-roadmap.md
```

脚本职责：

- `scripts/arch-bootstrap.sh`：在最小 Arch Linux 上安装基础依赖和 pacman 版 niri，检查 Quickshell 是否可用，然后调用 `arch-update.sh` 做首次部署。
- `scripts/arch-update.sh`：后续开发中的唯一更新入口，负责 git pull、检测变更、重新构建、重新部署配置，并输出是否需要重启 niri/Quickshell。
- `scripts/run-tahoe-session.sh`：用于在 Hyper-V 中快速启动或调试 niri + tahoe-shell。

脚本要求：

- 可以重复执行。
- 不依赖手动复制文件。
- 不依赖阶段性的手动构建；Windows push 后，Hyper-V Arch Linux 只运行 `bash scripts/arch-update.sh`。
- 关键路径和仓库 URL 集中放在脚本顶部。
- 遇到错误立即退出。
- 每一步输出清晰日志。
- 不默认覆盖用户已有配置，除非配置目录明确属于本项目。

构建自动化规则：

- 每个阶段都按固定闭环执行：Windows 修改、commit、push；Hyper-V Arch Linux 执行 `bash scripts/arch-update.sh`；随后只做运行和验收。
- `arch-update.sh` 必须根据变更范围自动处理更新：Phase 0/1 默认只拉取和部署 shell/config；Phase 2 起通过 `BUILD_NIRI_FORK=auto` 在 niri 代码变化时构建 niri fork；`tahoe-shell/` 或 assets 变化时部署 shell/config；脚本自身变化时提示重新执行或重新 bootstrap。
- Phase 0 默认使用 pacman 安装的系统 niri 做 baseline 验证，不因为 `~/.local/bin/niri` 不存在就自动构建 niri fork。
- 阶段清单中出现“拉取最新代码”时，默认通过 `bash scripts/arch-update.sh` 完成，不再额外手动 `git pull`。
- 阶段清单中出现“重新构建”时，默认必须收敛进 `scripts/arch-update.sh`，不再单独手动运行 `cargo build`、`cmake`、`ninja` 或复制配置。
- 如果某次构建必须临时手动执行，需要把原因、命令和后续脚本补齐项记录回 roadmap，避免成为重复人工步骤。

`arch-update.sh` 最低实现规格：

- 在脚本开头集中配置 `REPO_DIR`、`NIRI_DIR`、`TAHOE_SHELL_DIR`、安装目标和配置目标路径。
- 进入仓库后记录更新前 commit，执行 `git fetch` 和 `git pull --ff-only`，再记录更新后 commit。
- 输出更新前后 commit，方便确认 Hyper-V 运行版本与 Windows 推送版本一致。
- 检测 `niri/`、`tahoe-shell/`、`scripts/`、配置文件和 assets 是否变化。
- `niri/` 变化时，在 `niri/` 内执行 Rust 构建，并把构建产物安装或链接到本项目控制的运行路径。
- 只有设置 `BUILD_NIRI_FORK=auto` 且拉取到 niri 源码变化，或显式设置 `FORCE_NIRI_BUILD=true` 时，才构建 niri fork。
- `tahoe-shell/`、配置文件或 assets 变化时，部署到 Quickshell 运行目录。
- 第一版不构建 Quickshell 核心；只有实际修改 `quickshell/` 源码时，才扩展 CMake/Ninja 构建分支。
- 兼容统一根仓库和 `niri/` 独立 Git 仓库两种形态；当前 Windows 工作区根目录不是 Git 仓库时，也能更新并构建 `niri/`。
- 构建失败时立即退出，不继续部署旧产物。
- 构建和部署成功后输出下一步：是否需要重启 niri、重启 Quickshell、或重新登录 session。
- 每次执行结束时输出简短摘要：拉取的 commit、是否构建 niri、是否部署 Tahoe shell、是否需要重启。

## Phase 0: 配置原型

阶段目标：不改源码，在 Windows + Hyper-V Arch Linux 中先验证方向是否正确。

主要产出：

- 一份 niri 配置原型。
- 一个很薄的 Quickshell 顶栏/Dock/控制中心原型。
- 在 Hyper-V 中初步确认“默认浮动 + 圆角 + 阴影 + 背景模糊”的视觉方向是否可行。

小任务：

Windows 操作：

- [x] 确认本地目录存在：`niri/`、`quickshell/`、`macOS-26-Tahoe-for-the-Web-main/`。
- [x] 确认 niri 当前使用 sparse checkout，源码目录包含 `src/`、`niri-config/`、`niri-ipc/`、`niri-visual-tests/`、`resources/`。
- [x] 创建或确认 GitHub 仓库。
- [x] 从 Windows 工作区 commit 并 push 当前文档、源码和配置。
- [x] 在仓库中新增 `scripts/` 目录。
- [x] 编写 `scripts/arch-bootstrap.sh`。
- [x] 编写 `scripts/arch-update.sh`。
- [x] 在 `scripts/arch-update.sh` 中实现更新前后 commit 输出。
- [x] 在 `scripts/arch-update.sh` 中实现 niri 变更检测和自动构建。
- [x] 在 `scripts/arch-update.sh` 中兼容统一根仓库和 `niri/` 独立 Git 仓库两种形态。
- [x] 在 `scripts/arch-update.sh` 中实现 `tahoe-shell/`、配置和 assets 自动部署。
- [x] 在 `scripts/arch-update.sh` 中实现构建失败立即退出。
- [x] 在 `scripts/arch-update.sh` 中实现执行结束摘要和重启提示。
- [x] 编写 `scripts/run-tahoe-session.sh`。
- [x] 编写 `scripts/README.md`，记录 Hyper-V 端首次 bootstrap、后续 update 和启动 session 的固定命令。
- [x] 编写或确认 `.gitattributes`，强制 `*.sh` 使用 LF 换行。
- [x] 确认 shell 脚本提交到 GitHub 时带有 executable bit，必要时执行 `git update-index --chmod=+x scripts/*.sh`。
- [x] 在 niri 配置里添加默认浮动规则：`open-floating true`。
- [x] 给浮动窗口添加圆角：`geometry-corner-radius`。
- [x] 开启圆角裁剪：`clip-to-geometry true`。
- [x] 给浮动窗口添加阴影：`shadow`。
- [x] 给浮动窗口添加基础背景效果：`background-effect`、`blur`、`noise`、`saturation`。
- [x] 建立最小 Quickshell 入口，用于显示顶栏和 Dock。
- [x] 做一个静态顶栏，不接真实状态。
- [x] 做一个静态 Dock，不接真实窗口。
- [x] 做一个静态控制中心弹层。
- [x] 从 Web 项目中观察 Dock、Control Center 的透明度、圆角、blur 参数。
- [x] 记录视觉参数候选值：圆角、阴影、透明度、blur 强度、noise、saturation。
- [x] 记录 Phase 1 需要补齐的 shell UI 组件。

Windows 本地状态：

- 已落地项目专属 niri 配置：`config/niri/tahoe-phase0.kdl`。
- 已落地 Quickshell Phase 0 原型：`tahoe-shell/shell.qml` 和 `tahoe-shell/components/`。
- 已记录视觉参数和 Phase 1 待补组件：`tahoe-shell/docs/phase0-visual-params.md`。
- 当前工作区根目录已初始化为聚合 Git 仓库；`niri/` 和 `quickshell/` 已登记为 submodule。GitHub remote 为 `https://github.com/skjsbsnq/niri`，当前 `main` 已 push 到 GitHub。

Hyper-V Arch Linux 操作：

- [x] 在 Hyper-V 中创建 Arch Linux VM。
- [x] 在 Hyper-V Arch Linux 中通过 GitHub clone 仓库。
- [ ] 在 Hyper-V Arch Linux 中执行 `bash scripts/arch-bootstrap.sh`。
- [ ] 确认 `arch-bootstrap.sh` 已通过 pacman 安装基础图形环境依赖和系统 niri。
- [x] 根据实际渠道安装 Quickshell；`arch-bootstrap.sh` 只检查 Quickshell，不构建 Quickshell 核心。
- [x] 确认 Phase 0 使用系统 niri baseline，不要求构建 niri fork。
- [x] 确认 niri 能在 Hyper-V 中启动；如果不能启动，记录具体 DRM/KMS/GPU 错误。
- [x] 确认 Quickshell 能在 Hyper-V 中启动。
- [x] 在 Hyper-V Arch Linux 中执行 `bash scripts/arch-update.sh`，确认无代码变化时不会重复做无意义构建。
- [ ] 修改 niri 任意小配置并从 Windows push 后，在 Hyper-V Arch Linux 中执行 `bash scripts/arch-update.sh`，确认脚本自动拉取并完成需要的构建或部署。
- [ ] 修改 `tahoe-shell/` 任意 QML 或 asset 并从 Windows push 后，在 Hyper-V Arch Linux 中执行 `bash scripts/arch-update.sh`，确认脚本自动拉取并部署 shell。
- [x] 确认后续修改只需要 Windows push、Arch 中运行 update 脚本。
- [x] 确认不需要在阶段验证中手动执行 `cargo build`、`cmake`、`ninja` 或复制配置。
- [ ] 检查浮动窗口是否默认显示在平铺窗口上方。
- [ ] 检查弹窗和固定尺寸窗口是否保持正确浮动行为。
- [ ] 手动验证多窗口情况下默认浮动是否可接受。

Hyper-V 当前状态：

- 已在 Hyper-V Arch 中通过 `git clone --recurse-submodules https://github.com/skjsbsnq/niri` 拉取聚合仓库和 submodule。
- 已通过 pacman 安装 Quickshell，并确认 Phase 0 不构建 Quickshell 核心。
- 已执行 `bash scripts/arch-update.sh`，成功部署 `tahoe-shell/` 到 `~/.config/quickshell/tahoe`，部署 niri 配置到 `~/.config/niri/tahoe/config.kdl`。
- 已修复 submodule detached HEAD 下 `arch-update.sh` 误执行 `git pull` 的问题：脚本现在由根仓库管理 submodule update。
- 直接在已有图形桌面终端运行 `niri --session` 会触发 TTY backend 初始化失败；已修复 `run-tahoe-session.sh`，默认 `NIRI_MODE=auto`，检测到现有 `WAYLAND_DISPLAY` 或 `DISPLAY` 时自动 nested 启动。
- 已在 Hyper-V 中成功启动 nested niri，并显示 Tahoe 顶栏和 Dock。

Windows 到 Hyper-V 同步验证：

- [x] Windows 修改并 push 配置或脚本后，在 Hyper-V Arch Linux 中执行 `bash scripts/arch-update.sh`。
- [x] 确认 Hyper-V 中运行的 niri 配置、Quickshell 原型和 Windows 仓库版本一致。

验收标准：

- [x] Hyper-V Arch Linux VM 可用于阶段开发和基础运行验证。
- [x] GitHub 仓库成为 Windows、Hyper-V、未来真机之间的唯一同步源。
- [x] Hyper-V Arch Linux 可通过脚本完成一键安装或更新。
- [x] Windows push 后，Hyper-V Arch Linux 只需要执行 `bash scripts/arch-update.sh`，不需要手动构建。
- [x] Phase 0 使用 pacman 版 niri 完成 baseline 验证，不要求构建 niri fork。
- [x] niri 能启动；如果 Hyper-V 环境阻塞 niri 启动，已记录阻塞原因和替代验证方案。
- [x] Quickshell 能启动。
- [ ] 新窗口默认以浮动方式打开。
- [ ] 浮动窗口有圆角、阴影和背景模糊。
- [x] 顶栏、Dock、控制中心基础外观可见。
- [x] 不需要修改 niri 源码。
- [x] 不需要修改 Quickshell 核心源码。
- [x] 不要求真机验收，真机留到全部阶段完成后再做。

## Phase 1: Quickshell Tahoe Shell

阶段目标：新建独立 `tahoe-shell/`，用 QML 重写 Tahoe 风格 shell UI。

主要产出：

- `tahoe-shell/` 独立目录。
- 顶栏、Dock、控制中心、Launchpad、窗口列表、工作区 UI。
- 通过 Quickshell 读取 niri 的窗口和工作区状态。

建议目录：

```text
tahoe-shell/
- shell.qml
- components/
  - TopBar.qml
  - Dock.qml
  - ControlCenter.qml
  - Launchpad.qml
  - WindowButton.qml
- services/
  - Niri.qml
  - Apps.qml
- assets/
  - icons/
  - backgrounds/
```

小任务：

Windows 操作：

- [x] 新建 `tahoe-shell/`。
- [x] 新建 `shell.qml` 作为入口。
- [x] 新建 `components/`、`services/`、`assets/` 目录。
- [x] 从 Web 项目复制或引用 `background/`。
- [x] 从 Web 项目复制或引用 `icon/dock/`。
- [x] 从 Web 项目复制或引用 `icon/Launchpad/`。
- [x] 从 Web 项目复制或引用 `icon/symbols/`。
- [x] 实现 `TopBar.qml`。
- [x] 用 `PanelWindow` 把顶栏固定到屏幕顶部。
- [x] 顶栏显示时间、基础状态区和控制中心入口。
- [x] 实现 `Dock.qml`。
- [x] 用 `PanelWindow` 把 Dock 固定到屏幕底部。
- [x] Dock 支持固定 app 图标。
- [x] Dock 支持显示当前窗口列表。
- [x] 实现 `WindowButton.qml`。
- [x] 窗口按钮显示 app icon、title 或 appId。
- [x] 接入 `ToplevelManager.toplevels`。
- [x] 点击窗口按钮调用 `activate()`。
- [x] 实现 `ControlCenter.qml`。
- [x] 控制中心支持打开和关闭。
- [x] 控制中心作为 overlay 或 top layer 面板显示。
- [x] 控制中心使用透明背景和 blur region。
- [x] 接入 `BackgroundEffect.blurRegion`。
- [x] 实现 `Launchpad.qml`。
- [x] Launchpad 显示 app grid。
- [x] Launchpad 支持打开和关闭。
- [x] 实现 `services/Apps.qml`，维护固定 app 列表和图标映射。
- [x] 实现 `services/Niri.qml`，先用 Quickshell 现有 toplevel/workspace 能力。
- [x] 已评估：不需要用 `Process` 临时执行 `niri msg --json`，现有 `ToplevelManager` 和 `WindowManager.windowsets` 已覆盖 Phase 1。
- [x] 接入 `WindowManager.windowsets` 获取 workspace。
- [x] 顶栏或 Dock 显示当前 workspace。
- [x] 清理硬编码路径，集中管理 assets 路径。

Hyper-V Arch Linux 操作：

- [x] 执行 `bash scripts/arch-update.sh`，由脚本拉取并部署最新 `tahoe-shell/`。
- [x] 在 niri session 中启动 Quickshell Tahoe shell。
- [x] 验证顶栏固定到屏幕顶部。
- [x] 验证 Dock 固定到屏幕底部。
- [x] 验证固定 app 图标显示。
- [x] 验证当前窗口列表显示。
- [x] 验证点击窗口按钮能调用 `activate()`。
- [x] 验证控制中心能打开和关闭。
- [x] 验证 Launchpad 能打开和关闭。
- [ ] 验证 `BackgroundEffect.blurRegion` 是否生效。
- [x] 验证 `ToplevelManager.toplevels` 是否能读到 niri 窗口。
- [x] 验证 `WindowManager.windowsets` 是否能读到 workspace。
- [ ] 检查多显示器下顶栏和 Dock 的位置。
- [ ] 检查 layer-shell exclusive zone 是否符合预期。

Hyper-V 截图验收记录：

- 2026-06-14 截图确认：顶栏、Dock、固定 app 图标、当前窗口列表、控制中心打开状态和 workspace 状态均可见。
- 截图发现控制中心底部内容裁切，已在 commit `847dbea` 中修复 `ControlCenter.qml` 高度和 Now Playing 区域布局；待 Hyper-V 拉取后复测。
- 截图发现桌面壁纸未显示、面板 blur 观感不明显；已新增 Quickshell `Wallpaper.qml`，并修正为 `WlrLayer.Background` + `ExclusionMode.Ignore` 以覆盖顶栏和 Dock 背后的完整屏幕区域；待 Hyper-V 拉取后复测真实 blur 是否由 compositor 生效。
- 2026-06-14 手动确认：Dock 窗口项点击 `activate()`、控制中心打开/关闭、Launchpad 打开/关闭均已通过。
- 待继续手动确认：真实 compositor blur、多显示器位置和 exclusive zone。

Windows 到 Hyper-V 同步验证：

- [ ] Windows 修改并 push `tahoe-shell/` 后，在 Hyper-V Arch Linux 中执行 `bash scripts/arch-update.sh`。
- [ ] 确认 Hyper-V 中运行的 QML、assets 和 Windows 仓库版本一致。

验收标准：

- [x] 有顶部菜单栏。
- [x] 有底部 Dock。
- [x] Dock 能显示固定 app 图标。
- [x] Dock 能显示当前窗口列表。
- [x] 点击窗口项能 activate。
- [x] 控制中心能打开和关闭。
- [x] Launchpad 能打开和关闭。
- [ ] 面板有 compositor blur。
- [x] 工作区状态能从 Quickshell 读取。
- [x] 不修改 Quickshell 核心源码。

## Phase 1.5: niri Session 集成

阶段目标：把已经通过交互验证的 Tahoe shell 接到 niri session 启动链路里，实现进入 niri 后自动可用，并为后续真机登录会话做最小闭环。

主要产出：

- niri 配置中自动启动 Tahoe Quickshell。
- 一个明确的 Tahoe niri 启动入口。
- 可选的登录管理器 session 文件。
- 更新和回滚路径清晰，不覆盖用户已有默认 niri 配置。

小任务：

Windows 操作：

- [x] 在项目 niri 配置中加入 Tahoe shell 自动启动项，使用带 `TAHOE_SKIP_QUICKSHELL_AUTOSTART` 防重入的 `spawn-sh-at-startup`。
- [x] 确认自动启动项不会和 `scripts/run-tahoe-session.sh` 的 `niri -- ... quickshell` 启动方式重复拉起 shell。
- [x] 为 Phase 1.5 固定启动策略：开发/嵌套测试继续用 `scripts/run-tahoe-session.sh`，真实 session 使用 niri 配置自动启动 Quickshell。
- [x] 增加或更新脚本，把 Tahoe session 入口部署到用户目录或系统 session 目录。
- [x] 如需登录管理器显示独立入口，新增 `Tahoe Niri` 的 `.desktop` session 文件。
- [x] 保持项目配置部署到 `~/.config/niri/tahoe/config.kdl`，不覆盖 `~/.config/niri/config.kdl`。
- [x] 更新 `scripts/README.md`，记录嵌套测试、TTY session、登录管理器三种启动方式。
- [x] commit 并 push。

Windows 本地状态：

- 已在 `config/niri/tahoe-phase0.kdl` 中加入 Tahoe Quickshell 自启动。
- 已更新 `scripts/run-tahoe-session.sh`：nested 使用 child 启动并禁用配置自启，真实 session 使用配置自启。
- 已新增 `scripts/tahoe-niri-session.sh` 作为登录会话启动器。
- 已更新 `scripts/arch-update.sh`，部署 `~/.local/bin/tahoe-niri-session`、系统级 `/usr/local/bin/tahoe-niri-session`、用户级 `~/.local/share/wayland-sessions/tahoe-niri.desktop` 和系统级 `/usr/share/wayland-sessions/tahoe-niri.desktop`。
- 已更新 `scripts/README.md`，记录 nested、TTY session 和登录管理器启动方式。

Hyper-V Arch Linux 操作：

- [x] 执行 `bash scripts/arch-update.sh`，部署最新 niri 配置、Tahoe shell 和 session 入口。
- [x] 从已有桌面里继续验证 nested 启动不重复拉起 Quickshell。
- [x] 从 TTY 执行 `NIRI_MODE=session bash scripts/run-tahoe-session.sh`，验证 niri 能拥有真实 session。
- [x] 验证进入 niri 后 Tahoe 顶栏和 Dock 自动出现。
- [x] 验证退出 niri 后 Quickshell 不残留异常进程。
- [x] 如已部署 `.desktop` 文件，验证登录管理器中能看到 `Tahoe Niri` 入口。

Hyper-V 截图验收记录：

- 2026-06-14 截图确认：`NIRI_MODE=nested bash scripts/run-tahoe-session.sh` 显示 `shell launch: child`，nested niri 中仅出现一套 Tahoe 顶栏和 Dock。
- 2026-06-14 截图确认：真实 niri session 中 Tahoe 顶栏和 Dock 自动出现，不需要手动运行 Quickshell。
- 2026-06-14 发现：登录管理器中未显示 `Tahoe Niri`。原因判断为多数登录管理器只扫描 `/usr/share/wayland-sessions`，不扫描用户级 `~/.local/share/wayland-sessions`；后续已回补系统级 session 部署。
- 2026-06-14 继续发现：当前登录器仍只显示 `Niri`，疑似 greeter 只读取 `/usr/share/xsessions` 或过滤 home 下 Exec；已回补 `/usr/local/bin/tahoe-niri-session` 和 `/usr/share/xsessions/tahoe-niri.desktop`。
- 2026-06-14 截图确认：登录器已显示 `Tahoe Niri`，但选择后未能进入 session；已将 launcher 改为优先复用 distro `niri-session` wrapper，并把诊断日志写入 `~/.local/state/tahoe-niri/session.log`。
- 2026-06-14 继续发现：登录器同时显示两个 `Tahoe Niri`，且日志显示黑屏那次来自 `XDG_SESSION_TYPE=x11`；判断为 Wayland session 和 xsession-compatible 文件同时被 greeter 展示。已默认清理 `/usr/share/xsessions/tahoe-niri.desktop`，保留 `/usr/share/wayland-sessions/tahoe-niri.desktop`。
- 2026-06-14 最终验收：修复因曾用 `sudo bash scripts/arch-update.sh` 造成的 root-owned 仓库权限后，普通用户执行 `bash scripts/arch-update.sh` 通过；登录器只保留一个 `Tahoe Niri`，选择后可进入 Tahoe niri session，Phase 1.5 通过验收。

Windows 到 Hyper-V 同步验证：

- [x] Windows 修改并 push Phase 1.5 脚本或配置后，在 Hyper-V Arch Linux 中执行 `bash scripts/arch-update.sh`。
- [x] 确认 Hyper-V 中运行的 session 入口、niri 配置、QML 和 Windows 仓库版本一致。

验收标准：

- [x] 进入 niri session 后 Tahoe shell 自动启动。
- [x] 顶栏、Dock、控制中心和 Launchpad 不需要手动运行 Quickshell 就可用。
- [x] 嵌套开发启动和真实 session 启动不会重复创建 Tahoe shell。
- [x] Tahoe session 可以作为后续真机登录会话的部署模板。
- [x] 回滚方式明确：禁用自动启动项或恢复普通 niri session 后，不影响用户已有 niri 配置。

## Phase 2: niri Fork 最小化/恢复

阶段目标：让 Dock 能真正最小化和恢复窗口。

主要产出：

- niri 中新增窗口最小化状态。
- IPC action 支持 minimize/restore。
- foreign-toplevel minimize/unminimize 生效。
- Quickshell 能看到 `Toplevel.minimized`。

建议分支：

```powershell
cd .\niri
git switch -c tahoe-desktop
```

小任务：

Windows 操作：

- [x] 在 `niri-ipc/src/lib.rs` 的 `Window` 增加 `is_minimized: bool`。
- [x] 在 `niri-ipc/src/lib.rs` 的 `Action` 增加 `MinimizeWindow { id: Option<u64> }`。
- [x] 在 `niri-ipc/src/lib.rs` 的 `Action` 增加 `RestoreWindow { id: u64 }`。
- [x] 评估是否需要 `ToggleWindowMinimized { id: Option<u64> }`：Phase 2 暂不需要，Dock 使用显式 minimize/restore。
- [x] 在 `niri-config/src/binds.rs` 增加对应 config action。
- [x] 在 `niri-config/src/binds.rs` 增加 `From<niri_ipc::Action>` 映射。
- [x] 在 `src/input/mod.rs` 的 `do_action()` 里分发 minimize action。
- [x] 在 `src/input/mod.rs` 的 `do_action()` 里分发 restore action。
- [x] 在 `src/layout/workspace.rs` 增加 minimize 状态切换 API。
- [x] 在 `src/layout/workspace.rs` 增加 restore 状态切换 API。
- [x] 在 `src/layout/workspace.rs` 处理 active/focus 窗口被最小化后的焦点切换。
- [x] 在 `src/layout/floating.rs` 让最小化窗口从 render 中排除。
- [x] 在 `src/layout/floating.rs` 让最小化窗口从 hit-test 中排除。
- [x] 在 `src/layout/floating.rs` 保留最小化前的位置和大小。
- [x] 在 `src/layout/mod.rs` 增加顶层 minimize/restore API。
- [x] 在 `src/layout/mod.rs` 支持根据 window id 找到所在 workspace。
- [x] 在 `src/ipc/server.rs` 的 `make_ipc_window()` 填充 `is_minimized`。
- [x] 在窗口最小化状态变化时触发 `WindowsChanged`。
- [x] 在需要时触发 `WindowLayoutsChanged`：最小化不改变 layout 几何，状态变化走 `WindowOpenedOrChanged`。
- [x] 在 `src/protocols/foreign_toplevel.rs` 处理 `SetMinimized`。
- [x] 在 `src/protocols/foreign_toplevel.rs` 处理 `UnsetMinimized`。
- [x] 在 foreign-toplevel state 中发送 minimized 状态。
- [x] 在 Quickshell Dock 中读取 `Toplevel.minimized`。
- [x] Dock 点击未最小化窗口时支持 activate。
- [x] Dock 点击已最小化窗口时支持 restore。
- [x] Dock 保持显示已最小化窗口。
- [x] 增加 IPC window state 测试。
- [x] 增加 foreign-toplevel minimized state 行为测试。

Windows 本机记录：

- [x] 已运行 `cargo fmt`；只出现现有 nightly-only rustfmt 配置警告。
- [x] 已尝试 `cargo check -p niri-ipc`；Windows 被 `niri-ipc/src/socket.rs` 的 `std::os::unix::net::UnixStream` 阻断。
- [x] 已尝试 `cargo check -p niri-config`；Windows 被 `xkbcommon` / `input` 的 `std::os::unix` 依赖阻断。
- [x] 完整构建、协议请求行为和手工窗口操作已在 Hyper-V Arch Linux 中验证。

Hyper-V Arch Linux 操作：

- [x] 执行 `BUILD_NIRI_FORK=auto bash scripts/arch-update.sh`，由脚本自动构建 niri fork 并部署 `tahoe-shell/`。
- [x] 重启 niri + Quickshell Tahoe shell。
- [x] 运行 `niri msg windows`，确认不再出现 CLI/compositor 版本或 IPC schema 错误。
- [x] 运行 `niri msg action minimize-window --id X`，确认窗口不可见。
- [x] 触发 restore，确认窗口恢复。
- [x] 验证最小化窗口不可被点中。
- [x] 验证恢复后窗口回到原 workspace。
- [x] 验证恢复后窗口回到原位置和大小。
- [x] 验证 Quickshell 中 `Toplevel.minimized` 能正确变为 true/false。
- [x] 验证 Dock 仍显示已最小化窗口。
- [x] 验证 Dock 点击未最小化窗口时 activate。
- [x] 验证 Dock 点击已最小化窗口时 restore。
- [ ] 在 Hyper-V Arch Linux 中运行可行的 niri 测试。

Hyper-V 截图验收记录：

- `屏幕截图 2026-06-14 172444.png`：`minimize-window --id 3` 后终端窗口不可见，Dock 仍保留对应窗口项。
- `屏幕截图 2026-06-14 172450.png`：通过 Dock restore 后终端窗口恢复，位置和大小保持一致。

Windows 到 Hyper-V 同步验证：

- [x] Windows 修改并 push niri fork 或 `tahoe-shell/` 后，在 Hyper-V Arch Linux 中执行 `BUILD_NIRI_FORK=auto bash scripts/arch-update.sh`。
- [x] 确认 Hyper-V 中构建的 niri commit 和 Windows 推送的 commit 一致。

验收标准：

- [x] `niri msg windows` 能正常读取窗口 IPC 状态。
- [x] `niri msg action minimize-window --id X` 后窗口不可见。
- [x] 最小化窗口不可被点中。
- [x] Dock 仍能看到最小化窗口。
- [x] restore 后窗口回到原 workspace。
- [x] restore 后窗口回到原位置和大小。
- [x] Quickshell 中 `Toplevel.minimized` 能正确变为 true/false。

## Phase 3: Snap Assist 与动画拟真

阶段目标：补齐拖拽吸附和基础 macOS 风格动效。

主要产出：

- niri snap assist。
- snap preview。
- Quickshell shell 动画。
- niri window open/close/move/resize/snap 动画参数。
- 普通 fade/scale minimize，Genie effect 暂缓。

### Phase 3A: Snap Assist

小任务：

Windows 操作：

- [x] 在 niri 配置中设计 `layout.snap-assist` 配置结构。
- [x] 支持 `snap-assist.on`。
- [x] 支持 `snap-assist.threshold`。
- [x] 支持 `snap-assist.preview-color`。
- [x] 支持 `snap-assist.preview-border-color`。
- [x] 在 `src/input/move_grab.rs` 监听拖动位置。
- [x] 判断鼠标是否靠近屏幕左边缘。
- [x] 判断鼠标是否靠近屏幕右边缘。
- [x] 判断鼠标是否靠近屏幕顶部。
- [x] 根据边缘位置计算 snap target。
- [x] 在 `src/layout/mod.rs` 的 `InteractiveMoveData` 中增加 snap target。
- [x] 在 `interactive_move_update()` 更新 snap target。
- [x] 在 `interactive_move_end()` 应用 snap target。
- [x] 在 `src/layout/floating.rs` 设置 floating window 的目标位置。
- [x] 在 `src/layout/floating.rs` 设置 floating window 的目标大小。
- [x] 保存 snap 前的 restore size。
- [x] 从 snap 状态再次拖动时恢复之前大小。
- [x] 新增或复用 render element 绘制 preview。
- [x] 参考 `insert_hint_element` 的渲染思路。
- [x] 给 preview 加淡入淡出状态。
- [x] 补充 floating/snap 相关测试。

Hyper-V Arch Linux 操作：

- [ ] 执行 `BUILD_NIRI_FORK=auto bash scripts/arch-update.sh`，由脚本自动构建 niri fork。
- [ ] 启动或重启 niri。
- [ ] 打开多个浮动窗口，验证拖拽窗口时 snap assist 可触发。
- [ ] 拖到左边，验证显示左半屏 preview。
- [ ] 拖到右边，验证显示右半屏 preview。
- [ ] 拖到顶部，验证显示最大化 preview。
- [ ] 松手后验证窗口尺寸正确。
- [ ] 松手后验证窗口位置正确。
- [ ] 从 snap 状态再次拖动，验证能恢复之前大小。
- [ ] 在 Hyper-V Arch Linux 中运行 floating/snap 相关测试。

Windows 到 Hyper-V 同步验证：

- [ ] Windows 修改并 push snap assist 代码后，在 Hyper-V Arch Linux 中执行 `BUILD_NIRI_FORK=auto bash scripts/arch-update.sh`。
- [ ] 确认 Hyper-V 中运行的 niri commit 和 Windows 推送的 commit 一致。

Snap assist 验收标准：

- [ ] 拖到左边显示左半屏 preview。
- [ ] 拖到右边显示右半屏 preview。
- [ ] 拖到顶部显示最大化 preview。
- [ ] 松手后窗口尺寸正确。
- [ ] 松手后窗口位置正确。
- [ ] 从 snap 状态再次拖动能恢复之前大小。

### Phase 3B: Quickshell 动画

小任务：

Windows 操作：

- [x] 给 Dock 图标添加 hover scale。
- [x] 给 Dock 图标添加 y offset。
- [x] 实现 Dock magnification，鼠标越近图标越大。
- [x] 实现 Dock hover label。
- [x] 给 Dock hover label 添加 opacity 动画。
- [x] 给 Dock hover label 添加 y offset 动画。
- [x] 实现 Dock icon bounce。
- [x] 控制中心打开时使用 scale + opacity 动画。
- [x] 控制中心关闭时使用 scale + opacity 动画。
- [x] Launchpad 打开时背景 blur。
- [x] Launchpad 打开时 app grid scale/fade。
- [x] Launchpad 关闭时反向 scale/fade。
- [x] 菜单弹窗使用轻微 y 位移 + opacity。
- [x] 通知从右上角滑入。
- [x] 通知 settle 使用 spring。
- [x] 从 Web 项目 `javascript/script.js` 参考 Dock magnification。
- [x] 从 Web 项目 `Css/style.css` 参考 transition 和 cubic-bezier。

Hyper-V Arch Linux 操作：

- [ ] 执行 `bash scripts/arch-update.sh`，由脚本拉取并部署最新 `tahoe-shell/`。
- [ ] 重启 Quickshell Tahoe shell。
- [ ] 验证 Dock magnification 跟随鼠标流畅。
- [ ] 验证 Dock hover label 的 opacity 和 y offset 动画。
- [ ] 验证 Dock icon bounce。
- [ ] 验证控制中心打开/关闭的 scale + opacity 动画。
- [ ] 验证 Launchpad 打开/关闭的 scale/fade/blur 动画。
- [ ] 验证菜单弹窗的 y 位移和 opacity 动画。
- [ ] 验证通知从右上角滑入并 settle。
- [ ] 验证动画不影响窗口 activate/minimize/restore。

Windows 到 Hyper-V 同步验证：

- [ ] Windows 修改并 push `tahoe-shell/` 动画后，在 Hyper-V Arch Linux 中执行 `bash scripts/arch-update.sh`。
- [ ] 确认 Hyper-V 中运行的 QML 和 Windows 推送的版本一致。

Quickshell 动画验收标准：

- [ ] Dock magnification 跟随鼠标流畅。
- [ ] 控制中心打开/关闭不突兀。
- [ ] Launchpad 打开/关闭有 scale/fade/blur。
- [ ] 动画不影响窗口 activate/minimize/restore。

### Phase 3C: niri 窗口动画

小任务：

Windows 操作：

- [x] 调整 `workspace-switch` 动画。
- [x] 调整 `window-open` 动画。
- [x] 调整 `window-close` 动画。
- [x] 调整 `window-movement` 动画。
- [x] 调整 `window-resize` 动画。
- [x] 调整 `overview-open-close` 动画。
- [x] 第一版窗口打开使用 scale 0.96 -> 1.0。
- [x] 第一版窗口打开使用 opacity 0 -> 1。
- [x] 第一版窗口关闭使用 scale 1.0 -> 0.96。
- [x] 第一版窗口关闭使用 opacity 1 -> 0。
- [x] 移动动画使用轻微 spring。
- [x] resize 动画使用平滑尺寸变化。
- [x] snap apply 使用 spring 过渡。
- [x] snap preview 使用 fade in/out。
- [x] 普通 minimize 先做 fade/scale 版本。
- [x] 暂不实现 Genie deformation。

Hyper-V Arch Linux 操作：

- [ ] 执行 `BUILD_NIRI_FORK=auto bash scripts/arch-update.sh`，由脚本自动构建 niri fork。
- [ ] 启动或重启 niri。
- [ ] 验证 workspace switch 动画。
- [ ] 验证 window open 动画。
- [ ] 验证 window close 动画。
- [ ] 验证 window movement 动画。
- [ ] 验证 window resize 动画。
- [ ] 验证 overview open/close 动画。
- [ ] 验证 snap preview 淡入淡出。
- [ ] 验证 snap apply spring 过渡。
- [ ] 验证普通 minimize fade/scale 动画。

Windows 到 Hyper-V 同步验证：

- [ ] Windows 修改并 push niri 动画代码或配置后，在 Hyper-V Arch Linux 中执行 `BUILD_NIRI_FORK=auto bash scripts/arch-update.sh`。
- [ ] 确认 Hyper-V 中运行的 niri commit 和 Windows 推送的 commit 一致。

niri 动画验收标准：

- [ ] 窗口 open/close 不突兀。
- [ ] move/resize 不过度弹。
- [ ] snap preview 有淡入淡出。
- [ ] snap apply 有平滑过渡。
- [ ] 普通 minimize 已有可接受动画。

## Phase 4: Liquid Glass

阶段目标：让面板和窗口效果更接近 macOS 26 Tahoe 的 Liquid Glass。

主要产出：

- 更强的 background-effect 参数。
- layer-shell 面板真实背景模糊。
- 更高级 glass tint/highlight/edge light/refraction shader。

小任务：

Windows 操作：

- [ ] 先使用 niri 现有 `background-effect`。
- [ ] 先使用 Quickshell `BackgroundEffect.blurRegion`。
- [ ] 为 Dock 设置 blur region。
- [ ] 为控制中心设置 blur region。
- [ ] 为顶栏设置 blur region。
- [ ] 调整 `noise` 参数。
- [ ] 调整 `saturation` 参数。
- [ ] 调整透明 QML 背景。
- [ ] 在 `src/render_helpers/background_effect.rs` 研究 per-surface background effect。
- [ ] 在 `src/render_helpers/framebuffer_effect.rs` 研究 framebuffer effect。
- [ ] 在 `src/render_helpers/xray.rs` 研究 xray/backdrop。
- [ ] 在 `src/render_helpers/shaders/postprocess.frag` 增加或试验 tint/highlight。
- [ ] 评估是否需要新 shader 文件。
- [ ] 增加 glass tint 参数。
- [ ] 增加 edge highlight 参数。
- [ ] 增加 refraction/displacement 原型。
- [ ] 区分 active/inactive 窗口的玻璃强度。
- [ ] 区分 layer-shell 面板和普通窗口的玻璃参数。
- [ ] 记录多显示器和 fractional scale 的最终真机待测项。

Hyper-V Arch Linux 操作：

- [ ] 执行 `BUILD_NIRI_FORK=auto bash scripts/arch-update.sh`，由脚本自动构建 niri fork 并部署 `tahoe-shell/`。
- [ ] 启动或重启 niri + Quickshell Tahoe shell。
- [ ] 记录 FPS 基线。
- [ ] 在 Hyper-V 中测试窗口背后内容变化时 blur 是否同步。
- [ ] 在 Hyper-V 中记录 GPU/FPS 表现，仅作为参考。
- [ ] 检查 Dock 是否有真实背景模糊。
- [ ] 检查控制中心是否有真实背景模糊。
- [ ] 检查顶栏是否有真实背景模糊。
- [ ] 检查 Hyper-V 中是否出现功能性破图。

Windows 到 Hyper-V 同步验证：

- [ ] Windows 修改并 push glass/shader/QML 参数后，在 Hyper-V Arch Linux 中执行 `BUILD_NIRI_FORK=auto bash scripts/arch-update.sh`。
- [ ] 确认 Hyper-V 中运行的 niri commit、QML 和 assets 与 Windows 推送版本一致。

验收标准：

- [ ] Dock 有真实背景模糊。
- [ ] 控制中心有真实背景模糊。
- [ ] 顶栏有真实背景模糊。
- [ ] 窗口背后内容变化时玻璃同步变化。
- [ ] Hyper-V 中没有明显功能性破图。
- [ ] FPS、GPU、多显示器、fractional scale 的最终结论留到真机验收。

## Phase 5: 更深桌面化

阶段目标：在最小闭环稳定后，继续向完整 macOS 风格桌面靠近。

主要产出：

- 更完整的桌面级窗口体验。
- 可选的服务端窗口装饰。
- 可选的红黄绿按钮。
- 更完整 app menu。
- 更高级的 Genie minimize。

小任务：

Windows 操作：

- [ ] 评估是否需要服务端窗口装饰。
- [ ] 评估是否给浮动窗口添加红黄绿按钮。
- [ ] 设计关闭、最小化、最大化按钮与 niri action 的映射。
- [ ] 评估 Wayland 下 app menu 的可行方案。
- [ ] 研究 DBus/appmenu 工具链是否可接入。
- [ ] 改进窗口 z-order 行为。
- [ ] 增强 raise/lower 语义。
- [ ] 增强窗口切换体验。
- [ ] 增强任务栏/Dock 状态。
- [ ] 设计 Dock icon rect 到 niri IPC 的传输格式。
- [ ] 扩展 `MinimizeWindow { id, target_rect }`。
- [ ] 扩展 `RestoreWindow { id, source_rect }`。
- [ ] 实现 minimize snapshot。
- [ ] 实现 restore snapshot。
- [ ] 实现 Genie-style shader 或 mesh deformation。
- [ ] 实现 restore reverse animation。
- [ ] 处理 Genie 动画期间窗口真实状态。
- [ ] 处理 Genie 动画中断场景。
- [ ] 处理多显示器下 Dock target rect 坐标。
- [ ] 处理 fractional scale 下 Dock target rect 坐标。
- [ ] 增加 Genie 相关视觉测试或手动测试脚本。

Hyper-V Arch Linux 操作：

- [ ] 执行 `BUILD_NIRI_FORK=auto bash scripts/arch-update.sh`，由脚本自动构建 niri fork 并部署 `tahoe-shell/`。
- [ ] 启动或重启 niri + Quickshell Tahoe shell。
- [ ] 验证窗口 z-order、raise/lower 和窗口切换体验。
- [ ] 验证任务栏/Dock 状态与窗口状态一致。
- [ ] 验证可选窗口装饰不会破坏客户端装饰窗口。
- [ ] 验证红黄绿按钮映射到正确 niri action。
- [ ] 验证 Dock icon rect 到 niri IPC 的传输结果。
- [ ] 验证 minimize/restore snapshot 行为。
- [ ] 验证 Genie-style 动画不阻塞普通 minimize/restore 闭环。
- [ ] 验证 Genie 动画中断场景。
- [ ] 在 Hyper-V 能覆盖的范围内验证多显示器 Dock target rect 坐标。
- [ ] 在 Hyper-V 能覆盖的范围内验证 fractional scale Dock target rect 坐标。
- [ ] 运行 Genie 相关视觉测试或手动测试脚本。

Windows 到 Hyper-V 同步验证：

- [ ] Windows 修改并 push Phase 5 代码后，在 Hyper-V Arch Linux 中执行 `BUILD_NIRI_FORK=auto bash scripts/arch-update.sh`。
- [ ] 确认 Hyper-V 中运行的 niri commit、QML 和 assets 与 Windows 推送版本一致。

验收标准：

- [ ] 桌面使用方式更接近传统 Windows/macOS stacking WM。
- [ ] Dock、窗口状态、最小化、恢复之间状态一致。
- [ ] Genie effect 不阻塞普通 minimize/restore 闭环。
- [ ] 可选窗口装饰不会破坏现有客户端装饰窗口。
- [ ] 高级效果可以关闭或降级。
- [ ] 到此阶段结束前仍以 Hyper-V 验证为主，不要求真机验证通过。

## 最终真机验收

执行时机：Phase 0 到 Phase 5 全部完成后。

目标：把 Hyper-V 中已经完成的实现搬到真机 Linux 环境，做最终视觉、性能和稳定性验收。

小任务：

真机 Linux 操作：

- [ ] 在真机 Linux 上安装或部署 niri fork。
- [ ] 在真机 Linux 上部署 `tahoe-shell/`。
- [ ] 复用 Hyper-V 阶段确认过的 niri 配置。
- [ ] 验证 niri 是否能作为真实 Wayland session 稳定启动。
- [ ] 验证 Quickshell 顶栏、Dock、控制中心、Launchpad 是否正常显示。
- [ ] 验证窗口 activate/minimize/restore/snap 行为。
- [ ] 验证 Dock、控制中心、顶栏的 blur/glass 最终观感。
- [ ] 验证 Liquid Glass shader 的 FPS 和 GPU 占用。
- [ ] 验证多显示器。
- [ ] 验证 fractional scale。
- [ ] 验证 suspend/resume 后 shell 和 compositor 状态。
- [ ] 验证长时间使用后的稳定性。

真机到 Windows 回补：

- [ ] 记录真机专属问题、性能瓶颈和显示差异。
- [ ] 在 Windows 工作区根据真机结果回补配置参数或 shader 降级开关。
- [ ] Windows commit 并 push 真机回补修改。
- [ ] 真机 Linux 从 GitHub pull 回补修改并复测关键项。

验收标准：

- [ ] 真机上可以日常进入 niri session。
- [ ] Tahoe shell 可以随 session 启动。
- [ ] Dock、顶栏、控制中心、Launchpad 可用。
- [ ] 最小化、恢复、snap、窗口动画可用。
- [ ] 玻璃效果观感接近预期。
- [ ] FPS 和输入延迟可接受。
- [ ] 出现真机专属问题时，有明确修复清单或降级方案。

## 最小闭环推荐顺序

这部分来自交接文档的“下一步推荐”。每一步都按固定闭环执行：Windows 修改并 push，Hyper-V Arch Linux 执行 `bash scripts/arch-update.sh` 后验证。

**1. Quickshell 静态 shell**

Windows 操作：

- [x] 新建 `tahoe-shell/`。
- [x] 做 Quickshell 顶栏静态 UI。
- [x] 做 Quickshell Dock 静态 UI。
- [x] commit 并 push。

Hyper-V Arch Linux 操作：

- [x] 执行 `bash scripts/arch-update.sh`。
- [x] 启动 Quickshell Tahoe shell。
- [x] 验证顶栏和 Dock 可见。

**2. Dock 真实窗口列表**

Windows 操作：

- [x] 接入 `ToplevelManager`。
- [x] 让 Dock 显示真实窗口。
- [x] commit 并 push。

Hyper-V Arch Linux 操作：

- [x] 执行 `bash scripts/arch-update.sh`。
- [x] 打开多个窗口。
- [x] 验证 Dock 能显示真实窗口列表。

**2.5. Phase 1.5 niri Session 集成**

Windows 操作：

- [x] 给 Tahoe niri 配置增加 Quickshell 自动启动项。
- [x] 明确 nested 调试和真实 session 的启动策略，避免重复拉起 Quickshell。
- [x] 可选新增 `Tahoe Niri` 登录会话入口。
- [x] 更新 `scripts/README.md`。
- [x] commit 并 push。

Hyper-V Arch Linux 操作：

- [x] 执行 `bash scripts/arch-update.sh`。
- [x] 验证 nested 启动仍正常。
- [x] 验证真实 niri session 中 Tahoe shell 自动出现。
- [x] 如已新增 `.desktop` 文件，验证登录管理器入口。

**3. niri minimize/restore**

Windows 操作：

- [x] 在 niri fork 里实现 minimize/restore。
- [x] 补 IPC 和 foreign-toplevel 状态。
- [x] commit 并 push。

Hyper-V Arch Linux 操作：

- [x] 执行 `BUILD_NIRI_FORK=auto bash scripts/arch-update.sh`。
- [x] 启动或重启 niri。
- [x] 验证 `minimize-window` 和 restore 行为。

**4. Dock activate/restore/minimize**

Windows 操作：

- [x] Dock 点击未最小化窗口时 activate。
- [x] Dock 点击已最小化窗口时 restore。
- [ ] 需要时补 Dock 触发 minimize 的入口。
- [x] commit 并 push。

Hyper-V Arch Linux 操作：

- [x] 执行 `BUILD_NIRI_FORK=auto bash scripts/arch-update.sh`。
- [x] 验证 Dock activate/restore 行为。
- [x] 验证 Dock 和 niri 窗口状态一致。

**5. Snap assist**

Windows 操作：

- [x] 在 niri fork 中实现 snap assist。
- [x] 实现 snap preview。
- [ ] commit 并 push。

Hyper-V Arch Linux 操作：

- [ ] 执行 `BUILD_NIRI_FORK=auto bash scripts/arch-update.sh`。
- [ ] 验证左半屏、右半屏、最大化 snap。
- [ ] 验证从 snap 状态拖动恢复原尺寸。

**6. Quickshell 动画**

Windows 操作：

- [x] 补 Dock 动画。
- [x] 补控制中心动画。
- [x] 补 Launchpad 动画。
- [ ] commit 并 push。

Hyper-V Arch Linux 操作：

- [ ] 执行 `bash scripts/arch-update.sh`。
- [ ] 验证 Dock magnification。
- [ ] 验证控制中心和 Launchpad 打开/关闭动画。
- [ ] 验证动画不影响窗口操作。

**7. niri 窗口动画**

Windows 操作：

- [x] 补窗口 open/close 动画。
- [x] 补窗口 move/resize 动画。
- [x] 补 snap apply 动画。
- [ ] commit 并 push。

Hyper-V Arch Linux 操作：

- [ ] 执行 `BUILD_NIRI_FORK=auto bash scripts/arch-update.sh`。
- [ ] 验证 open/close/move/resize/snap 动画。
- [ ] 记录 Hyper-V 环境下的异常或卡顿。

**8. Liquid Glass 和 Genie minimize**

Windows 操作：

- [ ] 调整 Liquid Glass 参数。
- [ ] 试验 glass shader。
- [ ] 实现或试验 Genie minimize。
- [ ] commit 并 push。

Hyper-V Arch Linux 操作：

- [ ] 执行 `BUILD_NIRI_FORK=auto bash scripts/arch-update.sh`。
- [ ] 验证 Dock、顶栏、控制中心 blur/glass。
- [ ] 验证 Genie minimize 不破坏普通 minimize/restore。
- [ ] 记录 GPU/FPS 表现，仅作为参考。

**9. 最终真机验收**

真机 Linux 操作：

- [ ] Phase 0 到 Phase 5 完成后，从 GitHub 拉取同一仓库。
- [ ] 部署 niri fork 和 `tahoe-shell/`。
- [ ] 做最终视觉、性能和稳定性验收。

真机到 Windows 回补：

- [ ] 把真机专属问题记录成修复清单。
- [ ] 在 Windows 工作区回补配置、shader 或降级开关。
- [ ] commit 并 push 后回到真机复测。

## 测试清单

niri:

Windows 操作：

- [ ] 补 `src/tests/floating.rs` 相关测试。
- [ ] 补 `src/tests/window_opening.rs` 相关测试。
- [ ] 补 layout snapshot tests。
- [ ] 补 IPC window state tests。
- [ ] 补 foreign-toplevel minimize/unminimize 行为测试。
- [ ] 运行 Windows 环境中可行的 Rust 静态检查和单元测试。

Hyper-V Arch Linux 操作：

- [ ] 执行 `BUILD_NIRI_FORK=auto bash scripts/arch-update.sh`，由脚本拉取并构建最新 niri fork。
- [ ] 在 Hyper-V Arch 中运行 `cargo test --all`。
- [ ] 在 Hyper-V Arch 中重复关键 IPC、layout、foreign-toplevel 测试。

真机 Linux 操作：

- [ ] Phase 5 完成后，在真机 Linux 中重复关键测试。

Quickshell:

Windows 操作：

- [ ] 补充 QML 组件层面的可维护检查清单。
- [ ] 检查 Tahoe shell assets 路径和图标映射是否集中管理。

Hyper-V Arch Linux 操作：

- [ ] 优先在 Hyper-V Arch 的 Wayland/niri session 下手动运行。
- [ ] 检查 `PanelWindow` 是否正确占位。
- [ ] 检查 `BackgroundEffect.blurRegion` 是否生效。
- [ ] 检查 `ToplevelManager` 是否能读到 niri 窗口。
- [ ] 检查 `WindowManager.windowsets` 是否能读到 niri workspace。
- [ ] 检查 Dock activate/minimize/restore 行为。
- [ ] 检查控制中心和 Launchpad 动画。

真机 Linux 操作：

- [ ] Phase 5 完成后，在真机 Linux 中重复完整手动验收。

## 暂不优先做

- [ ] 不先 fork GNOME/KDE。
- [ ] 不先改 Quickshell 核心。
- [ ] 不直接运行 Web 项目作为真实 shell。
- [ ] 不先做完整 macOS 全局菜单栏。
- [ ] 不先做锁屏或登录管理器。
- [ ] 不一开始追求完整 Genie effect。
- [ ] 不一开始追求完整服务端窗口装饰。
