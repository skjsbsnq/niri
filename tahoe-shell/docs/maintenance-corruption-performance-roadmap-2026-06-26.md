# Tahoe Desktop 可维护性、抗腐化与性能改进研究路线图

日期：2026-06-26

范围：

- `tahoe-shell/` QML shell、服务层、脚本和配置编辑工具。
- `niri/` fork 中 Tahoe 相关 compositor 改动、协议、IPC、渲染路径。
- `quickshell/` fork 中 TahoeGlass client、Wayland 模块接入、fallback 路径。

目标：

- 增强可维护性，降低后续功能叠加造成的腐化。
- 优化明显的性能风险点，但不为了微优化引入复杂架构。
- 允许局部重构，但必须保持行为兼容。
- 每次只完成一个任务，验收通过后才能进入下一个任务。

非目标：

- 不重写 shell。
- 不替换 niri、quickshell 或 Wayland 协议栈。
- 不为了减少文件数量而合并职责。
- 不把私有 Tahoe 能力伪装成通用上游 API。
- 不在没有测试或人工验收的情况下调整视觉、动画、窗口行为。

## 总体结论

项目目前不是“接口和协议已经失控”。`niri` 作为完整 Wayland compositor，协议数量整体合理；`quickshell` 作为 shell toolkit，也需要多个 Wayland 模块来覆盖 layer-shell、toplevel、screencopy、idle、shortcut inhibit 等能力。

真正的腐化风险不在“协议多”，而在以下几个边界：

1. Tahoe 私有协议 XML 双份维护，缺少自动漂移检查。
2. `tahoe-shell/services/Windows.qml` 同时合并 Wayland toplevel、WindowManager、niri IPC event stream，字段来源和优先级没有被测试或文档固化。
3. Quickshell `TahoeGlass` 和既有 `BackgroundEffect` 复制了 attached Wayland object 的生命周期逻辑。
4. `tahoe-shell/shell.qml` 和多个服务文件承担过多全局协调职责。
5. `niri_settings_tool.py` 是手写 KDL 编辑器，功能重要但测试边界不足。
6. thumbnail 目前按组件启动 `niri msg window-thumbnail` 进程，窗口数量上来后会成为性能和调度问题。
7. 部署脚本有破坏性子模块操作，长期维护风险高。

路线图采用 KISS 原则：先加护栏和文档，后做小步拆分；先保护行为，再减少重复；先复用已有接口，再考虑新增接口。

## KISS 执行原则

所有后续任务必须遵守：

1. 一个任务只解决一个边界问题。
2. 完成当前任务的验收后，才能开始下一个任务。
3. 每个任务必须能单独回滚。
4. 优先加 guardrail、测试、文档，再做重构。
5. 不引入新框架、不引入全局状态管理库、不引入复杂构建系统改造。
6. 不做“顺手整理”。
7. 重构只允许局部移动职责，不允许改变用户可见行为。
8. 性能优化必须有明确触发点，例如重复进程、重复渲染、重复解析、无界列表、无界 watcher。

每个任务完成时至少运行：

```bash
bash scripts/check-tahoe-glass-guardrails.sh
python3 tahoe-shell/services/niri_settings_tool.py read --config config/niri/tahoe-phase0.kdl
```

涉及 niri 时按任务选择运行：

```bash
cargo test --manifest-path niri/Cargo.toml -p niri
cargo test --manifest-path niri/Cargo.toml -p niri-config
```

涉及 quickshell C++ 时按本机环境选择运行 quickshell 对应构建或最小模块测试。

## 接口与协议研究结论

### niri 协议数量

`niri/src/protocols/mod.rs` 中本地协议模块包括：

- `ext_workspace`
- `foreign_toplevel`
- `gamma_control`
- `mutter_x11_interop`
- `output_management`
- `screencopy`
- `tahoe_glass`
- `virtual_pointer`

这些不是同一概念的重复实现。多数属于 compositor 正常能力或兼容协议。Tahoe 专有协议主要是 `tahoe-glass-v1`。

`foreign_toplevel` 同时支持 `ext-foreign-toplevel-list` 和 `wlr-foreign-toplevel-management` 是合理兼容：前者偏列表和标识，后者提供 taskbar/dock 常用操作，例如 minimize、activate、close、set_rectangle。当前 `set_rectangle` 还被 Genie/minimize 动画复用，方向正确。

### TahoeGlass 是否重复 BackgroundEffect

不是完全重复。

`ext-background-effect-v1` 主要表达 client blur region。TahoeGlass 增加了：

- 多 region。
- region id。
- 四角半径。
- material 名称。
- blur/shadow/clip flags。
- interaction。
- materialAlpha。
- compositor-owned material、shadow、refraction、edge highlight。

这些能力无法干净地塞进标准 background effect 而不破坏语义。因此 TahoeGlass 作为私有协议是合理的。

但 Quickshell client 侧存在可维护性重复：`TahoeGlass` 和 `BackgroundEffect` 都处理 ProxyWindow、QWindow、QWaylandWindow、surface created/destroyed、reload object stealing、polish 调度。这里应该做局部 helper，而不是合并两个协议。

### window-thumbnail 走 IPC 是否合理

合理。

thumbnail 是 Tahoe shell 私有预览能力，不适合新增 Wayland protocol。当前通过 niri IPC：

- `niri/niri-ipc/src/lib.rs` 中 `Request::WindowThumbnail`
- `niri/src/ipc/server.rs` 中校验和调度
- `niri/src/niri.rs` 中渲染并写 PNG
- `tahoe-shell/components/DockMinimizedWindow.qml` 中调用 `niri msg window-thumbnail`

主要风险不是接口选择，而是后续重复造 provider。Dock、Overview、Switcher 等需要窗口缩略图时，应复用同一 thumbnail provider，不得新增第二套截图/抓图接口。

## 风险清单

### R1：TahoeGlass 协议 XML 双份维护

位置：

- `niri/resources/tahoe-glass-v1.xml`
- `quickshell/src/wayland/tahoe_glass/tahoe-glass-v1.xml`

当前状态：

- 两份 XML 当前 byte-identical。
- 没有找到自动 drift guard。

风险：

- server 和 client 协议描述漂移后，生成代码仍可编译，但运行时行为可能错位。
- surface interface 已是 v3，而 manager global 只能公布 v1，后续维护者容易误改。

改进方向：

- 加 `cmp` 检查。
- 加版本检查或测试，固定 manager global `VERSION = 1` 的原因。
- 把协议变更流程写入 TahoeGlass guardrails。

### R2：Window 模型来源过多

位置：

- `tahoe-shell/services/Windows.qml`

当前状态：

- 同时读取 Quickshell `ToplevelManager.toplevels`。
- 同时读取 Quickshell `WindowManager.windowsets`。
- 同时读取 niri IPC event stream。
- `mergeWindowModels()` 根据 appId/title 做匹配。

风险：

- 同一个字段在不同来源上含义不一致。
- title/appId 匹配可能误合并同应用多窗口。
- 新功能容易随手从任意来源读字段，形成隐式优先级。

改进方向：

- 文档化字段来源优先级。
- 把 merge 逻辑拆成纯函数文件。
- 给典型场景加 fixtures：同 app 多窗口、无 IPC、有 IPC 无 toplevel、minimized、workspace move、title 变化。

### R3：Quickshell TahoeGlass lifecycle 重复

位置：

- `quickshell/src/wayland/tahoe_glass/qml.cpp`
- `quickshell/src/wayland/background_effect/qml.cpp`

当前状态：

- 两者各自处理 attached object 生命周期。
- TahoeGlass 额外实现 fallback 到 BackgroundEffect blurRegion。

风险：

- Qt/Wayland 生命周期 bug 修一次漏一次。
- reload、surface destroy、window handle recreate 时容易出现悬空指针、重复 attach、漏清理。

改进方向：

- 抽一个轻量 helper，只负责：
  - 从 ProxyWindow 取得 backing QWindow。
  - 监听 visible / surfaceCreated / surfaceDestroyed / destroyed。
  - 保存当前 QWaylandWindow。
  - 支持 property-based object stealing。
- `BackgroundEffect` 和 `TahoeGlass` 保留自己的协议语义，只复用生命周期骨架。

### R4：shell.qml 全局协调职责过重

位置：

- `tahoe-shell/shell.qml`

当前状态：

- 作为全局 overlay、状态、面板、弹窗、快捷入口协调器。
- 多个布尔状态和跨组件调用集中在一处。

风险：

- 新增 UI 功能时倾向继续往 shell.qml 加全局状态。
- 面板互斥、dismiss、focus、animation 状态容易交叉影响。

改进方向：

- 不拆视觉结构，先抽 overlay 状态协调为小服务。
- 只移动状态和命令，不移动 UI 布局。
- 为“打开一个面板时关闭其它互斥面板”建立单一入口。

### R5：Controls.qml 服务职责过多

位置：

- `tahoe-shell/services/Controls.qml`

当前状态：

- 同时管理 audio、brightness、Wi-Fi、Bluetooth、media 等。

风险：

- 单个系统服务失败影响整个 control center 数据层。
- watcher/timer/process 分散，性能和错误处理难以统一。

改进方向：

- 先只抽纯 helpers 和子服务边界。
- 不改变 QML 外部 API。
- 优先拆高变动、外部命令多、错误多的域，例如 Wi-Fi/Bluetooth。

### R6：niri_settings_tool.py 重要但测试不足

位置：

- `tahoe-shell/services/niri_settings_tool.py`

当前状态：

- 约千行手写 KDL 修改工具。
- 能读写 Tahoe settings、glass material、input/output 等配置。

风险：

- KDL 注释、空白、块顺序、未知字段容易被破坏。
- 设置面板后续扩展会持续增加编辑规则。

改进方向：

- 先加 fixture/golden tests。
- 后续只在测试覆盖的域内做小规模整理。
- 不急着换 parser，除非现有工具无法可靠保留格式。

### R7：thumbnail 进程和缓存策略

位置：

- `tahoe-shell/components/DockMinimizedWindow.qml`
- `tahoe-shell/services/Windows.qml`
- `niri/src/niri.rs`

当前状态：

- 每个 minimized item 自己启动 `niri msg window-thumbnail`。
- 有单组件 running/pending，但没有全局队列。
- thumbnail 写入 `$XDG_RUNTIME_DIR/tahoe/window-thumbnails/`。

风险：

- 多窗口同时刷新时进程数增加。
- Overview、TaskSwitcher 未来若重复实现，会出现多套 thumbnail provider。
- IPC server 允许 absolute path，虽是本地 trusted IPC，但边界需要更明确。

改进方向：

- 在 shell 侧建立一个 thumbnail provider/queue。
- 所有组件只请求 provider，不直接启动进程。
- niri IPC 继续复用，不新增 Wayland 接口。
- 评估是否限制 path 到 runtime/cache 目录。

### R8：部署脚本破坏性操作

位置：

- `scripts/arch-update.sh`

当前状态：

- 子模块更新流程中存在 `git reset --hard`。

风险：

- 本地未提交改动可能被破坏。
- 后续维护者难以判断脚本是否安全。

改进方向：

- 默认 dry-run 或显式 `--force` 才允许破坏性操作。
- 在 reset 前打印 submodule dirty 状态并中止。
- 把 guardrail 检查放在部署前固定执行。

## 串行改进路线图

以下任务必须按顺序执行。每个任务完成并验收后，才能进入下一个任务。

### T0：建立维护基线

目标：

- 确认当前状态可复现。
- 明确哪些文件已有用户改动，避免后续误覆盖。

范围：

- 只读检查。
- 不修改代码。

步骤：

1. 记录 `git status --short`。
2. 运行 Tahoe guardrail。
3. 运行 niri settings read。
4. 记录当前 niri/quickshell 分支和 fork diff 大小。

验收：

- 有一份简短基线记录。
- 明确当前未跟踪/已修改文件。
- 无代码改动。

完成后才能开始：T1。

### T1：TahoeGlass 协议漂移护栏

目标：

- 防止 niri server XML 和 quickshell client XML 漂移。

范围：

- 新增或扩展脚本。
- 不改协议内容。
- 不改生成逻辑。

建议实现：

- 在 `scripts/check-tahoe-glass-guardrails.sh` 中增加：

```bash
cmp -s \
  niri/resources/tahoe-glass-v1.xml \
  quickshell/src/wayland/tahoe_glass/tahoe-glass-v1.xml
```

- 失败时打印明确说明：必须同步更新 server/client XML。

验收：

- 两份 XML 相同则 guardrail 通过。
- 人为改动其中一份时 guardrail 失败。
- 不改变任何运行时行为。

完成后才能开始：T2。

### T2：TahoeGlass 版本与 ABI 护栏

目标：

- 固化 manager v1 / surface v3 的协议事实，防止维护者误改。

范围：

- niri 协议测试或脚本检查。
- 不改协议字段。
- 不改 `VERSION` 当前值。

建议实现：

- 增加最小检查：
  - `niri/src/protocols/tahoe_glass.rs` 中 manager global `VERSION` 必须为 `1`。
  - XML 中 `tahoe_glass_manager_v1 version="1"`。
  - XML 中 `tahoe_glass_surface_v1 version="3"`。

验收：

- 修改任一版本会触发测试或 guardrail 失败。
- 注释中保留 manager 不能公布 v3 的原因。

完成后才能开始：T3。

### T3：窗口模型字段来源契约

目标：

- 明确 `Windows.qml` 中每个字段的 source-of-truth。

范围：

- 先写文档和注释。
- 不改 merge 行为。

建议契约：

- `id`：niri IPC 为准。
- `workspaceId` / `workspace` / `output`：niri IPC 为准。
- `isMinimized`：niri IPC 为准；无 IPC 时使用 Wayland toplevel fallback。
- `focused`：niri IPC 为准；无 IPC 时使用 toplevel activated fallback。
- `title` / `appId`：niri IPC 优先，toplevel fallback。
- `activate` / `close` / `setRectangle`：优先复用 Wayland toplevel/window manager 能力。
- `thumbnail`：只通过 niri IPC thumbnail provider。

验收：

- 文档存在。
- `Windows.qml` 顶部或 merge 函数附近有简短契约注释。
- 没有行为改动。

完成后才能开始：T4。

### T4：Windows.qml merge 逻辑测试化

目标：

- 在不改变行为的情况下，保护窗口模型合并逻辑。

范围：

- 把纯数据处理逻辑提到可测试 JS helper，或增加 QML/JS 测试 fixture。
- 不改 UI。
- 不改 IPC。

最小拆分对象：

- `normalizeIpcWindow`
- `findMatchingToplevel`
- `buildWindowModel`
- `mergeWindowModels`
- `filteredMinimizedWindows`
- `sortedWorkspaceList`

测试场景：

1. 单窗口 IPC + toplevel 正常合并。
2. 同 appId 多窗口不同 title。
3. IPC 缺失时保留 toplevel fallback。
4. toplevel 缺失时保留 IPC window。
5. minimized 字段以 IPC 为准。
6. title 变化后不错误复用旧窗口。

验收：

- merge helper 有测试。
- 原 `Windows.qml` 外部 API 不变。
- Dock、TaskSwitcher、minimized shelf 行为不变。

完成后才能开始：T5。

### T5：thumbnail provider 串行队列

目标：

- 避免每个组件直接启动 thumbnail 进程。
- 为 Dock、Overview、TaskSwitcher 复用同一 provider 铺路。

范围：

- shell 侧新增/整理 provider。
- niri IPC 保持不变。
- Dock UI 行为不变。

建议实现：

- 在 `tahoe-shell/services/Windows.qml` 或独立 `ThumbnailProvider.qml` 中提供：
  - `requestThumbnail(windowId, path, maxWidth, maxHeight, callbackKey)`
  - 全局队列。
  - 最大并发 1 或 2。
  - 同一 windowId/path 的 pending 请求合并。
  - 失败状态回传。

验收：

- `DockMinimizedWindow.qml` 不直接构造 `niri msg window-thumbnail` 命令。
- 多 minimized 窗口同时出现时不会启动无界进程。
- thumbnail 失败仍显示 fallback。
- 不新增截图协议。

完成后才能开始：T6。

### T6：thumbnail path 安全边界

目标：

- 明确 thumbnail 写入路径是受控 runtime/cache 路径。

范围：

- 优先 shell 侧约束。
- 可选 niri IPC server 侧增加限制。
- 不改变返回结构。

建议：

- shell provider 只生成 `$XDG_RUNTIME_DIR/tahoe/window-thumbnails/window-<id>.png`。
- niri 侧可选择拒绝非 runtime/cache 的 path，或至少文档说明 IPC 是 trusted local API。

验收：

- 组件不能传 arbitrary path。
- 旧 thumbnail 目录仍可被清理。
- Dock 缩略图正常。

完成后才能开始：T7。

### T7：Quickshell attached Wayland lifecycle helper

目标：

- 消除 `TahoeGlass` 和 `BackgroundEffect` 的重复生命周期逻辑。

范围：

- 只在 quickshell fork 内做局部 C++ helper。
- 不改变 QML API。
- 不改变 TahoeGlass protocol。
- 不改变 BackgroundEffect behavior。

建议 helper 职责：

- 持有 `ProxyWindowBase*`、`QWindow*`、`QWaylandWindow*`。
- 连接：
  - `ProxyWindowBase::windowConnected`
  - `ProxyWindowBase::polished`
  - `ProxyWindowBase::devicePixelRatioChanged`
  - `QWindow::visibleChanged`
  - `QWaylandWindow::surfaceCreated`
  - `QWaylandWindow::surfaceDestroyed`
  - `QObject::destroyed`
- 提供回调：
  - `onWaylandSurfaceAvailable(QWaylandWindow*)`
  - `onWaylandSurfaceGone()`
  - `onProxyWindowGone()`

禁止事项：

- 不把 TahoeGlass region 逻辑塞进 helper。
- 不把 BackgroundEffect blur region 逻辑塞进 helper。
- 不改变 fallback 行为。

验收：

- TahoeGlass 和 BackgroundEffect 共享 lifecycle helper。
- reload 时 protocol object stealing 仍正常。
- surface destroy 不崩溃、不重复 attach。
- Tahoe shell 玻璃 fallback 仍正常。

完成后才能开始：T8。

### T8：TahoeGlass region limit 常量统一

目标：

- 消除 quickshell client 中裸写 `32` 的维护风险。

范围：

- quickshell TahoeGlass client。
- niri server 不改行为。

当前问题：

- niri 使用 `MAX_REGIONS_PER_SURFACE = 32`。
- quickshell `qml.cpp` 中也有 `32`，但不是共享常量。

建议：

- quickshell TahoeGlass module 内定义 `constexpr qsizetype MaxRegionsPerSurface = 32;`
- fallback 和 protocol commit 共用同一常量。
- 注释说明必须与 niri server 保持一致。

验收：

- quickshell TahoeGlass 不再有散落的裸 `32` region limit。
- 行为不变。

完成后才能开始：T9。

### T9：niri TahoeGlass 协议测试

目标：

- 给 server 侧 region validation 和 commit 语义加最小测试。

范围：

- niri tests。
- 不改渲染视觉。

测试场景：

1. 合法 region commit 后可读取 committed regions。
2. width/height <= 0 被丢弃。
3. 负 radius 被丢弃。
4. 超出 surface geometry 的 region 被丢弃。
5. region 总数超过 32 时被限制。
6. repeated same region 不产生多余变化。

验收：

- 测试覆盖协议输入校验。
- 不依赖真实 GPU。
- 不改变 compositor runtime 行为。

完成后才能开始：T10。

### T10：niri foreign_toplevel 保持为唯一窗口动作协议

目标：

- 防止未来为 Dock/TaskSwitcher 又创建一套窗口 action 接口。

范围：

- 文档/guardrail。
- 可选测试补充。

规定：

- minimize/restore rectangle 继续走 `wlr foreign-toplevel set_rectangle`。
- activate/close/maximize/minimize 优先走现有 toplevel 能力。
- 不新增 Tahoe 私有 Wayland protocol 来控制普通窗口。

验收：

- 文档写明窗口动作接口复用策略。
- 新功能计划引用该策略。

完成后才能开始：T11。

### T11：niri_settings_tool.py fixture/golden tests

目标：

- 保护手写 KDL 编辑器，防止设置功能扩展时破坏配置。

范围：

- Python tests 和 fixtures。
- 不改设置面板 UI。
- 不改 KDL 输出格式，除非测试明确允许。

测试场景：

1. read 当前 `config/niri/tahoe-phase0.kdl`。
2. 修改 TahoeGlass material 单字段，保留其它 material。
3. 修改 blur 开关，保留注释和未知字段。
4. 修改 input 设置，保留 unrelated blocks。
5. round-trip 后再次 read 结果一致。
6. invalid config 返回明确错误，不写半截文件。

验收：

- 有 golden fixtures。
- 设置读写关键域有覆盖。
- 后续新增设置项必须先加 fixture。

完成后才能开始：T12。

### T12：Controls.qml 服务边界拆分

目标：

- 降低控制中心服务层的变更冲突和性能风险。

范围：

- 只拆服务数据层。
- 不改 ControlCenter 视觉。
- 不改 QML 外部字段名，或提供兼容转发。

拆分顺序：

1. Wi-Fi 子服务。
2. Bluetooth 子服务。
3. Media 子服务。
4. Brightness 子服务。
5. Audio 子服务。

每次只拆一个子服务。拆完一个并验收后，才能拆下一个。

验收：

- 控制中心所有现有控件仍能读取旧字段。
- 单个子服务失败不会使整个 Controls 服务不可用。
- 外部命令/process 有集中错误处理。

完成后才能开始：T13。

### T13：shell overlay 状态协调器

目标：

- 从 `shell.qml` 中抽出互斥面板、dismiss、全局 overlay 状态。

范围：

- 只移动状态和命令。
- 不移动 UI 结构。
- 不改视觉。

建议：

- 新建轻量 `OverlayCoordinator.qml` 或 JS service。
- 提供：
  - `openPanel(name)`
  - `closePanel(name)`
  - `closeAllTransient()`
  - `isOpen(name)`
  - `activePanel`

验收：

- 打开控制中心、通知中心、Spotlight、Launchpad、Settings 等行为不变。
- Esc/dismiss 行为不变。
- `shell.qml` 全局布尔数量减少。

完成后才能开始：T14。

### T14：Quickshell TahoeGlass build option

目标：

- 降低 quickshell fork 面，便于未来 upstream 或最小构建。

范围：

- CMake option。
- 默认保持当前行为：ON。

建议：

- 增加 `TAHOE_GLASS` option，依赖 WAYLAND。
- ON 时行为完全不变。
- OFF 时不构建 `quickshell-wayland-tahoe-glass`，QML module 不导入。

验收：

- 默认构建不变。
- `-DTAHOE_GLASS=OFF` 可跳过 TahoeGlass module。
- Tahoe shell 生产构建仍默认启用。

完成后才能开始：T15。

### T15：部署脚本安全化

目标：

- 防止部署脚本误删本地改动。

范围：

- `scripts/arch-update.sh`。
- 不改变默认部署目标。

建议：

- 子模块 dirty 时默认中止。
- `git reset --hard` 只在显式 `--force` 或环境变量确认时执行。
- 打印将要执行的 destructive command。
- destructive command 前再次显示 repo path 和 branch。

验收：

- dirty 子模块下默认不会 reset。
- 明确 force 时才继续。
- guardrail 脚本仍默认运行。

完成后才能开始：T16。

### T16：性能观察点和轻量指标

目标：

- 为后续性能优化建立最小观察点，避免凭感觉优化。

范围：

- 日志或 debug counters。
- 不引入复杂 telemetry。

建议观察点：

- thumbnail queue 长度、成功/失败、平均耗时。
- Windows model merge 输入数量和输出数量。
- TahoeGlass region commit count。
- TahoeGlass fallback 是否触发。
- Controls 子服务 process 调用频率。

验收：

- debug 模式可观察关键热点。
- 默认用户体验不增加日志噪声。

完成后才能开始：T17。

### T17：回归文档和贡献规则

目标：

- 把维护边界写成后续开发必须遵守的规则。

范围：

- docs。
- 不改代码。

内容：

- 新 Tahoe 玻璃组件必须使用 `TahoeGlass.regions`。
- 不得直接在 Tahoe QML 中使用 `BackgroundEffect.blurRegion`，除非明确 fallback。
- 窗口动作走 existing toplevel/foreign_toplevel。
- thumbnail 走统一 provider。
- 新设置项必须加 KDL fixture。
- 新全局 overlay 状态必须进 coordinator，不直接塞进 `shell.qml`。
- 新外部命令必须有失败 fallback 和调用频率控制。

验收：

- 文档存在。
- 后续 roadmap 引用该规则。

完成后路线图第一轮结束。

## 局部重构优先级

优先级从高到低：

1. Guardrails：XML drift、版本、KDL fixtures。
2. 数据契约：Windows model source-of-truth。
3. 性能边界：thumbnail provider queue。
4. 生命周期复用：Quickshell attached Wayland helper。
5. 服务拆分：Controls 子服务。
6. 全局状态收敛：OverlayCoordinator。
7. 构建可选项和部署安全。

不建议优先做：

- 全面重写 `Windows.qml`。
- 全面重写 `Controls.qml`。
- 把 TahoeGlass 合并进 BackgroundEffect。
- 新增更多 Wayland 私有协议解决窗口动作或 thumbnail。
- 引入复杂事件总线。

## 接口复用规则

后续新增功能时必须先查是否已有通道：

| 能力 | 应复用接口 | 禁止方向 |
| --- | --- | --- |
| 玻璃 region / material / shadow / clip | TahoeGlass | 新建第二个玻璃协议 |
| 普通 blur fallback | BackgroundEffect | Tahoe QML 直接散落 blurRegion |
| 窗口 activate/close/minimize/rectangle | foreign_toplevel / Quickshell toplevel | Tahoe 私有窗口控制协议 |
| 窗口列表、workspace、minimized 状态 | niri IPC + documented fallback | 任意组件自行拼 model |
| 窗口缩略图 | niri IPC `window-thumbnail` + shell provider | screencopy 或新 Wayland thumbnail 协议 |
| 设置读写 | `niri_settings_tool.py` + fixtures | 组件直接字符串替换 config |
| overlay 互斥状态 | OverlayCoordinator | 继续往 `shell.qml` 加全局布尔 |

## 每个任务的完成定义

一个任务只有同时满足以下条件才算完成：

1. 当前任务目标达成。
2. 没有引入无关重构。
3. 没有改变用户可见行为，除非任务明确要求。
4. 相关 guardrail/test 已运行。
5. 失败路径有 fallback 或明确错误。
6. 文档或注释更新到能解释维护边界。
7. `git diff` 可读，改动范围和任务一致。

## 建议第一轮执行顺序

第一轮只做低风险维护基础，不碰视觉重构：

1. T0 维护基线。
2. T1 TahoeGlass XML drift guard。
3. T2 TahoeGlass 版本护栏。
4. T3 Windows 字段来源契约。
5. T4 Windows merge 测试化。
6. T5 thumbnail provider queue。
7. T6 thumbnail path 安全边界。

第一轮完成后，再评估是否进入 C++ lifecycle helper 和服务拆分。这样风险最低，也最符合 KISS：先保护接口和行为，再动结构。

## 最终判断

当前项目不需要大规模重构，也不需要减少 Wayland 协议数量。需要的是把几个已经成型的私有能力固定下来，防止后续功能绕过它们：

- TahoeGlass 是唯一玻璃协议。
- foreign_toplevel 是窗口动作和 rectangle 的复用入口。
- niri IPC thumbnail 是唯一窗口缩略图入口。
- Windows model 必须有明确 source-of-truth。
- 设置写入必须有 fixture/golden tests。
- Quickshell lifecycle 重复只做局部 helper。

按这个路线推进，可以在不破坏现有功能的前提下，提高长期维护性，降低腐化速度，并解决最明显的性能扩展风险。
