# T-32 · glass capture band 8px 量化 + 快速运动 downsample tier2（2026-07-31）

任务定义：`docs/refactor-roadmap-2026-07-27/roadmap.md` T-32（R-3）。
门槛判定：T-30 验收 `T30-profiling-baseline-2026-07-31.md` §6 —— **GO**
（C-island 峰值 0.42ms/帧、D-overview 0.61–0.75ms/帧、B-dock 0.38ms/帧，均 ≥0.3ms 门槛）。

## 1. 实现摘要（niri 子模块）

### a) band 8px 量化（R-3a）

- `resolved_effect_plan.rs`：`CAPTURE_BAND_QUANTUM=8`、
  `quantize_capture_band()`（向外取整、严格超集、幂等、负坐标安全）、
  `ResolvedEffectPlan::resolve_capture_band(band, geometry_animating)`（仅动画期量化；
  `NIRI_DISABLE_BAND_QUANTIZATION` A/B 开关）。
- 调用点（`background_effect.rs::render_for_tile` 与 `tahoe_glass.rs` 的 region 渲染）：
  量化后的 band 同时进入 capture key 与 `RenderParams.capture_band`（元素携带）。
- `framebuffer_effect.rs`：
  - `capture_framebuffer`：blit 源改用量化带（clamp/比例一致），纹理尺寸仍按
    src.size 推导（保留 overview 缩放不重分配纹理的既有行为）；
  - `draw`：按输出变换把「精确 clamped 目标」映射为量化纹理内的子矩形
    （`texture_rect`），归一化坐标与 crop/uniform 数学不变 —— 超集捕获的精确映射端。
- **不是 rest-anchored 采样**：量化带跟随 band 移动（只是取整到 8px 格），
  从不采样「静止位」内容；61138be 教训不适用（roadmap.md T-32 行）。

### b) 快速运动 tier2（R-3b）

- `blur.rs`：`FAST_MOTION_DOWNSAMPLE_SHIFT=2`、`FAST_MOTION_DISPLACEMENT_PX=24`、
  `NIRI_DISABLE_FAST_MOTION_DOWNSAMPLE` 开关。
- `BackgroundEffect::is_fast_motion(band)`：上一帧 capture band 与新 band 的
  曼哈顿位移 > 24px（per-region/per-surface 天然成立）。
- `resolve_blur`/`build`/`capture_key` 新增 `fast_motion: bool`；tier 仍在
  `BlurOptions.downsample_shift` 单点设置，build 与 capture_key 喂同一值
  （P06 契约保持）；tier 翻转经 capture key 失效契约双向强制重捕获（临时档位）。

## 2. 验收

| 项 | 结果 |
|---|---|
| niri `cargo test --lib` | 543/543（新增 5 项 T-32 测试全过；连续多轮全绿） |
| 新增单测 | `quantize_capture_band_is_superset_and_idempotent`（超集/幂等/格线/负坐标/亚格复用/跨格重捕）、`resolve_capture_band_quantizes_only_while_animating`、`quantized_band_reuses_capture_within_cell`（note_plan_keys 级：同格复用 0 bump、跨格 +1）、`fast_motion_tier_flip_forces_recapture_both_ways`、`is_fast_motion_threshold`；`capture_key_tracks_downsample_tier` 扩展 fast tier 断言 |
| `cargo check` 警告 | 0 |
| 运行时 `note_fb_effect_capture` A/B | **有限样本**（见 §3）：overview 5s 窗口和 135→137（无回归）。量化命中路径（慢速几何动画）的运行时计数受嵌套 winit swap 停顿限制未取得，机制由单测锁定；测量工具 `tools/t32-capture-ab/run-capture-ab.sh` 已入库供稳定会话复跑 |
| blur 边缘走查 | 理论等价：量化捕获严格超集，draw 端子矩形精确映射（与 P06 downsample 同型）；无内容重采样差异。走查命令见 §4 |

## 3. 运行时样本（有限，如实披露）

- 场景 overview 进出 ×6（嵌套 winit 会话，`NIRI_LIFECYCLE_DIAG=1`）：

| 指标 | before（5b6210fe） | after（本任务） |
|---|---|---|
| fb_capture 5s 窗口和 | 135 | 137 |

- 说明：overview 缩放不是 `geometry_animating` 路径，量化按设计不介入；
  计数持平 = 无回归（捕获既不丢失也不重复）。量化收益场景（island 展开、
  dock autohide 滑动等慢速几何动画）在嵌套 winit 下受 T-30 已记录的
  swap 停顿（T30 验收 §7.6）与 quickshell IPC 挂起影响，未取得可信前后对比；
  `tools/t32-capture-ab/run-capture-ab.sh`（dock 慢扫 / island / overview +
  autohide 滑动驱动）已入库，可在稳定会话（真实 DRM 或已消除停顿的会话）复跑。

## 4. 走查与回滚开关

- 视觉走查：`NIRI_DISABLE_BAND_QUANTIZATION=1` 对比默认行为（dock 展开/收起、
  island 展开、窗口打开动画的 blur 边缘）；理论无差异（超集+精确子矩形映射）。
- 快速运动档位：`NIRI_DISABLE_FAST_MOTION_DOWNSAMPLE=1` 回退 tier1。
- 既有开关 `NIRI_DISABLE_ANIM_BLUR_DOWNSAMPLE` 语义不变。

## 5. 行为契约核验

- 静止 band：key 不变 → 缓存复用（P03 既有），量化不改变（静止非动画期不量化）。
- 动画期亚格移动：同量化格 → key 不变 → commit 通道不动（运行时 blit 仍受
  damage tracker 的 i32 几何变化驱动，量化收益集中在亚像素尾帧与 slow-path）。
- 动画期跨格/快速移动：key 变 → 重捕获；tier2 仅在位移 >24px/帧时临时生效，
  停顿时经 key 翻转恢复全质量。
- blur 半径一致性：tier 仅在 passes > shift 时生效（既有守卫），最深层金字塔
  半径不变（P06 既有测试锁定）；passes=2 时 fast 帧回退 ANIM 档（F4）。

## 6. 对抗性审查与修复（两轮独立子代理）

第一轮发现并修复：

| # | 严重度 | 发现 | 修复 |
|---|---|---|---|
| F1 | MAJOR | layer 开启动画/变换动画以 Rescale/Relocate/Crop 包装元素，capture 收到 post-wrap dst；量化带（未 wrap 几何）与可见带错位 → 61138be 同类 | `capture_band_applies(dst, own_geometry)` 守卫（≤1px 容差）：仅未包装元素用量化带，wrapped/crop 回退精确 dst；capture 与 draw 同一守卫；damage tracker 对 moving wrapped 元素逐帧实例 damage 兜底 key↔blit 不一致 |
| F2 | MAJOR | crop 路径分辨率回归 | 量化适用时纹理尺寸改由量化带推导（1:1），wrapped/crop 回退走原 src.size 链 |
| F3 | MAJOR | fast kill-switch 让 fast 帧落到 shift=0（A/B 基线错误） | `NIRI_DISABLE_FAST_MOTION_DOWNSAMPLE` 时 fast 帧回退 ANIM 档（tier2-vs-tier1 基线） |
| F4 | MINOR | passes=2 时 fast 帧比动画帧更贵 | 新 tier 选择：fast 档不可用时回退 ANIM 档；测试锁定 |
| F5 | MINOR | 注释与 24px=3 cells 不符 | 注释修正（阈值是量化带上的严格 >24px） |

第二轮验证 + 新发现并修复：

| # | 严重度 | 发现 | 修复 |
|---|---|---|---|
| #7 | MAJOR | 量化 draw 的 v_coords 只覆盖纹理子矩形，而 input_to_geo 未补偿 → 玻璃 SDF（圆角/rim/高光/clip）偏移 0–7px，动画结束帧回跳 | `compute_uniforms` 增加 `band_subrect=(q/p, -rel/q)` 补偿矩阵；量化路径限 Normal 变换（旋转输出保守回退精确路径） |
| #8 | MINOR | 测试注释把 key 通道说成 "reuse cached blur"（运行期 blit 仍由 damage tracker 驱动） | 注释精确化 |
| #1a | INFO | f32 scale 往返在非二进分数下守卫可能静默失效 | 守卫改为 ≤1px 容差（安全方向降级） |

两轮审查确认的数学正确项：量化超集包含关系、capture 三链比例自洽、旋转变换对称性
（Normal 下严格成立；非 Normal 保守回退）、build/capture_key 的 fast_motion 一致性、
xray 隔离、非动画路径逐字节等价。
