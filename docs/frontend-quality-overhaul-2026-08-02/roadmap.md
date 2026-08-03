# Tahoe Desktop 修复与质量改进路线图

**状态**：待执行
**基线**：主仓库 `78dc847`，niri `0cf398c4`，Quickshell `5a984c7`
**任务总数**：24
**执行规则**：严格按 T01 -> T24 串行；任一任务未完成、未双审查、未 commit/push，不得开始下一项
**约束权威**：`CONSTRAINTS.md`

---

## 1. 目标与非目标

本路线图负责修复 `research-report.md` 中有充分证据的问题，并用可判定门禁研究架构改进。目标是：

- 消除已确认的 compositor/shell 生命周期缺陷、崩溃路径和当前 QML 告警。
- 让几何、动画完成和异步操作各自只有一个 authority。
- 降低动画期间的纹理分配、重复捕获、QML 分配和无预算重试。
- 统一现有主题、控件、popup、键盘与 Accessibility 行为。
- 建立热插拔、240 Hz、fractional scale、长时内存和失败恢复的回归机制。

本路线图不授权新增产品功能、设置项、主题、动画 profile、快捷方式、页面、后台服务或实验开关。不得创建第二套 Motion、Theme、TahoeGlass、FileView、CommandRunner 或 PopupGeometry 接口。

---

## 2. 严格顺序

| 顺序 | 任务 | 主要仓库 | 依赖 | 完成判据 |
|---|---|---|---|---|
| T01 | output layer teardown 闭环 | niri | 无 | 重复 hot-plug 后无残留 mapped layer/hook |
| T02 | window/output 生命周期 panic 清理 | niri | T01 | dialog 与 stale redraw 路径不 panic，行为保持 |
| T03 | layer map 锁边界与 damage/redraw 归因 | niri | T02 | 无长 guard、无无界 damage、root 归因正确 |
| T04 | pointer 缓存与 focus transaction | niri | T03 | 不重入锁且所有输入路径坐标/焦点正确 |
| T05 | thumbnail 主循环预算 | niri | T04 | 请求限流/合并/缓存且主循环有延迟上限 |
| T06 | QsPaths 失败状态机 | Quickshell | T05 | 所有目录失败组合无无效指针 |
| T07 | FileView 非阻塞写状态机 | Quickshell | T06 | writer 取消/替换不阻塞 GUI |
| T08 | TahoeGlass mapping 生命周期 | Quickshell + shell | T07 | Dock 当前告警消失，remap 正确重放 |
| T09 | TahoeGlass 完成/拒绝反馈 | niri + Quickshell + shell | T08 | 协议反馈闭环，无永久 pending morph |
| T10 | blur texture 容量复用 | niri | T09 | 尺寸动画不逐步重建、内存有界 |
| T11 | glass capture 语义收敛 | niri | T10 | padding 稳定、透明早退、归因/阴影正确 |
| T12 | 每输出共享 backdrop 证据门禁 | niri | T11 | 达标则单路径替换；不达标则证据关闭 |
| T13 | 线性光与高精度 blur 证据门禁 | niri | T12 | 质量收益可量化且 capability 回退等价 |
| T14 | 灵动岛单一几何 driver | shell + niri | T13 | 零 binding loop、retarget C1 连续 |
| T15 | 灵动岛交互/退场状态机 | shell | T14 | press/swipe/OSD/mask/reduced 语义一致 |
| T16 | shell active-state 工作预算 | shell | T15 | 240 Hz、监视器与 IPC 有明确预算 |
| T17 | 主题、材质与字体 authority | shell | T16 | 所有生产 surface 使用现有统一 tokens |
| T18 | 共享控件键盘与 Accessibility | shell | T17 | 控件层完整契约、无键盘旁路控件 |
| T19 | popup 几何、滚动与焦点闭环 | shell | T18 | 全分辨率可达、关闭后焦点恢复 |
| T20 | 图标、圆角、阴影与 fallback 收敛 | shell + niri | T19 | 无空图标/伪装图标，视觉规则一致 |
| T21 | 异步操作真实完成状态 | shell | T20 | Power/Search/Appearance 失败可恢复 |
| T22 | 日志轮转与诊断入口 | root scripts | T21 | 日志有界、诊断可定位且不泄露 |
| T23 | 多输出/混合缩放/热插拔整体验收 | niri + shell | T22 | lifecycle 与 Genie 跨输出行为确定 |
| T24 | 全量回归、长时 soak 与收尾 | 全部 | T23 | 所有矩阵通过、无未裁决问题 |

任务只能按上表顺序进入 `IN_PROGRESS`。`RESOLVED-NO-CODE` 也必须完成证据、双审查、commit 和 push，才算完成。

---

## 3. 全任务共同验收

每个任务除专属验收外，还必须满足：

- `G01`：当前任务的同类 symbol/调用点全仓搜索完成，未改点逐一解释。
- `G02`：没有新增功能重叠接口、长期 feature flag 或第二 authority。
- `G03`：受影响仓库专项测试与全量测试通过；既有红项必须证明与本任务无关。
- `G04`：缺陷测试在旧实现失败、在新实现通过，或有等价的确定性 A/B 证据。
- `G05`：两个独立只读子代理对最终 diff 给出 `CLEAN`，所有中间 finding 已闭合。
- `G06`：commit/push 顺序、remote ancestor 和主仓库子模块指针验证通过。
- `G07`：`execution-log.md` 包含前提、改动、验收、审查、未覆盖和 push receipt。
- `G08`：未触碰范围外用户改动，未重启实时会话，未执行真实电源操作。

---

## 4. 任务定义

## T01 output layer teardown 闭环

**对应发现**：STAB-01。
**目标**：让 output removal 成为一个完整事务，在 output 离开 layout 前释放其 layer-shell 映射和所有 Tahoe/foreign 状态。

**必须机制**：

- 原地重构 `Niri::remove_output()`、现有 layer-shell teardown helper 和 `mapped_layer_surfaces` ownership。
- 锁内只收集必要对象/geometry；close、snapshot、foreign rect、Tahoe directive 和 hook 清理的顺序必须显式。
- output 已不可渲染时不得为追求 close 动画保留旧 output 强引用；应定义取消或无动画销毁语义。
- 不新增 `mapped_layer_surfaces_v2`、第二张索引表或专用 hot-plug 旁路。

**验收**：

- `A01.1`：映射至少两个 layer，移除 output，再模拟 null commit 和 destroy；map、pre-commit hook、foreign rect、Tahoe transform 均为空。
- `A01.2`：重复 100 次虚拟 output add/remove，持有数量回到基线且无线性增长。
- `A01.3`：移除最后 output、非最后 output、layer 已 unmap、client 不响应 close 四种次序均不 panic。
- `A01.4`：保留正常 layer unmap/destroy 的 close snapshot 行为。
- `A01.5`：niri 全量 lib 测试、fmt、check 通过。

## T02 window/output 生命周期 panic 清理

**对应发现**：STAB-02、STAB-03。
**目标**：消除最小化父窗口创建 dialog 和 stale output redraw 的 panic，同时保持窗口放置与 redraw 语义。

**必须机制**：

- 先用父/子 toplevel 拓扑复现 `active_window() == None`；修复应选择合法 placement owner，而非 early return 丢窗口。
- 对 output callback 使用现有 output existence/state authority，明确 stale callback 是丢弃、重归因还是取消。
- 全仓检查同类 `active_window().unwrap()` 与 `output_state.get_mut(...).unwrap()`；只修改具有同一失效前提的调用点。
- 不引入 `queue_redraw_safe()` 与旧 `queue_redraw()` 长期并存；如需签名变化，迁移全部调用者。

**验收**：

- `A02.1`：最小化父窗口后创建 transient dialog，dialog 可见、位置合法、会话不 abort。
- `A02.2`：父窗口恢复、floating/scrolling、父窗口销毁并发场景行为明确。
- `A02.3`：排队 redraw 后移除 output，回调到达不 panic，也不错误重绘其他 output。
- `A02.4`：所有同类 unwrap 均有不变量证明或被修复。
- `A02.5`：现有窗口 placement/fullscreen/minimize 测试保持通过。

## T03 layer map 锁边界与 damage/redraw 归因

**对应发现**：STAB-04、GLASS-02 中 damaged regions 与 root attribution。
**目标**：缩短 Smithay layer-map mutex 持有范围，保证 damage 有界并把 Tahoe redraw 归因到正确 root/output。

**必须机制**：

- 把 layer map 读写阶段与 renderer、规则、foreign rect、callback 阶段结构分离；不得在 guard 存活时进入可能再次取 layer map 的函数。
- `damaged_regions` 必须有明确所有者、上限与在不可渲染/锁屏/DPMS/empty regions 时的排空规则。
- redraw 接受任意 surface 时先解析既有 root；失败策略必须显式，不得默认全输出而不记录原因。
- 不创建平行 damage queue 或第二 redraw API。

**验收**：

- `A03.1`：测试/静态 guard 证明 layer map guard 不跨渲染、IPC、output lookup 和回调边界。
- `A03.2`：锁屏/DPMS/不可见 layer 下连续 10,000 次 region commit，damage 存储保持有界并可恢复。
- `A03.3`：subsurface/root/unmapped/destroyed surface 的 redraw attribution 各有确定结果；多输出不退化为无理由全量 redraw。
- `A03.4`：TSAN 可用时运行相关测试；不可用时记录并提供确定性重入 harness。
- `A03.5`：glass guardrail 与 niri 全量测试通过。

## T04 pointer 缓存与 focus transaction

**对应发现**：STAB-07 的保护不变量、旧报告 R-3/R-6。
**目标**：在不重新引入 PointerInternal 重入的前提下，使缓存位置和 on-demand focus 清理覆盖全部输入生命周期。

**必须机制**：

- 枚举 mouse motion、warp、output move、tablet axis、touch/grab 结束等所有会改变有效 pointer/interaction location 的路径。
- 只保留一份位置 authority；若不同设备语义不同，应在现有 input state 内表达设备来源，不得复制 `pointer_pos2`。
- 把无作用域裸 bool focus-clear 改为与 button/seat/surface 生命周期绑定的现有 transaction/state。
- 保留历史 deadlock 修复：回调内不得查询 Smithay current_location。

**验收**：

- `A04.1`：mouse、IPC warp、tablet、touch 后 cursor image redraw/拾色使用正确 output 坐标。
- `A04.2`：多按键交错、surface destroy、lock、VT switch、grab cancel 后 focus transaction 不遗留。
- `A04.3`：历史 cursor_image/on_ungrab deadlock harness 继续通过。
- `A04.4`：多输出 scale/transform 下缓存坐标转换正确。
- `A04.5`：无第二位置缓存 authority。

## T05 thumbnail 主循环预算

**对应发现**：旧报告 STAB-05。
**目标**：让窗口缩略图请求不会通过同步 GPU readback 无限阻塞 compositor 主事件循环。

**必须机制**：

- 保持现有 IPC request/response 语义；在内部建立有界 latest-wins、去重、缓存和尺寸预算。
- GPU readback 完成所有权必须明确；取消/客户端断开后资源可回收。
- 不新增第二个 thumbnail IPC，也不降低图像正确性来隐藏延迟。

**验收**：

- `A05.1`：同窗口突发 1,000 请求时 in-flight/queued 数量有硬上限，重复请求合并。
- `A05.2`：客户端断开、窗口销毁、output 移除、renderer reset 后无泄漏或 use-after-free。
- `A05.3`：4096x4096 上限请求期间 compositor event-loop latency 有测量上限，普通 pointer/frame 继续推进。
- `A05.4`：缩略图像素、尺寸、权限和错误响应与旧接口兼容。
- `A05.5`：缓存有内存上限和失效测试。

## T06 QsPaths 失败状态机

**对应发现**：STAB-05。
**目标**：修正 instance/shell/base runtime directory 的现有状态机，使任何创建失败组合都只返回合法指针或 null。

**必须机制**：

- 修正 `instanceRunDir()` 检查字段，`linkRunDir()` 复用一次验证过的 base pointer。
- 枚举 Unknown/Ready/Failed 状态转换，重复调用必须幂等。
- 使用临时目录、权限失败和 mkdir 失败注入；不得依赖真实 `$XDG_RUNTIME_DIR` 损坏。
- 不新增 `safeInstanceRunDir()` 旁路。

**验收**：

- `A06.1`：base、shell、instance 三类目录各自失败及组合失败不崩溃、不创建错误 symlink。
- `A06.2`：失败后重复调用保持 Failed，不返回未初始化 QDir。
- `A06.3`：成功路径 by-id/by-pid/shell link 与现有路径兼容。
- `A06.4`：ASan/UBSan 可用构建下专项测试通过。
- `A06.5`：Quickshell build 与 ctest 全量通过。

## T07 FileView 非阻塞写状态机

**对应发现**：STAB-06。
**目标**：消除生产 GUI 线程对异步 writer 的同步等待，保持读写顺序、原子写和 QML signal 语义。

**必须机制**：

- 原地重构 FileView operation state：正在写时的新 read/write/cancel 进入有界顺序状态，由完成回调推进。
- 明确定义 latest-write、read-after-write、path change、destroy、atomic rename 和 error 传播。
- 迁移生产 QML 中依赖 `waitForJob()`/blocking flags 的调用语义；不得增加 FileViewAsync 或第二套 service。
- 慢 writer 测试必须验证 GUI heartbeat，而不仅是最终文件内容。

**验收**：

- `A07.1`：writer 阻塞 500ms 时 GUI heartbeat/timer 持续运行，任何 QML API 调用不阻塞主线程。
- `A07.2`：快速连续写只落盘定义的最终值，signal 次数和错误归属正确。
- `A07.3`：path 切换、对象销毁、取消、磁盘错误、atomic/non-atomic 两路无 UAF 或丢失未声明数据。
- `A07.4`：Wallpaper、Apps、Clipboard、Appearance 等生产调用者行为测试通过。
- `A07.5`：Quickshell ctest 和 Tahoe shell 全量测试通过。

## T08 TahoeGlass mapping 生命周期

**对应发现**：当前 Dock `undefined -> double` 告警。
**目标**：在现有 TahoeGlass QML 类型中提供真实的 per-wl_surface mapping generation/lifecycle signal，让 Dock 在每次 remap 正确重放 compositor slide。

**必须机制**：

- 先确认 Dock 注释与既有失败测试要求；不能用 `Number(undefined) || 0` 隐藏不存在的 API。
- 在现有 TahoeGlass attached/object 类型中增加其职责所需的 generation，并在真实 surface mapping 周期递增、通知。
- shell 继续读取同一 `TahoeGlass.mappingGeneration`；不得新建 Dock 专用 generation service。
- surface 未建立、重建、快速 unmap/remap 和协议不可用均有明确值。

**验收**：

- `A08.1`：当前 Quickshell 日志不再出现 Dock.qml:68 类型告警。
- `A08.2`：初次 mapping 和每次新 wl_surface generation 单调变化；同一 mapping 普通 commit 不变化。
- `A08.3`：Dock 每个 mapping 恰好重放一次 slide，input mask 与视觉位置保持现有语义。
- `A08.4`：协议不可用时走现有非 compositor slide 路径，不新增开关。
- `A08.5`：既有长期失败的 Dock mapping 测试转绿，Quickshell/Tahoe shell 全量通过。

## T09 TahoeGlass 完成/拒绝反馈

**对应发现**：GLASS-01、GLASS-02 中 `pending_dirty` 风险。
**目标**：在现有 TahoeGlass 协议族中闭合 transform/region morph 的完成、拒绝和 capability 反馈，消除客户端猜相位与永久 pending。

**必须机制**：

- 先构造永久 overflow、healable overflow、surface 后续增长、重复覆盖 morph 和 destroy 场景，判定当前 `pending_dirty` 行为。
- 按 Wayland 向后兼容规则扩展同一协议版本，使用 serial/region identity 把完成或拒绝对应到请求。
- niri、Quickshell binding 和 Tahoe shell 在同一任务内同步；`scripts/check-protocol-sync.sh` 必须通过。
- 旧协议 client 仍按旧语义工作；新 client 只暴露一套 TahoeGlass API，不得提供“legacy/new mode”用户选项。

**验收**：

- `A09.1`：永久不可能容纳的 region 在有界提交次数内被明确拒绝，不会永久阻塞后续 morph。
- `A09.2`：可治愈 overflow 在 surface 增长后完成，serial 只完成一次且不误认旧请求。
- `A09.3`：transform retarget/cancel/destroy 的 completion 状态确定，无 late event 更新已销毁 QML 对象。
- `A09.4`：v4/旧 client 兼容测试、新版本 event 测试和协议生成同步测试通过。
- `A09.5`：QML 不再通过重复实现曲线来猜已完成状态；迁移后旧 completion authority 被删除。

## T10 blur texture 容量复用

**对应发现**：PERF-01、PERF-02。
**目标**：原地改造现有 `Blur` texture pyramid，使小幅尺寸变化复用有足够容量的 texture，且增长、收缩和 renderer reset 均有界。

**必须机制**：

- 先为 debug trace 增加受控采样：surface/namespace、requested size、capacity、format、passes、reuse/reallocate 原因；默认生产日志不得每帧刷屏。
- 复用策略必须定义 capacity bucket、UV/viewport/scissor、最大尺寸、总内存配额和收缩滞后。
- format、context、pass count、shared-reference 不兼容仍必须正确重建。
- 直接改造现有 texture ownership；不得并存 `BlurPooled` 与 `Blur` 或加用户开关。

**验收**：

- `A10.1`：固定场景 surface 在连续 1px/2px/8px resize 中，重建次数由逐步重建降到有界 bucket 增长次数。
- `A10.2`：纹理比 source 大时像素采样、边缘 clamp、damage 和 viewport 正确，无旧内容泄漏。
- `A10.3`：4K -> 小尺寸 -> 4K、pass/format/context 切换和 renderer reset 均正确释放/复用。
- `A10.4`：池容量与总 bytes 有硬上限；压力测试后回落策略可验证。
- `A10.5`：相同交互 trace 的 allocation count、frame p95/p99 和 GPU error 前后对比记录。

## T11 glass capture 语义收敛

**对应发现**：GLASS-02、旧报告 G-2/G-3/G-5 与 R-2。
**目标**：让 capture geometry 只由 blur kernel/结构需求决定，透明区域不支付完整成本，阴影与 redraw attribution 符合合成顺序。

**必须机制**：

- 在 material interaction/tint 动画前解析稳定 padding；视觉参数变化不得无理由改变 capture capacity。
- `material_alpha == 0` 或最终无可见贡献时在现有 resolved plan/element 体系内早退。
- 明确 glass 是否应该捕获自己的 shadow；用固定像素基线决定绘制/捕获顺序，而非主观调整。
- surface 归因必须先解析 root；不能另加一个 glass-only redraw API。

**验收**：

- `A11.1`：hover/material fade 时 capture rect/capacity 不抖动，视觉 tint 仍逐帧更新。
- `A11.2`：alpha 0 场景捕获和 blur 次数为 0；从 0 恢复时首帧内容正确。
- `A11.3`：亮/暗壁纸上 panel 内缘无未经设计的自阴影；固定截图/像素差有基线。
- `A11.4`：root/subsurface、多输出、unmapped surface redraw 归因测试通过。
- `A11.5`：direct scanout 与 xray/非 xray 既有行为没有非任务要求的回归。

## T12 每输出共享 backdrop 证据门禁

**对应发现**：GLASS-01 的共享 backdrop `PROPOSAL`。
**目标**：判断并在满足门禁时，将同一 render target 上重复 glass 捕获/blur 收敛为一次有界共享阶段；若语义不成立，以证据关闭任务。

**先决 GO 条件，缺一不可**：

- `A12.G1`：trace 证明典型场景同一 output/render target 每帧存在至少两个语义可共享的 capture/blur。
- `A12.G2`：建立 z-order 模型，证明 background、windows、Bottom/Top/Overlay layer、glass-over-glass 的采样边界。
- `A12.G3`：共享 union/capture 的显存上限与脏区更新优于 T11 后的单 region 基线。
- `A12.G4`：没有要求保留两个用户可选渲染路径；capability fallback 隐藏在同一内部接口后。

**GO 后必须机制**：

- 复用现有 EffectBuffer/FramebufferEffect/Blur ownership，替换重复 capture stage；不得创建可长期选择的 `GlassBackdropV2`。
- backdrop key 必须包含 output、render target、context、format、scale/transform 和正确的 stack epoch。
- 每个 region 只保留 postprocess/clip 所需的独立参数，不能双重 blur。

**验收**：

- `A12.1`：GO 条件逐条有 trace/测试；不满足时按 `RESOLVED-NO-CODE` 双审查并提交证据。
- `A12.2`：GO 时，N 个可共享 region 每帧 capture/blur 从 N 收敛到 1，dirty union 只更新必要区域。
- `A12.3`：重叠 glass、workspace transition、screenshot/xray、多 GPU/render target 图像与旧语义一致或差异被明确批准。
- `A12.4`：显存上限、eviction、output remove、renderer reset 和 no-glass 帧资源回收有测试。
- `A12.5`：无用户设置、A/B flag 或长期双 authority。

## T13 线性光与高精度 blur 证据门禁

**对应发现**：旧报告 G-1/P-B `PROPOSAL`。
**目标**：用图像证据判断 8-bit 非线性 blur 的色带/暗环影响；收益明确时在同一 blur pipeline 内加入线性光和高精度中间格式。

**先决 GO 条件**：

- 固定 10-bit gradient、高对比边缘和实际壁纸场景能量化当前误差。
- renderer 能力探测覆盖目标 GPU；内存与 frame-time 增量在预算内。
- capability 不支持时的现有格式路径在同一内部接口后自动回退。

**验收**：

- `A13.1`：保存旧/新像素统计、banding 指标与线性参考；不能只给主观截图。
- `A13.2`：GO 时，decode -> blur -> postprocess -> encode 只发生一次，避免共享 xray/backdrop 二次转换。
- `A13.3`：half-float renderability/filtering 不支持时正确回退，用户可观察语义一致。
- `A13.4`：4K 多 region 显存、frame p95/p99 和功耗增量满足任务开始时记录的预算。
- `A13.5`：门禁不满足时以 `RESOLVED-NO-CODE` 关闭，不做“便宜的半套格式改动”。

## T14 灵动岛单一几何 driver

**对应发现**：MOTION-01、MOTION-02、旧报告 M-1/M-2/M-4/M-11。
**目标**：消除 `geometryRevealProgress` binding loop，让 island geometry、radius、content reveal、protocol region 和 compositor completion 从一个可重定向 driver 派生。

**必须机制**：

- 先用 QML profiler/求值 probe 还原真实 binding loop，不得照搬旧报告未经证实的闭环。
- 选择并原地改造现有 driver；删除被替代的 spring/ease/protocol completion authority。
- retarget 必须从当前位置和现有速度继续，C0/C1 连续；niri 已有解析 velocity 时不得再做 1ms 有限差分。
- surface envelope、painted capsule、input region 和 Tahoe region 的 floor/ceil 安全不变量保持。

**验收**：

- `A14.1`：启动、所有状态转换和 1,000 次随机 retarget 日志中零 binding loop。
- `A14.2`：clock/media/timer/OSD/notification 的展开、收起、反向、抢占都由一个 geometry progress authority 驱动。
- `A14.3`：retarget 前后位置与速度连续；无停一帧、内容消失重现或圆角/底色二段完成。
- `A14.4`：normal/fast/liquid/reduced profile 均满足各自完成语义，reduced 不运行隐藏动画。
- `A14.5`：fractional scale 下 painted/input/glass region 无外溢、白边或点击错位。

## T15 灵动岛交互/退场状态机

**对应发现**：MOTION-03、MOTION-04、旧报告 M-5 至 M-10/M-13。
**目标**：统一媒体、计时器、OSD、swipe、input-mask hold 和 dismiss 的交互生命周期。

**必须机制**：

- 业务 action 统一 release-inside/TapHandler commit；pressed 只负责视觉与 lease，cancel 必须可撤销。
- OSD 在退场中收到更新时从当前 opacity/offset 可逆 retarget，不得硬写端点。
- swipe 记录时间与速度，位移/速度共同决定 settle；仍使用现有状态机和 motion tokens。
- input mask hold、content exit、dismiss afterimage 从实际 profile/animation completion 派生，删除巧合相等的裸常量 authority。

**验收**：

- `A15.1`：press 后拖出、cancel、multi-touch/重复释放均不会误触发业务 action。
- `A15.2`：OSD 退场任意进度更新无 opacity/offset 跳变，租约正确延长。
- `A15.3`：快速短 flick、慢长 drag、反向、cancel、边界速度具有一致可预测结果。
- `A15.4`：视觉结束后 input mask 在同一完成信号收回，不提前透传也不超时吞点击。
- `A15.5`：四 motion profile、键鼠/触摸、媒体不可用/计时器销毁场景全覆盖。

## T16 shell active-state 工作预算

**对应发现**：PERF-03、UX-06、旧报告 R-1/M-12。
**目标**：为仅在 active 状态运行的 Canvas、监视器、窗口布局刷新和 Dock rect IPC 建立明确频率、分配和退避预算。

**必须机制**：

- Weather 使用 accumulator 固定 30/60 fps 档，复用粒子容器；不新增用户帧率设置。
- brightness monitor 在现有 Controls authority 内做 capability probe、degraded 状态和有上限指数退避；fallback poll 只有一个 authority。
- Windows 布局刷新不得使用固定 16ms 假设，应对齐现有 frame/event coalescing 机制。
- Dock rect 去重必须包含发布者语义/真实目标，消除乒乓但保持 minimize target 正确。

**验收**：

- `A16.1`：240 Hz 输出下天气模拟/paint 次数不超过选定预算，CPU/GC/功耗前后有对比；非 active 时仍为 0。
- `A16.2`：udevadm 缺失/持续失败时 spawn 频率按上限退避，fallback 稳定接管，恢复后无双 authority。
- `A16.3`：60/144/240 Hz 下窗口布局更新延迟以帧定义，不固定积累 16ms。
- `A16.4`：Dock 相同 rect 不重复发送；两个合法发布者不再互相污染缓存，Genie endpoint 保持正确。
- `A16.5`：线程、FD、Process 数和 reduced-motion 生命周期 gate 无回归。

## T17 主题、材质与字体 authority

**对应发现**：UX-01、UX-05 的字体部分。
**目标**：让所有生产 surface 和共享控件从现有主题 authority 获取语义颜色、材质和排版，消除亮/暗/强调色孤岛。

**必须机制**：

- 原地扩展并收敛 `SettingsTheme.js`/现有 settings theme authority；不得新增 ThemeV2 或并行 token 文件。
- 定义 semantic tokens：glass fill/stroke、primary/secondary/tertiary text、accent、danger、focus、disabled，以及正文/标题/微标签字体 role。
- 迁移所有生产调用点；literal 只允许品牌色、内容数据色或有证据的特殊效果，并加入治理测试。
- darkMode、accent 和 contrast 输入必须通过现有 shell/service 链传播；不新增主题或用户设置。

**验收**：

- `A17.1`：Notification、Battery、Wi-Fi、Fan、Clipboard、TaskSwitcher、Overview、Toast 与现有主题同步。
- `A17.2`：所有 Toggle/Button active state 跟随当前强调色；danger/semantic colors 不被错误重染。
- `A17.3`：正文 UI 使用统一 font family/weight/size roles；11px literal 清单归零或逐项有理由。
- `A17.4`：light/dark × 8 accent × 亮/暗壁纸快照矩阵满足可读性阈值，无暗色不透明板式回归。
- `A17.5`：治理测试阻止生产 QML 重新引入未豁免 literal 和 bypass token。

## T18 共享控件键盘与 Accessibility

**对应发现**：UX-02。
**目标**：在现有 Button、Toggle、MenuRow、Slider、Segmented、SidebarButton 等原语中建立统一指针、键盘、焦点和 Accessibility 契约。

**必须机制**：

- 原地升级共享控件，不复制 KeyboardButton/AccessibleToggle 等旁路。
- 明确 role/name/description/value/checked/enabled/action；Enter/Space、方向键、Home/End/Page、Tab/Backtab 依控件类型实现。
- focus ring 只在键盘导航时显示，并使用 T17 focus token；pointer 使用不残留 ring。
- 迁移生产交互点到共享原语；确需自定义手势的控件必须实现同等契约。

**验收**：

- `A18.1`：全 shell `Accessible.*` 不再为零，所有生产可操作元素可由 Qt accessibility tree 命名和激活。
- `A18.2`：Button/Toggle/Menu/Slider/Segmented 的键盘和 pointer 行为矩阵通过。
- `A18.3`：disabled/hidden/destroyed delegate 不进入焦点链；动态列表更新后焦点落在最近合法项。
- `A18.4`：TopBar 既有稳定 traversal 保持，打开 popup 后焦点可进入内容。
- `A18.5`：无仅供键盘使用的平行控件或第二 activation signal。

## T19 popup 几何、滚动与焦点闭环

**对应发现**：UX-03、UX-05 的滚动部分。
**目标**：所有 popup 在不同 logical size/scale 下可见、可滚动、可关闭，并在关闭后恢复触发点焦点。

**必须机制**：

- 原地扩展 `PopupGeometry` 返回 placement/top/maxHeight/origin；所有 popup 迁移到同一 geometry authority。
- 优先 anchor 下方，空间不足时上翻，再不足时高度 cap + 现有 Flickable；最小视觉高度不得超过 availableHeight。
- 为有 overflow 的视图提供一致、克制的 ScrollIndicator/ScrollBar 语义；触摸、滚轮和键盘均可达。
- ShellPopupState/PopupDismissLayer 继续拥有互斥和 outside dismiss；统一 Escape、初始焦点和关闭后 restore。

**验收**：

- `A19.1`：1366x768、1920x1080、2560x1600，scale 1/1.25/2 下所有 topbar popup 不越界。
- `A19.2`：anchor 上下空间边界、极高内容、动态 DBus menu 增长时 placement/input cutout 不跳错。
- `A19.3`：每个 popup 可仅用键盘完成主要操作并 Escape 关闭；焦点返回原 topbar entry。
- `A19.4`：滚动位置/overflow 可感知，不遮内容，不在无 overflow 时显示无意义 chrome。
- `A19.5`：outside click、afterimage、单 popup 互斥既有测试保持通过。

## T20 图标、圆角、阴影与 fallback 收敛

**对应发现**：UX-05 的图标部分、旧报告 V-6/V-8/V-9/V-10。
**目标**：在不增加新主题或资源选择功能的前提下，统一现有视觉资产、圆角层级、阴影层次和缺失资源 fallback。

**必须机制**：

- 使用现有 TahoeSymbol/icon resolver 作为唯一 authority；未知 symbol 显示明确通用 fallback，不得静默空白。
- 应用图标优先真实 system icon；未知应用使用中性通用图标，不得把多个不同应用伪装为 Finder/Safari/Messages。
- 圆角从 T17 tokens 派生并满足嵌套同心关系；不创建一套 squircle 组件与旧圆角长期并存。
- 阴影的环境层/接触层若需扩展，应在现有 niri shadow 表达中完成；先以截图/像素证据证明，不添加纯装饰效果。

**验收**：

- `A20.1`：未知 symbol、缺 icon、多个浏览器/聊天应用可区分且无空图标框。
- `A20.2`：Material/Google literal 与 Tahoe palette 混用清单完成迁移或有内容来源豁免。
- `A20.3`：panel/tile/control 嵌套圆角在所有尺寸同心，无 24 个散落 literal authority。
- `A20.4`：亮/暗背景、重叠 glass、禁用 compositor glass fallback 的 shadow/stroke 可读且不双描边。
- `A20.5`：未新增主题、皮肤、图标选择器或无关视觉功能。

## T21 异步操作真实完成状态

**对应发现**：UX-04。
**目标**：让 Power、Search、Appearance 等现有动作拥有从请求到完成/失败/超时的真实状态，UI 关闭后仍可恢复错误上下文。

**必须机制**：

- 原地扩展 CommandRunner/现有 Process ownership；高风险动作不得再用 detached spawn 代表完成。
- 状态统一为 queued/started/completed/failed/timeout/canceled，并携带 action identity 防止晚结果覆盖。
- Appearance 明确 desired/applying/applied/capability/lastError；移除掩盖后端失败的 `|| true`，但允许按现有后端定义部分成功。
- 使用现有 notification/toast/inline error 通路，不能新增消息中心或“高级状态页”。

**验收**：

- `A21.1`：fake power command 的成功、非零、FailedToStart、timeout、重复确认均有确定 UI/状态结果；禁止真实电源操作。
- `A21.2`：菜单可按既有设计关闭，但失败产生可见且可重试的持久反馈，保留 action context。
- `A21.3`：Search open/copy/command 失败时查询与选中项保留或恢复，不假报成功。
- `A21.4`：dark/night mode 后端缺失/失败时 desired 与 applied 可区分，重启持久化语义明确。
- `A21.5`：late result、service destroy、并发不同 action 不串状态；现有 dependency preflight 保留。

## T22 日志轮转与诊断入口

**对应发现**：OPS-01、OPS-02。
**目标**：让 niri 会话日志有界、Quickshell 实例日志可定位，并保留按需 debug 能力而不常驻刷屏。

**必须机制**：

- 在现有 `tahoe-niri-session.sh` 启动边界轮转，使用 size/count policy、原子 rename 和明确权限；不引入 daemon/system service。
- 默认日志级别减少已解决的每帧 debug；需要性能调查时沿现有环境变量临时启用采样。
- 提供只读诊断命令定位当前 Quickshell instance/log ring；不得把 stdout/stderr 无界合并进 session.log。
- 不删除当前 3.55 GB 文件，除非用户单独授权。

**验收**：

- `A22.1`：临时目录中模拟超限、并发启动、rename 失败、只读目录，日志不丢当前会话且总大小有界。
- `A22.2`：保留数量、单文件上限、权限和压缩策略有测试与文档；无宽路径删除。
- `A22.3`：默认会话不再逐帧输出 blur allocation debug，按需诊断仍能获得 surface/cause 采样。
- `A22.4`：一条命令可找到当前 Quickshell 实例日志并报告 binding/type warning 摘要。
- `A22.5`：不得记录通知正文、剪贴板内容、Wi-Fi 密钥或其他敏感 payload。

## T23 多输出/混合缩放/热插拔整体验收

**对应发现**：STAB-01/03、旧报告的 Genie output-local endpoint 风险。
**目标**：验证 T01-T22 在 output add/remove、不同 scale/transform 和进行中动画迁移时形成完整系统行为。

**必须机制**：

- 优先扩展现有 headless/virtual output test harness；不得创建仅供本路线图使用的第二 compositor harness。
- 进行中的 Genie 必须明确定义：取消、在新 output 重投影或以无 endpoint 继续；不能原样迁移旧 output-local rect/scale snapshot。
- shell 每 output surface、popup anchor、Dock rect、Tahoe mapping generation 和 focus restore 必须随 output identity 变化。
- 真实硬件 hot-plug 只作为用户授权的补充验证。

**验收**：

- `A23.1`：1.0/1.25/2.0 scale 与 normal/rotated output 组合下 add/remove 100 次无残留、panic、错误 global redraw。
- `A23.2`：Genie minimize/restore 中途拔出源/目标 output，无跳到旧坐标、永久裁切或 lease 残留。
- `A23.3`：TopBar/Dock/popup/island 在 primary 切换后 mapping/anchor/input/focus 正确。
- `A23.4`：renderer reset、last-output removal、output reconnect 同名/不同 identity 均覆盖。
- `A23.5`：niri、Quickshell、shell 组合测试和协议 guardrail 全绿。

## T24 全量回归、长时 soak 与收尾

**对应发现**：PERF-04、OPS-03，以及所有历史/风险项。
**目标**：在固定基线矩阵中证明路线图整体没有破坏原功能，并对内存、帧时间、日志、资源和当前告警给出最终数据。

**必须机制**：

- 不再实现新功能；只修复由最终矩阵确认且可归因于 T01-T23 的回归。
- 运行至少 60 分钟 idle soak，以及岛、Dock、Overview、popup、天气、通知、hot-plug 的重复场景 soak。
- 对历史 Quickshell Network/QML core 只做现行回归覆盖；没有复现不得虚构根因。
- 把最终证据写入 execution log，并更新研究报告的“当前状态”而不重写历史事实。

**验收**：

- `A24.1`：niri fmt/test/check、Quickshell build/ctest、Tahoe shell 全量 pytest、协议/guardrail/config validation 全绿。
- `A24.2`：当前 Quickshell 日志中零 binding loop、零 undefined-to-type、零由本路线图引入的 QML warning。
- `A24.3`：60 分钟 PSS/Private_Dirty、FD、线程、QObject/texture、mapped layer 和日志增量无未解释单调增长。
- `A24.4`：核心场景 frame p50/p95/p99、blur allocation/capture、CPU/GPU/功耗与基线比较；任何回退有书面裁决。
- `A24.5`：light/dark、8 accent、normal/reduced、三分辨率、三 scale、键鼠/触摸的视觉与操作矩阵通过。
- `A24.6`：所有 T01-T24 状态闭合，无 `BLOCKED`、未裁决 `PLAUSIBLE`、TODO、未推送 commit 或部署版本错配。
- `A24.7`：需要用户亲自执行的实时会话重启/真实 hot-plug 清单单独列出，不冒充已完成。

---

## 5. 发现到任务映射

| 研究发现 | 路线图任务 |
|---|---|
| STAB-01 | T01、T23 |
| STAB-02 / STAB-03 | T02、T23 |
| STAB-04 / damage / redraw root | T03 |
| pointer deadlock protection / cache / focus | T04 |
| thumbnail main-loop risk | T05 |
| STAB-05 QsPaths | T06 |
| STAB-06 FileView | T07 |
| Dock missing mappingGeneration | T08 |
| Tahoe pending/completion feedback | T09 |
| PERF-01 / PERF-02 | T10、T11、T12 |
| linear-light proposal | T13 |
| MOTION-01 / MOTION-02 | T14 |
| MOTION-03 / MOTION-04 | T15 |
| PERF-03 / retry / IPC budget | T16 |
| UX-01 / typography | T17 |
| UX-02 | T18 |
| UX-03 / scroll / focus | T19 |
| icon/radius/shadow/fallback | T20 |
| UX-04 | T21 |
| OPS-01 / OPS-02 | T22 |
| mixed-scale/hot-plug/Genie | T23 |
| PERF-04 / OPS-03 / final regressions | T24 |

未在本表中的旧草稿主张不自动形成任务。执行者若发现遗漏，必须停下请求用户修订路线图，不能自行追加工作。
