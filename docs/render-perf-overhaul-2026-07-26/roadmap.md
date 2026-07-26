# 渲染性能重构路线图（2026-07-26）

> 依据同目录 `research-report.md`。范围 = **路线二全部（合成器下沉）+ 路线一核心投资（自定义单线程 QSGRenderLoop）** + QML 速效项。

## 流程铁律（每个任务必须遵守）

1. **严格串行**：每完成一个任务并通过审查、commit + push 之后，才能开始下一个任务。禁止并行推进多个任务。
2. **独立子代理对抗性审查**：每个任务完成后，必须派多个独立子代理对改动做对抗性审查（正确性、回归、边界、与守护规则冲突），审查通过才允许 commit + push。
3. **不做最小实现**：允许并鼓励局部重构，把实现做完整、做对，不留"临时方案"。
4. **禁止平行接口**：不得为绕开现有实现新建并行的第二套接口/路径；必须重构原有实现本身。
5. **不破坏原有功能与实现语义**：所有现有视觉效果、交互、配置行为必须保持；重构是内部结构与性能改进，不是行为变更。
6. 既有守护规则继续生效：玻璃 region 几何禁弹簧（Motion.js:269-272）；`QSG_USE_SIMPLE_ANIMATION_DRIVER` 禁用。

## 任务序列

### 阶段 A：QML 速效项（低风险热身）

**P01 — 缩略图解码修复**
- `WindowOverview.qml:1041`、`TaskSwitcher.qml:569`、`Spotlight.qml:698`、`DockMinimizedWindow.qml:206`：为窗口截图 `Image` 补 `sourceSize`（按实际显示尺寸 × 屏幕 scale），并复查 `cache: false` 的必要性（缩略图文件按窗口更新时失效的场景保留，否则允许缓存）。顺带复查 `Wallpaper.qml:995-1004` 静态壁纸。
- 验收：打开 Overview/TaskSwitcher 首帧无解码风暴（对比 CPU 峰值），视觉无变化。

**P02 — 静止窗口 updatesEnabled 门控**
- 利用 fork 已有的 per-window `updatesEnabled`（`windowinterface.hpp:151`）：对不可见/完全静止的常驻窗口（含 DynamicIslandOverlay 空闲态）接入统一冻结门控。作为对现有 `visible`/`pollingActive` 门控体系的重构延伸，不新建平行机制。
- 验收：空闲时 quickshell 各渲染线程无唤醒（`NOCTALIA_IDLE_PROFILE` 思路：用 perf/strace 抽查）；所有动画/弹出行为不变。

### 阶段 B：niri 合成器下沉（路线二主体）

**P03 — live blur 结果缓存**
- `render_helpers/framebuffer_effect.rs`（+ `background_effect.rs`）：为 live 路径增加"上一帧 blit 区域无 output damage 则复用 blurred 纹理"判据，范式取自 xray 路径 `effect_buffer.rs:233-257` 的 OutputDamageTracker 用法。是对 live 路径的重构，不新建第二条 blur 管线。
- 验收：静止玻璃面板下 GPU blur pass 不再每帧执行（renderdoc/日志计时确认）；视觉与现在逐像素一致（含 interaction/material_alpha 动画期正确失效缓存）。

**P04 — 弹层进出场动画收尾（QML 侧删动画，交合成器）**
- 合成器侧 open/close 动画已完工（`opening_layer.rs`/`closing_layer.rs`）。逐面板把 QML 自有 map/unmap 进出场动画（opacity/位移尾巴、延迟 unmap 技巧）删除，改为静态提交 + 合成器 layer 动画 + `interaction`/`material_alpha` 状态过渡。逐面板推进、逐面板核对动画风格与现有观感一致（per-layer rule 调参补齐差异）。
- 注意：此任务体量大，允许在任务内按面板分批 commit，但每批仍需审查后 push。
- 验收：每个面板打开/关闭动画观感不劣于现状（时长/曲线/origin 对齐），client 侧动画期 CPU 下降。

**P05 — 变换动画下沉协议（set_transform_target）**
- tahoe-glass-v1 协议扩展 `set_transform_target(x, y, scale, spring 参数)`（`protocols/tahoe_glass.rs` 增 request，协议版本 +1，向后兼容旧 client——版本协商不算平行接口）。
- niri 侧：per-surface `TransformAnimation`，复用 `OpenAnimation` 双通道骨架 + `RescaleRenderElement`/`RelocateRenderElement` + R16 稳定 identity。明确决策 glass region 随变换模式（优先沿用 closing_layer 的冻结跟随模式，逐帧重映射为后备）。
- quickshell 侧：`tahoe_glass/` 客户端封装该 request；tahoe-shell 侧把动态岛形变、Dock 放大波改为提交静态内容 + 发变换目标。**注意守护规则**：弹簧在合成器侧作用于 surface 变换，不作用于 glass region 几何本身，与"玻璃 region 禁弹簧"不冲突，但需在审查中专项确认。
- 验收：动态岛/Dock 动画期 client 不再每帧重提交 buffer；blur 不随变换每帧重算；观感（弹簧手感）与现有 Motion.js 参数对齐。

**P06 — 动画期 blur 降采样档位（兜底，视 P03/P05 效果决定是否执行）**
- 若 P03+P05 后动画期仍有 blur 瓶颈：动画状态下将 kawase 金字塔起始降采样提一档（`blur.rs` `prepare_textures` 兼容复用逻辑可吃下档位切换）。
- 先测后做：无瓶颈则标记 SKIPPED 并记录数据。

### 阶段 C：路线一核心投资

**P07 — 自定义单线程 QSGRenderLoop**
- quickshell fork 内实现 `TahoeRenderLoop`（参考 `QSGThreadedRenderLoop`）：单渲染线程轮询全部窗口、按各窗 frame callback 起搏、跨窗帧对齐；首窗创建前 `QSGRenderLoop::setInstance()` 注入。这是对渲染循环的**替换式重构**（经运行时开关选择实现属于配置项，不属于平行接口；默认启用新 loop，旧 threaded 路径仅作故障回退保留一个发布周期后移除）。
- 覆盖：expose/resize/grab/incubation（`core/incubator.cpp` 与 loop 的 timeToIncubate 耦合）、`updatesEnabled`、窗口销毁时序（deleteOnInvisible）、多屏。
- 验收：渲染线程数 32→1；所有面板动画无掉帧回归（重点：多窗同帧动画场景，如弹层 + dismiss 层同开）；长时间运行无死锁/泄漏；崩溃场景（GPU reset）不劣于现状。
- 风险最高，放最后：前面阶段完成后系统负载已低，本任务收益可单独度量。

### 收尾

**P08 — 全量回归审查 + 文档更新**
- 跨任务综合对抗性审查（多子代理）：全部面板交互走查、空闲功耗对比（quickshell CPU 均值、渲染线程唤醒）、动画期帧率记录（打开/退出/动态岛/Dock/面板展开）。
- 更新本目录文档，记录每任务的实测数据与遗留项。

## 度量基线（P01 开始前采集一次）

- 详见 `baseline-pre-p01.txt`（2026-07-26 采集）。
- quickshell 空闲样本：pid 常驻、Threads=10、5s 采样 CPU 见基线文件；研究期均值曾录 ~2.9%。
- 渲染线程：本机空闲未见 per-window QSG 渲染线程洪峰（面板未全热时 NLWP=10）；研究指满载 ~32。
- 打开 WindowOverview / ControlCenter / Launchpad 的首帧耗时与动画期掉帧数：P01 后对比采集。
- 动画期 niri GPU 帧时间（blur pass 占比）：留给阶段 B。

## 任务状态

| 任务 | 状态 | commit |
|---|---|---|
| P01 缩略图解码修复 | 完成 | 4b6b420 |
| P02 updatesEnabled 门控 | 完成 | db8799b（quickshell 1c03b80） |
| P03 live blur 缓存 | 未开始 | |
| P04 弹层动画收尾 | 未开始 | |
| P05 变换动画下沉协议 | 未开始 | |
| P06 动画期降采样（兜底） | 未开始 | |
| P07 单线程 RenderLoop | 未开始 | |
| P08 全量回归审查 | 未开始 | |
