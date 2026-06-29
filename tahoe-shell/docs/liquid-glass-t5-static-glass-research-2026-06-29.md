# Liquid Glass T5 Static Glass Research

日期：2026-06-29

## 状态

T5 已完成研究，不落实现。

本轮没有新增 static blur、screencopy service、长期 region texture cache、Wayland request 或 KDL 开关。当前结论是：TahoeGlass 继续实时走现有 `BackgroundEffect` / `FramebufferEffect` / `Xray` 管线；static blur 只保留为 T14 的有条件研究方向。

## 开始前上下文

- 已完整读取 `tahoe-shell/docs/liquid-glass-niri-glass-forceblur-roadmap-2026-06-28.md`。
- 开始前读取 Git 历史和现有改动：`HEAD` 为 `f042058 tahoe: advance liquid glass roadmap`。
- 开始前 `git status --short` 与 `git diff --stat` 为空，工作区干净。
- 最近提交已经完成 T4 路线图推进、`GlassPanel.qml`、material profile、guardrails 和 T4 视觉基线。

## 运行环境测量

这次测量只作为 T5 起始数据，不作为实现 static blur 的依据。原因是当前会话存在动态壁纸、打开的终端和多个前台窗口，不能代表干净的低功耗 idle。

环境：

- 运行中的 compositor：`/home/wwt/.local/bin/niri --session --config /home/wwt/.config/niri/tahoe/config.kdl`。
- `niri msg --json version`：CLI `26.04 (8ed0da4)`，compositor `26.04 (6df0b4fa)`。
- `/usr/bin/niri --version`：`26.04 (8ed0da4)`。
- `/home/wwt/.local/bin/niri --version`：`26.04 (6df0b4fa)`。
- Quickshell：`/home/wwt/.local/bin/quickshell 0.3.0 (revision d2f0acf96cbd03f6f4029d686e68c2c93c6229b2, distributed by Tahoe fork)`。
- 输出：`eDP-2`，物理 `2560x1600@239.998`，逻辑 `2048x1280`，scale `1.25`，VRR disabled。
- 当前 layer：`linux-wallpaperengine`、`tahoe-wallpaper`、`tahoe-topbar`、`tahoe-dynamic-island`、`tahoe-dock`。
- Overview：closed。
- 当前窗口：Console、Text Editor、cc-switch、Nautilus、Sparkle。
- 配置 hash：仓库 `config/niri/tahoe-phase0.kdl` 与部署的 `/home/wwt/.config/niri/tahoe/config.kdl` 不一致；`TahoeGlass.js` 仓库与部署版本一致。

10 秒进程采样，数据来自 `/proc` delta：

| process | CPU avg | CPU min | CPU max | RSS avg |
| --- | ---: | ---: | ---: | ---: |
| `niri` | `7.9%` | `6.8%` | `8.8%` | `260084 KB` |
| `quickshell` | `6.1%` | `4.9%` | `6.8%` | `436142 KB` |
| `linux-wallpaperengine` | `22.3%` | `20.5%` | `23.4%` | `289820 KB` |
| `kgx` | `19.8%` | `16.6%` | `25.2%` | `188732 KB` |

10 秒 NVIDIA 采样，数据来自 `nvidia-smi`：

| GPU | util avg | util range | power avg | power range | temp avg | VRAM |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| RTX 4070 Laptop | `33.5%` | `29-39%` | `34.3 W` | `31.6-38.2 W` | `65.1 C` | `2372 MiB` |

`/sys/class/drm/card*/device/gpu_busy_percent` 在同一窗口内每次为 `0`，当前机器上不能把该 sysfs 值当作 NVIDIA 渲染负载依据。

初步判断：

- 当前 GPU/CPU 负载主要被动态壁纸和终端会话污染。
- 这些数据只能说明当前会话有可观 GPU 活动，不能证明 TahoeGlass 需要 static blur。
- 要判断 static blur 是否值得做，必须在关闭动态壁纸、切到静态壁纸、重启到当前工作区 niri 构建后重测。

## forceblur 参考结论

本轮只参考 static blur 的架构边界，不复制实现。

有用点：

- `hasStaticBlur()` 由配置开关控制，并可在窗口后方存在其它窗口时禁用 static blur。
- static blur texture 按 output 缓存，`ensureStaticBlurTexture()` 已存在则复用，不存在才创建。
- static blur 命中时会清空 live blur 的 offscreen textures/framebuffers，改用 cached texture paint path。
- Wayland static texture 来源是 desktop wallpaper 或 custom image，并做 colorspace transform。
- 输出变化、桌面背景变化、reconfigure 都会清掉 static texture。
- normal blur path 对小纹理尺寸 clamp 到至少 `1x1`，并且只在尺寸、format、iteration 不匹配时重建 offscreen targets。

不适合 Tahoe 直接照搬的点：

- forceblur 是 KWin window effect，围绕 window stacking、desktop window、window class 和 decoration 判断；TahoeGlass 是 explicit layer surface region。
- forceblur static blur 本质更接近“画一张预模糊背景图”，不能保持真实窗口移动、视频、workspace animation 下的实时折射。
- forceblur UI 明确提示 static blur 下 refraction 不工作；Tahoe 的液态玻璃目标恰恰依赖真实背景采样、rounded SDF 和最后阶段折射。
- Tahoe 不应增加 per-window class matching，也不应新增普通应用窗口 glass 路径。

## 本仓库现状

当前 TahoeGlass 已经有一部分性能保护，不是每帧盲目重建所有资源：

- `tahoe_glass.rs` 在 `SurfaceData` 上保存 per-surface renderer，并按 committed region id 保留 per-region `BackgroundEffect` / `Shadow`。
- region damage 只记录 old/new region rect，并通过 `ExtraDamage` 推给 renderer。
- `BackgroundEffect` 只有在 blur config、options 或 radius 改变时 damage non-xray framebuffer。
- `FramebufferEffect` 已按 render element cache 复用 framebuffer；尺寸不变时不重新创建 framebuffer texture。
- `FramebufferEffect` 用 geometry/scale 计算 texture size，避免 overview zoom 中每帧因为 cropped dst 变化而 realloc。
- `Xray` 已经维护 per-render-target background/backdrop `EffectBuffer`，且能在 opaque background 覆盖 backdrop 时跳过 backdrop draw。

这些保护说明：如果出现性能问题，第一优先级应是先量化大 surface、blur passes、dynamic wallpaper 和 real xray path 的实际开销，而不是直接加 static blur。

## Tahoe static glass 假设

如果 T13 后续证明需要 static blur，候选范围只应是大面积、低动态、低折射场景：

- `Launchpad.qml` fullscreen/backdrop 模式。
- 其它 fullscreen backdrop 或长期 idle 的大 panel。
- 只在背后内容静止、没有 workspace animation、没有窗口移动、没有视频或动态壁纸时可用。

默认不应覆盖：

- `TopBar.qml`、`Dock.qml`、菜单、toast、Dynamic Island。
- `Spotlight` search pill 这类小面积、交互强、需要真实边缘折射的 region。
- `WindowOverview.qml`，因为窗口缩略图和 workspace animation 本身是高动态场景。
- 每个 TahoeGlass region 一张长期缓存纹理。

## 必须失效的条件

任何未来 static glass 设计至少要在这些条件下回到实时 blur，或者清空缓存：

- behind content 打开、关闭、移动、resize、restack。
- workspace animation、overview open/close、window overview、scale/transform animation。
- output mode、scale、transform、colorspace、VRR 或 monitor set 变化。
- wallpaper 改变，尤其是 `linux-wallpaperengine` 这类动态背景每帧更新。
- Tahoe layer surface geometry、region rect、radius、clip、material、materialAlpha、interaction 改变。
- niri `blur` 或 `tahoe-glass material` 配置改变。
- 背后有视频、游戏、屏幕共享、xwaylandvideobridge 或其它持续动态内容。
- lockscreen/session transition 等安全或可读性敏感场景。

## 风险

- stale background：缓存失效不完整会让 panel 后方内容显示错误。
- refraction 降级：static texture 不能表达真实背景移动下的折射，液态感会变弱。
- damage hole：缓存和实时路径混用时容易漏 damage，出现残影或局部不刷新。
- geometry mismatch：TahoeGlass 使用 region-local rounded rect 和 sample padding，缓存必须保持 texture UV 与 geometry UV 分离，否则会回到 T4 已修过的错位问题。
- memory cost：单个 `2560x1600` RGBA8 texture 约 `15.6 MiB`，多输出、多 cache、blur intermediates 会迅速放大。
- dynamic wallpaper 无收益：当前会话中动态壁纸持续更新，static cache 会频繁失效。
- complexity risk：失效条件和调度复杂度可能超过节省的 GPU 成本。
- regression risk：如果把 static blur 做成 KDL raw knob，用户会在小面板上打开它，导致玻璃视觉和实时交互退化。

## T5 决策

T5 结论是“不实现”。

当前测量不足以证明 static blur 必要，且已有动态壁纸负载污染。TahoeGlass 继续使用实时 background capture/blur/refraction。只有 T13 的干净场景测量显示大面积 backdrop 持续超预算，并且降低 refraction/lens/blur 后仍不可接受，才进入 T14 的 static blur 设计。

## T14 进入门槛

进入 static blur 设计前必须补齐这些测量：

1. 静态壁纸、无动态壁纸、无前台高负载终端，记录 60 秒 idle。
2. `Launchpad/backdrop` 打开 60 秒，记录 real blur 相对 idle 的 GPU util、power、niri CPU 和显存变化。
3. 背后窗口持续移动 15 秒，确认是否出现 stutter 和 texture realloc。
4. Overview open/close 和 workspace animation 中采样。
5. 背后播放视频或动态内容时采样。
6. VM 与真机各测一次。

建议进入条件：

- 大面积 backdrop 相对干净 idle 持续增加超过 `10-15` 个百分点 GPU util，或超过 `5 W` power。
- 用户可见 stutter 仍存在，且降低 material refraction/lens/blur 后不能解决。
- niri log 或 tracing 显示问题集中在大面积 framebuffer capture/blur，而不是动态壁纸、Quickshell QML、终端或其它应用。

如果这些条件不满足，static blur 继续保持不实现。

