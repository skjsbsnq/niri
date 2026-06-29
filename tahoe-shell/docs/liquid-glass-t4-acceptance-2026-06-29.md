# Liquid Glass T4 Acceptance

日期：2026-06-29

## 已完成

- 完整审计 `clipped_surface.frag` 与 `postprocess.frag` 的采样坐标和 region geometry 坐标关系。
- 折射位移继续在 clip-region geometry 坐标中计算，但采样点通过 `geo_to_input` 反变换回 texture/input 坐标，避免扩展采样 padding 改变 lens 强度。
- `FramebufferEffect` 和 `Xray` 都向 `postprocess_and_clip` shader 传入 `geo_to_input`。
- `chromatic` 默认继续为 `0`；当前 KDL material 和 fallback block 都显式保持 `chromatic 0.0`。
- 小 surface 在 shader 内有轻量 edge/refraction boost，大 surface 通过 `glass_surface_detail()` / `glass_large_surface_fade()` 自动衰减 refraction、lens、highlight 和 inner shadow。
- 已新增当前会话视觉基线目录：`tahoe-shell/docs/visual-baselines/2026-06-29-liquid-glass-t4/`。

## 关键代码点

- `niri/src/render_helpers/shaders/clipped_surface.frag`
  - 保持 `v_coords` 作为 texture/input 坐标。
  - 使用 `input_to_geo` 得到 clip-region `coords_geo`。
  - 使用 `niri_refraction_sample_coords(v_coords, coords_geo.xy)` 取得最终采样点。
- `niri/src/render_helpers/shaders/postprocess.frag`
  - 新增 `geo_to_input`。
  - 新增大 surface fade 和小 surface boost。
  - 把 refraction sample point 从 geometry 坐标映射回 input 坐标。
- `niri/src/render_helpers/framebuffer_effect.rs`
  - 对 framebuffer/crop path 传入 `input_to_geo` 和其 inverse `geo_to_input`。
- `niri/src/render_helpers/xray.rs`
  - 对 xray path 传入 `input_to_geo` 和其 inverse `geo_to_input`。

## 视觉基线限制

当前运行中的 niri 是已安装的 `26.04 (c205293c)`，不是本工作区 dirty shader 构建；截图只能记录当前会话状态。当前 Quickshell IPC 也未暴露 ControlCenter、Spotlight、Launchpad、NotificationToast 的 open/close，且系统缺少可用 Wayland 输入注入工具。

因此本轮已保存可获得的 TopBar/idle/notification-attempt 基线，并在 `visual-baselines/2026-06-29-liquid-glass-t4/README.md` 中记录未能自动触发的场景和原因。新 shader 的最终视觉验收需要在重启到本工作区构建的 niri 后重新采集。
