# P03 对抗性审查记录

日期：2026-07-26

## 改动摘要（niri fork，`niri/`）

问题定位（较研究报告更精确）：smithay（rev ff5fa7df）damage tracker 本身已具备 fb-effect 缓存判据——`needs_capture` 仅在 fb 元素自身或其**下方**元素产生与其区域重叠的 damage 时置位，capture 被跳过时 `draw` 复用 effects_cache 里的 `Inner.intermediate`（blurred 纹理）。live 路径"每帧 blit + 全套金字塔"的真正根源是 fork 自己的失效通道：`tahoe_glass.rs render_region` 中 `material_alpha`/`interaction` 每帧缩放材质标量 → `ResolvedEffectVisualKey` 每帧变 → `note_plan_visual` → `nonxray.damage()`（FramebufferEffect commit 递增）→ 元素自身 damage → smithay 判定 needs_capture → 每帧重新 blit + blur。而这些标量只进 draw pass uniform（`compute_uniforms`），blit 源与金字塔输出与它们无关。

修复 = 失效通道拆分（重构原路径，无第二条 blur 管线）：

- `resolved_effect_plan.rs`：新增 `ResolvedEffectCaptureKey { blur, blur_options(passes/offset), xray }` + `capture_key()`；blur 解析提取为 `resolve_blur` 与 `build()` 共用（无逻辑分叉）。`blur_config.noise/saturation` 刻意不入 key（仅 draw uniform）。
- `background_effect.rs`：`note_plan_visual` → `note_plan_keys(visual, capture)` 双通道——任何视觉变化 → `ExtraDamage.damage_all()`（重绘）；仅 capture key 变化 → `nonxray.damage()`（重 capture）。live 分支提取为 `render_live`，并把 ExtraDamage 元素 push 在 fb 元素**之前**（z 更高）：其 damage 驱动重绘但被 smithay `skip(damage_index)` 排除在 needs_capture 判定外。`damage()`（blur region 协议变化外部入口）保持双通道保守。
- `tahoe_glass.rs` / `render_for_tile`：两处调用方同步双 key。
- 计量（既有 `lifecycle_diag` 设施延伸，`NIRI_LIFECYCLE_DIAG=1` 门控）：`fb_effect_capture`/`blur_render` 计数器 + `maybe_log_periodic()` 5s 节流增量日志（挂 `Niri::redraw` 开头，禁用时单原子读）。
- 测试 8 项：capture key 对材质 fade/interaction boost 稳定、对 kernel(passes/offset/off)/effect.blur/xray 敏感、与 `build()` 解析一致；`note_plan_keys` 双通道 commit 行为（`CommitCounter::distance` 量化）；live 路径 push 顺序（ExtraDamage 在 fb 元素前）。
- 测试灵敏度实证：临时在 visual 分支恢复 `nonxray.damage()`（旧行为）→ `draw_only_material_change_damages_without_recapture` 立即红（"draw-only change must not force a framebuffer re-capture"）→ 撤销恢复全绿。

## 验收数据（嵌套 winit niri，2026-07-26）

场景：`window-rule background-effect { blur true; xray false; tint-amount 0.15; refraction 0.02 }` 强制全窗口走 live 路径；debug 二进制，`NIRI_LIFECYCLE_DIAG=1`；alacritty ×2（静止）+ `watch -n1 date`（每秒变化）。5s 增量：

| 阶段 | redraw | fb_capture | blur | 解读 |
|---|---|---|---|---|
| 窗口映射前 | +46 | +0 | +0 | 无玻璃元素 |
| 静止双窗口 | +52 | +5 | +5 | 零星内容 damage 正确失效；其余帧复用缓存 |
| 开窗 + 布局动画 | +239 | +275 | +275 | 几何变化期每帧正确失效（多玻璃 × 每帧） |
| 全静止 | +1 | +0 | +0 | **验收达标：静止玻璃零 blur** |
| watch 每秒刷新 | +4 | +0 | +0 | 窗口内容在玻璃上方，不触发重 capture（blur 的是下方 backdrop，视觉一致） |

全程 `fb_capture : blur ≡ 1:1`（无泄漏执行）。`cargo build`/`cargo check --release` 零警告；`cargo test --lib` 463 通过（含新增 8 项）。

主会话（tahoe-shell 材质动画场景，即本改动的核心收益：顶栏 hover/按压、灵动岛 material_alpha 过渡期 blur 归零）需部署 `~/.local/bin/niri` 后以 `NIRI_LIFECYCLE_DIAG=1` 复测——见部署后附录。

## 审查方式

三个独立子代理并行对抗审查：① smithay damage 判据配合正确性 + 漏失效猎杀；② 全消费方回归面 + 动画路径 + diag 热路径；③ 视觉逐像素一致性专项（capture 隔离性、多缓冲 age、screencast 独立 tracker、material fade × sample_padding）。

### 审查一：正确性 / smithay 判据配合

- 裁决：**机制正确性成立，未找到"漏失效→画面陈旧"反例，全部边界失效方向保守**。
- 已验证：`element_damage_index` 在元素自身 damage 之前记录（damage/mod.rs:544）→ `skip(damage_index)` 恰好排除上方（含新 ExtraDamage）、包含自身+下方；`force_effect_redraw` 三场景（元素消失/opaque 收缩/输出变化）damage_index=0 保守重 capture；noise/saturation 确实只进 draw uniform（blur shader 仅 tex/half_pixel/offset）；xray 默认位翻转只随整体可见性翻转同帧发生，元素出入场全 damage + capture key 含 xray 双保险；subregion 双通道保守；draw_clip 仅动画期变化且伴随几何/alpha 实例态失配兜底；多实例（fb 缓存键按 ns 隔离；ExtraDamage 同 Id 多实例走 smithay 通用 last_instances 逻辑最坏保守）；两遍渲染（damage_output + render_output_with_states）经 with_element_state 转发 needs_capture；ExtraDamage 覆盖 ⊇ fb 实绘（`precise_up` ⊇ `precise_round`，crop 语义两变体同生共死）；capture key 依赖 ⊆ visual key 依赖 → 两通道同触发，且 commit bump 自身产生全几何 damage 重绘自足。
- [P2 已修] capture key 文档误把 `alpha` 写进 ExtraDamage 通道（alpha 实际依赖上方共 fade 内容/伴随 glass 标量的既有旁路，pre-P03 同样）→ doc 更正。
- [P2 记录] 单测以 commit 计数为代理，mapped.rs wrap/crop 分发后的最终元素顺序无测试锁定 → 补强项。

### 审查二：回归面

- 裁决：**无 P0 正确性回归**。
- 已验证七项：全部消费方（window/layer/tile/layout/snap-preview）对元素数量/类型零假设，Crop/Rescale/Relocate/宏转发完备，tile.rs:1328 error 分支不可达；close/open 动画玻璃重绘机制具体存在（material_alpha 衰减→visual key→ExtraDamage；上方快照 alpha 实例失配 damage；slide 几何失配自然 capture），纯 fade 无玻璃字段场景与旧代码逐帧等价；多 region z 序严格等价（视觉 damage 从 z(Fb) 移到 z(Fb)−1，之间无任何 fb 元素；下方 region 变化仍正确触发上方 capture；删除的"上方 draw-only 变化级联下方 recapture"因 draw 阶段 back-to-front 而安全）；xray 分支逐字节不变；popup（xray 默认 false）路径安全，离屏烘焙路径无条件 capture 无陈旧纹理；capture key 覆盖金字塔全部参数输入无遗漏；`note_plan_visual` 全仓无残留（含 niri-visual-tests）。
- [P1 澄清] `cargo check --workspace --all-targets` 失败（protocols/tahoe_glass.rs:1115 E0063）系**工作树中并行的 P05 协议半成品**（+447 行 + transform_animation.rs + XML），非 P03 diff 文件；P03 七文件独立可编译性另以干净 worktree 实证（见下）。
- [P2 已修] `ensure_init` 每次原子 RMW → 加 `INIT.load` 快路径；`maybe_log_periodic` SystemTime 回拨静默 → 换 `Instant` 单调钟。
- [P2 记录] live 路径 ExtraDamage 未按 ns 命名空间化：overview 多视图帧同 Id 多实例可致对侧 fb 保守多 recapture（仅全屏运动帧的性能损失；xray 路径与 surface 级 damaged_regions 此前即如此）。

### 审查三：视觉逐像素一致性

- 裁决：**逐像素一致成立，未找到反例**。capture 输出 = f(下方 framebuffer, src, dst, scale, blur_options)，每个输入均有失效通道兜底；draw-only 参数逐行确认不进 capture_framebuffer。
- 已验证：buffer age 组合（capture 判定在 age 合并**前**、capture 帧全区域进 new_damage 参与后续合并、intermediate 整体原子替换）→ age=N 旧缓冲当帧用当前 intermediate 补画与最新缓冲一致，无混龄采样；screencast/screencopy 每目标独立 tracker → 独立 effects_cache/intermediate 无互踩，CommitCounter 只读不消费（damage_since 为相等比较，跳帧退化全 damage 保守）；material-only 帧 pre/post 像素等价（下方内容确定性重绘 → 相同 blit → 相同 blur）；叠层玻璃 z 语义自洽；SnapPreview 独立 FramebufferEffect 不走 note_plan_keys 行为不变；首帧切换成本一次性。
- [P2 记录] `params.scale` 不在任何 key/实例态——触达需"scale 变而物理几何不变"，实际 output scale 变化必然全屏失效，纯理论洞且 pre-P03 一致非回归。screencast `damage_output(1)` 先消费后 dequeue 失败丢帧为预存在问题，P03 前后等价。

### 共同结论：收益边界（非正确性问题，如实记录）

带 shadow 的 region 在 material_alpha fade 期，shadow（位于玻璃下方、在 blit 采样源内）alpha 每帧变化 → **语义上必须**每帧 recapture；refraction/lens_depth 参与 `glass_sample_padding`，fade/boost 使 padding 连续变化 → sample 几何抖动 → 那些帧实例失配照常 capture。按部署材质量化（refraction 0.002–0.013、lens 0–0.010、interaction 协议层 clamp(0,1)）：短边 < ~108px 的元素（顶栏 bar、灵动岛 compact、Dock）blur 项（passes×offset=9）主导 padding，fade/boost 期几何稳定、缓存收益完整；灵动岛 expanded / 大弹层 refraction 项主导（且弹层多带 shadow），动画期收益受限——静止期收益不受影响。视觉在全部场景正确（失配帧原子重 capture，无旧几何纹理错配）。

## 审查后修复

- `ensure_init` INIT.load 快路径（热路径去原子 RMW）；`maybe_log_periodic` 改 `Instant` 单调钟（回拨免疫）。
- `ResolvedEffectCaptureKey` doc 移除 alpha 误述，明确其既有旁路通道。
- P03 七文件在干净 HEAD worktree（/tmp/p03-verify，无 P05 半成品）独立编译 + `cargo test --lib` 全绿实证（见下）。

## 遗留观察项（后续任务输入）

1. **sample padding 峰值稳定化**（收益扩大，候选并入 P06 前测量）：`glass_sample_padding` 改用 at-rest 材质 × interaction 峰值（clamp 后上限 2×）计算，使 fade/boost 期 sample 几何恒定——需专项验证 boost 期折射采样 margin 充足（视觉安全边界），故不并入 P03。
2. shadow 元素在 fade 期驱动上方玻璃每帧 recapture 属语义正确（阴影在采样源内）；若 P04 后 material fade 成为主要动画形态，可再评估阴影与玻璃的合成顺序。
3. live 路径 ExtraDamage 的 ns 命名空间化（overview 多视图帧保守多失效）。
4. mapped.rs wrap/crop 分发层的元素顺序契约测试补强。
5. alpha 失效的既有旁路缺口（纯 blur 材质 + region 超出 surface 内容 + layer fade 的理论场景；tahoe-shell 实际 region 均在 surface 内）——pre-P03 既有，非本次引入。

## 结论

**PASS** — 三份独立审查均未发现正确性/视觉反例（P0 零）；全部可修 P1/P2 已修复并复测，其余为收益边界与补强项，已如实记录。允许 commit + push。

