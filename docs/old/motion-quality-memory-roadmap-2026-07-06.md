# Tahoe 动画质感、曲线调参、材质性能与内存管理研究路线图

日期：2026-07-06

状态：研究文档兼改进路线图。本文基于本地源码静态阅读，不代表已经完成实现或实机性能验收。

## 目标

把当前 Tahoe / niri 项目中“动画不够丝滑、曲线不方便调、玻璃质感与内存占用还需要跟上”的问题，收敛为一条可执行、可回滚、可验收的路线图。

本路线图采用严格串行策略：完整完成一个任务并通过验收记录后，才能开始下一个任务。不得在一个任务中顺手完成后续任务。

## 非目标

- 不重写 niri 动画系统。
- 不重写 Tahoe Shell。
- 不新增与现有能力平行的 Wayland protocol、IPC daemon、配置格式或设置服务。
- 不为了调参方便绕过现有 KDL、`NiriSettings.qml`、`niri_settings_tool.py`、`DesktopSettings.qml`。
- 不在没有测量基线的情况下提高 blur、chromatic、refraction 或全局材质强度。
- 不把 nested winit 后端的动画体感当作最终判断，真实体感以 DRM/TTY 会话为准。
- 不删除现有 fallback 和回退开关，除非单独任务完成验收并记录。

## 硬约束文档

本节是后续所有实现任务必须遵守的约束。任何任务如果需要违反其中一条，必须先修改本文档并说明原因、风险和回滚方式。

### 严格串行

1. 一个任务只解决一个明确问题。
2. 当前任务必须完成实现、验证、记录，才能进入下一个任务。
3. 验收失败时，只能在当前任务内修复或修改当前任务目标，不能跳到后续任务。
4. 每个任务都必须能单独回滚。
5. 不允许“顺手重构”“顺手迁移”“顺手删旧路径”。

### 反腐化

1. 优先复用现有接口，再考虑扩展接口。
2. 不重复创造功能平行接口。
3. 不把 Tahoe 私有能力伪装成通用上游 API。
4. 新增抽象必须减少真实重复或固化明确边界，不能只为了“看起来更架构化”。
5. 状态来源必须唯一且可解释；不得让同一设置同时由多个服务、文件或 helper 写入。
6. 可写能力必须真实可写；read-only 状态不能包装成开关。
7. 视觉参数和动效参数必须有 source of truth，不能在多个文件中各自漂移。

### 必须优先复用的现有接口

| 领域 | 必须优先复用 | 禁止新增的平行能力 |
| --- | --- | --- |
| niri 动画配置 | `niri/niri-config/src/animations.rs`、`config/niri/tahoe-phase0.kdl`、现有 `layer-rule animations` | 第二套动画配置文件、第二套 KDL parser、Tahoe 专用 Rust namespace 分支 |
| 设置读写 | `tahoe-shell/services/NiriSettings.qml`、`tahoe-shell/services/niri_settings_tool.py` | 新 Python 配置编辑器、组件内直接改 KDL、临时 shell sed 写配置 |
| Shell 持久化 | `DesktopSettings.qml` 和已有 state JSON | 每个组件自建设置文件、环境变量开关 |
| QML motion token | `tahoe-shell/components/Motion.js`、`DynamicIslandMotion.js` | 每个组件自建 motion 常量文件、硬编码 duration/curve 继续扩散 |
| Glass material | `TahoeGlass.js`、`tahoe-material-governance.md`、`config/niri/tahoe-phase0.kdl`、`niri-config/src/tahoe_glass.rs` | 组件内直接写 raw shader 参数、随手新增 material 名称 |
| 窗口缩略图 | `ThumbnailProvider.qml` 和 niri IPC `window-thumbnail` | 组件内直接 spawn `niri msg window-thumbnail`、新截图协议、第二套 thumbnail queue |
| 性能追踪 | 已有 Tracy span、`RUST_LOG`、niri render helpers 现有 instrumentation | 新增常驻采样 daemon、未验证的全局 profiler 依赖 |

### 接口新增门槛

只有同时满足以下条件，才允许新增接口：

1. 现有接口无法表达该能力，并且已经在文档中列出缺口。
2. 新接口不会与已有能力并行竞争。
3. 新接口有明确 owner、source of truth、测试和回滚方式。
4. 新接口的第一版只服务一个已验收任务，不能预留过度泛化能力。

## 当前研究结论

### 动画底层能力不是主要短板

niri 侧已经有完整的动画基础：

- `Animation` 支持 easing 和 spring：`niri/niri-config/src/animations.rs`。
- 已支持 `linear`、`ease-out-quad`、`ease-out-cubic`、`ease-out-expo`、多组命名 cubic-bezier 和任意 `cubic-bezier`。
- layer open/close 已拆分 transform 和 opacity channel。
- redraw 时使用 `FrameClock::next_presentation_time()` 冻结动画采样时间，采样设计是正确方向。

当前问题更接近产品化和调参体验问题：参数散在 compositor KDL、QML token、组件硬编码和设置页之间，没有统一 profile 和可视化曲线预览。

### QML motion 仍然碎片化

已有 `Motion.js` 和 `DynamicIslandMotion.js`，但仍有大量组件直接写：

- `NumberAnimation { duration: 140; easing.type: Easing.OutCubic }`
- `ColorAnimation { duration: 120 }`
- 局部 `Timer` 驱动的视觉节奏

这会造成三个问题：

1. 同一类动作在不同 surface 上节奏不一致。
2. 调一条曲线不能同步影响完整体验。
3. 后续 motion profile UI 很难覆盖 QML 内部微动效。

### 设置页覆盖面不足

当前 `NiriAnimationsPage.qml` 主要暴露四类 spring 参数：

- `workspace_switch`
- `window_movement`
- `window_resize`
- `overview_open_close`

但 panel/popup 手感主要由以下参数决定：

- layer open/close style
- transform duration
- opacity duration
- transform curve
- opacity curve
- scale / distance / opacity 起终点
- QML 内部 motion token

这些现在没有统一调参入口。

### `edge-reveal distance` 语义容易误导

当前 KDL 中 `edge-reveal` 配了 `distance 18` 或 `distance 24`，但实现上 edge reveal 会按 surface 完整宽/高移动，测试也确认 close edge reveal 应该完整 retract surface，而不是停在短 distance。

这不是立即要定性的 bug，但它是调参体验问题：用户看到 `distance` 会以为它影响 edge reveal 手感，实际主要不生效。后续必须选择：

1. 在 UI/文档中隐藏或解释该字段；或
2. 新增明确语义的 `edge-slide` / `short-reveal` 样式，让 distance 真正参与短位移动画。

### glass 渲染已有缓存，但缺少预算

`EffectBuffer` 和 `FramebufferEffect` 已经在复用 offscreen、framebuffer、blur texture 和 damage storage。TahoeGlass protocol 也有限制：

- 每个 surface 最多 32 个 region。
- committed region 总面积不能超过 surface area。

真正风险不是“完全没缓存”，而是大面积 TahoeGlass / BackgroundEffect 在动画帧中持续 framebuffer capture + blur pass。必须先建立可观测预算，再谈增强质感。

### 内存和高频分配需要先测量再优化

明确可见的小热点：

- `XrayElement::draw()` 每次 draw 都新建 filtered damage `Vec`，代码已有 FIXME。
- `ThumbnailProvider.qml` 每次 cache 更新复制 JS object，且每个 job 通过外部 `niri msg window-thumbnail` 进程执行。
- close snapshot、blur texture、offscreen texture 的生命周期需要用实测确认动画结束后及时释放。

这些不一定是最大头，但都适合在测量后做局部修复。

## 路线图总规则

每个任务完成时都必须写一份验收记录，建议命名：

```text
docs/motion-quality-memory-taskXX-acceptance-YYYY-MM-DD.md
```

验收记录至少包含：

- 修改范围。
- 是否遵守本文硬约束。
- 使用或扩展了哪些现有接口。
- 没有新增哪些平行接口。
- 运行的命令。
- 未完成风险。
- 回滚方式。

## 任务 0：建立真实基线

目标：在不改行为的情况下，记录当前动画、glass、内存和调参入口的事实基线。

范围：

- 真实 DRM/TTY 会话下记录常用 surface open/close 体感。
- 记录 nested winit 与 DRM/TTY 的差异，但不以 winit 作为最终判断。
- 记录当前 QML 硬编码动画分布。
- 记录 TahoeGlass region 面积、数量、动画期间是否持续重绘。
- 记录进程 RSS、niri frame time、Quickshell RSS、thumbnail queue 行为。

必须复用：

- `niri msg --json layers`
- `RUST_LOG`
- Tracy span
- 现有 shell IPC 或手动触发入口

禁止：

- 不修改 motion 参数。
- 不改 QML 动画。
- 不新增测试专用协议。

验收：

- 生成 task0 验收文档。
- 至少覆盖 Control Center、Notification Center、Small Popup、Spotlight、Toast、Dock、Window Overview、Task Switcher。
- 明确哪些场景无法自动触发，以及原因。

完成后才能开始任务 1。

## 任务 1：梳理 motion source of truth

目标：定义 Tahoe motion profile 的唯一来源和映射关系，先文档化，不急着写 UI。

范围：

- 列出现有 compositor motion 参数。
- 列出现有 QML token。
- 列出硬编码 QML 动画。
- 定义第一版 profile：例如 `fast`、`balanced`、`liquid`、`reduced`。
- 定义每个 profile 对应的 transform/opacity duration、curve、QML token。

必须复用：

- `Motion.js`
- `DynamicIslandMotion.js`
- `config/niri/tahoe-phase0.kdl`
- `NiriSettings.qml`
- `niri_settings_tool.py`

禁止：

- 不新增第三个 motion token 文件。
- 不让组件直接读 profile JSON。
- 不把 profile 写死进 niri Rust。

验收：

- task1 文档列出 profile 表。
- 每个 profile 都能映射到现有 KDL/QML 能力。
- 明确哪些能力无法表达，作为后续任务输入。

完成后才能开始任务 2。

## 任务 2：补齐可重复触发与采样入口

目标：让后续调参能稳定复现 open/close、快速 toggle、打断动画，而不是靠手动点击。

范围：

- 优先复用已有 Tahoe IPC / shell 函数。
- 如果缺入口，只扩展现有 shell IPC 路由，不新增 daemon 或协议。
- 为 Battery/Wi-Fi/Control Center/Notification Center/Spotlight/Toast 提供可重复触发路径。
- 采样 `niri msg --json layers` 和截图时间点。

禁止：

- 不新增 Wayland protocol。
- 不新增第二套 shell 控制服务。
- 不把测试入口留成用户可见功能，除非已有类似 IPC 语义。

验收：

- 能自动执行 open、close、快速 toggle。
- 验收文档记录每个 surface 的触发命令。
- 失败路径有明确说明。

完成后才能开始任务 3。

## 任务 3：曲线预览与 sampler

目标：解决“曲线动画手感调起来不方便”的问题，先做可视化和采样，再做写入。

范围：

- 为 cubic-bezier 显示曲线、速度趋势、关键采样点。
- 为 spring 显示 settle time、overshoot、响应曲线。
- 对 niri 支持的 named curves 做只读展示。
- 标注 non-monotonic 或 overshoot 曲线的风险。

必须复用：

- `NiriAnimationsPage.qml`
- `NiriSettings.qml`
- 现有 `animations.rs` 曲线命名

禁止：

- 不新增独立调参 App。
- 不新增第二套曲线定义表，除非由现有曲线表生成或显式镜像并加测试。
- 不在预览阶段写 KDL。

验收：

- 设置页能预览当前曲线，但不改变配置。
- 预览结果与 niri cubic-bezier 语义一致，至少有采样测试或人工比对记录。
- 文档列出推荐曲线使用场景。

完成后才能开始任务 4。

## 任务 4：QML motion token 收敛

目标：减少 QML 动画碎片化，让内部微动效和 compositor layer 动画共享同一 motion vocabulary。

范围：

- 把常见硬编码 duration/easing 迁到 `Motion.js` 或 `DynamicIslandMotion.js`。
- 按语义命名 token：panel enter、panel exit、element move、element resize、fade fast、menu enter、menu exit。
- 保留特殊组件的局部例外，但必须注释原因。

禁止：

- 不改变用户可见行为，除非任务明确列出。
- 不把所有数值机械统一成一个 duration。
- 不移动组件结构。

验收：

- `rg "NumberAnimation|ColorAnimation|Easing.OutCubic"` 的结果明显减少，并记录剩余例外。
- 常用 surface 视觉行为保持一致。
- 没有新增 motion token 文件。

完成后才能开始任务 5。

## 任务 5：motion profile 写入模型

目标：把 profile 从文档变成可应用模型，但仍然优先复用现有设置读写链路。

范围：

- 扩展 `NiriSettings.qml` 的 animation mirror，而不是新建设置服务。
- 扩展 `niri_settings_tool.py`，让它能写 layer profile 所需字段。
- profile 应用到 KDL 中现有 `animations` 和 `layer-rule animations`。
- QML token profile 通过现有 shell settings 或 central token 入口生效。

禁止：

- 不新建 KDL 写入工具。
- 不让 QML 组件直接编辑 `config.kdl`。
- 不引入 profile JSON 作为第二配置源，除非它只是生成 KDL/QML token 的内部表并有同步测试。

验收：

- 设置页可以选择 profile 并写入现有配置路径。
- 热重载后 niri 配置生效。
- 回滚到旧 profile 可用。
- 验收文档记录具体写入字段。

完成后才能开始任务 6。

## 任务 6：修正 edge-reveal 调参语义

目标：消除 `edge-reveal distance` 的调参误导。

选择一条路径执行，不能两条同时做：

路径 A：保留当前 edge reveal 语义。

- UI 隐藏 `distance` 或显示为“不影响完整 edge reveal retract”。
- 文档说明 edge reveal 按 surface 完整宽/高移动。
- 保持现有测试。

路径 B：新增短距离样式。

- 新增 `edge-slide` 或 `short-reveal`，明确 `distance` 生效。
- 保留现有 `edge-reveal` 完整 retract 行为。
- 添加解析测试、动画状态测试、视觉验收。

禁止：

- 不悄悄改变 `edge-reveal` 现有行为。
- 不破坏 `layer_close_edge_reveal_moves_full_surface_extent` 的语义，除非先迁移测试和文档。

验收：

- 用户在设置页或文档里不会再误以为 `edge-reveal distance` 是短滑动距离。
- 如果新增 style，必须有完整测试和回滚说明。

完成后才能开始任务 7。

## 任务 7：close/open 连续性修复

目标：解决关闭闪透明、double fade、快速 toggle 接管感明显的问题。

范围：

- 检查 close snapshot 捕获时的 alpha、scale、offset 起点。
- 快速 close 打断 open 时，close 应从当前视觉状态开始。
- open 打断 close 时，旧 snapshot 必须取消或被新 live surface 接管。
- opacity 和 transform channel 不应造成 double alpha。

必须复用：

- `opening_layer.rs`
- `closing_layer.rs`
- `mapped.rs`
- 现有 layer animation test fixture

禁止：

- 不引入 shader 解决基础连续性问题。
- 不通过延长动画 duration 掩盖闪烁。
- 不把 QML 外层动画重新叠回 compositor 动画路径。

验收：

- 快速 toggle 10 次无残影、无长期 repaint。
- open interrupt close 和 close interrupt open 有测试或截图记录。
- snapshot 动画结束后 texture 不留在 active list。

完成后才能开始任务 8。

## 任务 8：glass 与材质性能预算

目标：在不牺牲稳定性的前提下提升质感，并为 blur/glass 成本建立硬预算。

范围：

- 记录每帧 TahoeGlass region 数量、面积、sample padding、blur pass。
- 记录 `FramebufferEffectElement::capture_framebuffer` 和 blur render 时间。
- 建立大 surface 动画期间的材质预算。
- 只在测量后调整材质参数。

必须复用：

- `FramebufferEffect`
- `EffectBuffer`
- `TahoeGlass.js`
- `tahoe-material-governance.md`
- 现有 Tracy span

禁止：

- 不新增 static blur 路径来绕开测量。
- 不默认提高 chromatic/refraction。
- 不按 GPU 自动切换材质策略，除非另开路线图。
- 不新增 material token，除非现有七个 token 无法表达。

验收：

- 有 baseline 和调整后对比。
- 动画期间 frame time 不劣化到不可接受。
- 材质变更同步 TahoeGlass.js、KDL、Rust defaults、设置 mirror 和治理测试。

完成后才能开始任务 9。

## 任务 9：内存与高频分配治理

目标：在有测量依据后处理明确内存和高频分配问题。

范围：

- 修复 `XrayElement::draw()` 中 filtered damage `Vec` 高频分配。
- 检查 close snapshot 生命周期和释放时机。
- 检查 `FramebufferEffect` / `EffectBuffer` texture 重建原因。
- 优化 `ThumbnailProvider.qml` cache 更新和队列行为。

必须复用：

- 现有 thumbnail provider。
- 现有 niri IPC `window-thumbnail`。
- 现有 render element cache。

禁止：

- 不给每个组件新增 thumbnail 请求逻辑。
- 不新增第二套图片缓存目录。
- 不为了省内存牺牲失败 fallback。

验收：

- 记录优化前后 RSS、thumbnail burst、动画场景内存趋势。
- `XrayElement` 修复有局部测试或明确人工验证。
- thumbnail queue 不出现组件各自 spawn 进程。

完成后才能开始任务 10。

## 任务 10：默认策略与回退整理

目标：在动画、曲线、材质、内存都验收后，再决定默认策略和是否整理旧路径。

范围：

- 决定默认 motion profile。
- 决定是否默认启用 compositor layer animation。
- 决定旧 QML 外层显隐路径是否继续保留。
- 更新设置页文案、文档和故障排查说明。

禁止：

- 不在任务 10 之前删除 fallback。
- 不在任务 10 之前改变默认开关。
- 不删除用户可见入口。

验收：

- 默认策略有基线数据支持。
- 回退路径可用。
- 用户可以在设置页恢复保守 profile。
- 所有相关文档更新。

## 推荐验收命令

按任务选择运行，不要求每个任务都全跑。

```bash
python3 tahoe-shell/services/niri_settings_tool.py read --config config/niri/tahoe-phase0.kdl
bash scripts/check-tahoe-glass-guardrails.sh
python3 -m pytest tahoe-shell/tests/test_tahoe_material_governance.py
cargo test --manifest-path niri/Cargo.toml -p niri-config
cargo test --manifest-path niri/Cargo.toml -p niri layer_shell
```

实机会话观察建议：

```bash
RUST_LOG=niri=debug niri --session
niri msg --json layers
```

如果启用 Tracy，至少标注以下 span：

- layer open/close render
- closing snapshot capture
- framebuffer capture
- blur render
- TahoeGlass region render
- thumbnail request burst

## 关键决策记录

1. 先做测量，再调材质。
2. 先做曲线预览，再做曲线写入。
3. 先收敛 QML token，再做 profile UI。
4. 先修 close/open 连续性，再追求更夸张的 liquid 动效。
5. 先复用现有接口，再讨论新增接口。
6. `edge-reveal` 当前完整 retract 语义不能被悄悄改变。
7. window thumbnail 继续走现有 provider 和 niri IPC，不新增协议。
8. TahoeGlass material vocabulary 继续受治理文档约束。

## 后续维护规则

后续任何实现任务完成后，都必须在本文对应任务下补充：

- 完成日期。
- 验收文档路径。
- 关键 commit 或变更摘要。
- 剩余风险。

如果某个任务被拆分，必须保留串行顺序，不能把拆分后的子任务并行推进。
