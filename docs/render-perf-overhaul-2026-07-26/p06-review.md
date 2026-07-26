# P06 — 动画期 blur 降采样档位（2026-07-26）

> niri 子仓 commit：**78540ae2**（分支 tahoe-layer-animations，基 P03 7b2ebd0e）。
> 注意：niri 子模块指针**未**在本 commit 中前移——主检出树当时由 P05 会话持有
> 未提交改动，不可切换；指针将随 P05 落地或部署时统一前移。

## 决策与背景

roadmap 原文将 P06 定义为"兜底，视 P03/P05 效果决定是否执行；先测后做"。执行时点上
P03/P04/P05 正由并行代理推进（P03 于本任务审查期间落地 `7b2ebd0e`），"P03+P05 之后
的动画期瓶颈测量"在本任务窗口内不可得。按用户指令（并行推进、完整完成 P06），本任务
把**档位机制完整实现并默认启用**，同时提供进程级 A/B 开关，把"是否保留"的最终裁决留
给 P08 全量回归的实测：

- `NIRI_DISABLE_ANIM_BLUR_DOWNSAMPLE=1` 启动 niri 即回到旧行为（单点判定于
  `resolve_blur`，禁用时生成的 `BlurOptions` 与旧代码逐位相同，P03 缓存键零扰动）。

## 机制

- `BlurOptions` 新增 `downsample_shift: u8`（0=静止全档；动画档=1，常量
  `blur::ANIM_DOWNSAMPLE_SHIFT`，钳 ≤4）。
- **capture 减半**：`FramebufferEffectElement::capture_framebuffer` 里 blur 开启时
  capture framebuffer 尺寸经 `BlurOptions::capture_size()` 右移——既有
  `BlitFramebuffer(…, GL_LINEAR)` 即免费 2× box 降采样；`draw()` 按归一化坐标采样，
  分辨率无关（复核确认 postprocess/clipped_surface shader 无任何纹素尺寸推导项）。
- **passes 补偿 + 门槛**：`effective_passes() = clamp(1,31)(passes) − shift`；档位仅在
  `passes > shift`（即 ≥2 pass）时启用——两档金字塔**最深层完全一致**（结构性半径对
  齐，单测锁定），单 pass kernel 恒静止档，无半径翻倍边界。金字塔写像素 ≈ 1/4。
- **触发谓词**（仅几何动画，逐帧）：`scale ≠ 1 || offset ≠ (0,0)`——
  open/popup 路径用 `OpenAnimationState`，close live 路径用
  `CloseAnimationRenderState`；fade 与 opacity_delay 尾巴为 false；`bob_offset`
  （baba-is-float）刻意排除（永续动画不得永久降档）；快照烘焙、窗口路径、snap 预览、
  xray 恒静止档。
- **失效集成（对抗性审查修复，关键）**：档位由 `resolve_blur(options, blur_config,
  geometry_animating)` 唯一设置，`build()` 与 `capture_key()` 共用 ⇒ 档位是 P03
  `ResolvedEffectCaptureKey` 的一部分。engage/disengage 帧 key 翻转 →
  `note_plan_keys` bump live effect commit → 元素自身 damage → **零外部 damage 的帧
  也保证重绘+重 capture**。若无此步，spring 亚像素尾帧/纯 alpha 收尾会让半档模糊在
  静止桌面永久驻留（三个独立审查者一致抓出的 BLOCKER）。

## 与 P03 的集成契约（已实现）

capture key 与 kernel 由同一 `resolve_blur` 解析，结构上不可能脱钩；纯材质动画
（interaction/material_alpha）谓词恒 false ⇒ 不触碰 key ⇒ P03 的 draw-only blur 缓存
完整保留。测试 `downsample_tier_flip_forces_recapture_both_ways` 同时锁定双通道分工
（fb commit 两方向 +1、ExtraDamage 通道 0）。P05 变换动画落地时，将其动画期状态并入
各调用点的 `geometry_animating` 即可复用全套机制（build 与 capture_key 必须喂同一值，
两处 doc comment 已声明契约）。

## 实测（结构性，本任务窗口）

- 1920×1080 capture、passes=3（当前各 material kernel 均 passes:3）：金字塔写像素
  3 402 000 → 810 000（≈×0.238），另 blit 目标像素 −3/4、draw 采样带宽减半。
- cargo test：**472 通过 / 0 失败**（含 P03 落地套件 + P06 新增 9 项）；release 构建
  通过。
- 已知代价（审查 MINOR，接受并记录）：动画进/出各一次 capture+金字塔纹理重建（收尾
  帧含一次全尺寸分配，建议 P08 基准观察）；用户自定义 y>1 cubic-bezier 至多 ~6 次/动
  画有界翻转；slide/edge-reveal close 首帧 offset=0 多一次重建；动画结束帧一帧"blur
  回锐"为既定语义。
- 动画期 GPU 帧时间实测与 A/B（开关对照）留待 P08 在 P05 落地后统一采集（与 P03 部署
  待办合并：重建 `~/.local/bin/niri` + 会话重启窗口期，`NIRI_LIFECYCLE_DIAG=1` 观察
  5s delta 日志）；若结论为"无需档位"，`NIRI_DISABLE_ANIM_BLUR_DOWNSAMPLE=1` 即回
  退，无需改码。

## 审查记录

三个独立子代理对抗性审查（渲染/GL 正确性、回归与语义、边界条件三视角）：

- **首轮：三方一致 FAIL**，独立命中同一 BLOCKER——档位翻转不进 damage/失效指纹，
  半档模糊驻留静止帧（三条独立触发路径：spring 亚像素尾巴、opacity 先于 transform
  完成、P03 下默认 Popin 纯 alpha 收尾 draw-only 复用旧纹理）。次要发现：passes=1
  半径翻倍边界、翻转纹理重建 churn（有界）、env 取值惯例 cosmetic。
- **修复**：capture key 集成（上文"失效集成"）+ passes 门槛 + 4 项回归测试。
- **复核：三方一致 PASS**，各自到 smithay ff5fa7d 源码级重推 damage 链
  （note_plan_keys 先于元素创建 → commit bump → `damage_since` 全几何 →
  `needs_capture` 必然成立），并独立复跑测试 472/0。确认：A–F 正确性结论维持、
  P03 draw-only 语义完好、两调用点 build/capture_key 喂同一形参无脱钩窗口、
  kill-switch 下 key 与 kernel 同步退回零开销。
- 首轮全 OK 项：draw 映射分辨率无关（shader 逐项核查）、ensure 不变量、clamp/取整、
  subregion/draw_clip/Tty、blur-off 路径、xray 隔离、快照烘焙独立 UserDataMap、
  close 冻结生命周期、整数边界、r15 结构测试兼容、守护规则（region 禁弹簧）无涉、
  env 开关非平行接口认定（NIRI_LIFECYCLE_DIAG 惯例族）。
