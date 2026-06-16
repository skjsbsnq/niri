# Phase 4 Liquid Glass Notes

Windows-side implementation status:

- Quickshell panels use `BackgroundEffect.blurRegion` on Dock, TopBar, Control Center, and Launchpad surfaces.
- Quickshell layer-shell panels force `xray false` so the effect samples the real framebuffer behind the panel instead of only the workspace backdrop.
- Dock, TopBar, and Control Center now use lower-alpha QML fills so compositor blur remains visible.
- niri `background-effect` still owns blur/noise/saturation and now carries glass tint, edge highlight, and refraction parameters.
- The existing `postprocess.frag` path is still sufficient; the 2026-06-15 redo keeps the effect in the current postprocess shader rather than adding a new shader file.
- Active windows, inactive windows, popups, and Quickshell layer-shell panels use separate glass strengths in `config/niri/tahoe-phase0.kdl`.

Compositor parameters added under `background-effect`:

- `tint-color`: unpremultiplied glass tint color.
- `tint-amount`: blend amount for the tint color.
- `edge-highlight`: strength for top/edge lighting in the postprocess shader.
- `refraction`: small sampling offset used as a displacement prototype.

Current Tahoe defaults:

- Global blur: `passes 5`, `offset 7`, `noise 0.012`, `saturation 1.6`.
- Active windows: `saturation 1.62`, light blue tint, stronger normal-based edge highlight, `refraction 0.032`.
- Inactive windows: `saturation 1.32`, lower tint/highlight, `refraction 0.014`.
- Popups: brighter tint/highlight than normal windows, `refraction 0.030`.
- Quickshell layer-shell panels: framebuffer blur with light tint/highlight, `refraction 0.006`.

2026-06-15 glass redo:

- Refraction clamp increased from `0.05` to `0.12` in `postprocess.frag`.
- The old center-vector displacement was replaced with a pseudo height-field normal built from a glass dome, rim falloff, and value-noise turbulence.
- Edge highlight now uses that normal with a top-left light vector, specular response, rim light, and a small caustic term instead of fixed top/left bands only.
- Refraction sampling is clamped in `clipped_surface.frag` so stronger displacement does not sample outside the texture edge.
- QML panel fills/strokes were reduced slightly because compositor glass now supplies more of the visible highlight.

2026-06-15 VMware large-surface safety pass:

- The shader rim is now pixel-sized instead of a fixed percentage of the glass rectangle. This prevents full-screen Launchpad and half-screen snap previews from showing huge rim bands.
- Dome/specular detail fades out on large surfaces, so big overlays become stable frosted glass instead of one giant lens.
- Snap preview glass parameters were reduced to match the safer Quickshell layer values.

Real-machine follow-up items:

- Verify multi-monitor layer-shell blur regions on every output.
- Verify fractional scale alignment for blur regions, rounded clipping, and edge highlights.
- Compare Hyper-V blur/FPS results against real GPU behavior before tuning shader cost.
- Compare the stronger shader against real GPU behavior before raising blur/refraction further.
- Decide whether coordinate-space refraction still needs a dedicated sampled-surface shader after real-machine review.

2026-06-17 Phase 4 liquid glass (rounded-rect SDF + inner shadow + chromatic + lens depth + per-region interaction):

- Added `niri/src/render_helpers/shaders/rounded_rect_sdf.frag`, a standard iquilezles rounded-box SDF (`niri_sd_rounded_rect` + outward `niri_sd_rounded_rect_grad`) with per-corner selection mirroring `rounding_alpha.frag`. This is the key fix: the edge highlight, refraction offset, and inner shadow previously measured distance to the axis-aligned bounding rectangle, so they did not line up with the rounded corners. They now measure distance to the rounded shape.
- `postprocess.frag` gains three material uniforms: `inner_shadow`, `chromatic`, `lens_depth`.
  - `inner_shadow` drives a shader-generated bottom-right inner shadow: the SDF outward normal dotted against a bottom-right light direction, concentrated in the inner edge band (`glass_inner_shadow`, clamped 0.5). This replaces the Android reference's knockout+blur technique with a cheaper, stable in-shader term.
  - `lens_depth` adds a center radial lens bulge to `niri_refraction_offset` (circular-eased, faded on large surfaces), giving center magnification (clamped 0.3).
  - All new terms reuse `glass_surface_detail()` so they fade out on large surfaces (Launchpad backdrop, snap preview) and stay safe on VMware/software GPU.
- `clipped_surface.frag` gains chromatic aberration: when `chromatic > 0` the background sample is split into three R/G/B taps along the refraction direction (clamped 0.1, +2 texture taps). `chromatic` is declared once and shared between the two programs; defaults to 0 so there is no extra cost at rest.
- New per-material config knobs in `niri-config` (`BackgroundEffect{,Rule}` + `TahoeGlassMaterialRule`): `inner-shadow`, `chromatic`, `lens-depth`. `GlassOptions` carries them through to the uniforms; both `framebuffer_effect.rs` and `xray.rs` uniforms grew from `[11]` to `[14]`. The non-postprocess `clipped_surface` stub program keeps its single-sample path because `chromatic` defaults to 0.
- Protocol bumped v1 → v2: `set_region` gained an `interaction` `fixed` arg (0..1). niri clamps it to [0,1] and, in `render_helpers/tahoe_glass.rs::render_region`, scales `edge_highlight`/`refraction`/`inner_shadow`/`chromatic`/`lens_depth` by `(1 + interaction)` — compositor-internal material easing, no shader or region-geometry change. The quickshell fork (regenerated protocol + QML `interaction` property on `TahoeGlassRegion`) drives it from QML.
- QML demos: `Dock.qml` binds the dock region's `interaction` to `dockHovered` (glass intensifies on hover); `NotificationToast.qml` binds the card region's `interaction` to `card.opacity` (glass eases in/out with the toast). Other regions stay at `interaction: 0`.
- Snap preview (`layout/mod.rs`) gained `inner-shadow`/`lens-depth` (alpha-scaled) and `chromatic 0.0`.
- `tahoe-phase0.kdl` now sets conservative non-zero values for the new params per material (backdrop stays 0 — fullscreen should not warp).

Shader parameter → uniform mapping (clamps shown):

| config knob | uniform | clamp |
|---|---|---|
| `edge-highlight` | `edge_highlight` → `glass_light_strength` | 2.0 |
| `refraction` | `refraction` → `niri_refraction_offset` | 0.12 |
| `inner-shadow` | `inner_shadow` → `glass_inner_shadow` | 0.5 |
| `chromatic` | `chromatic` → RGB-split taps in `clipped_surface.frag` | 0.1 |
| `lens-depth` | `lens_depth` → radial bulge in `niri_refraction_offset` | 0.3 |
| (`interaction`, per-region) | scales the five above by `(1 + interaction)` | 0..1 |

Phase 4 follow-up items:

- Tune the new params on real hardware; the config values are starting points.
- Verify the dock-hover and toast-enter interaction easing reads as intended.
- Consider wiring `interaction` to ControlCenter open, Spotlight focus, and popup open if the easing proves useful.
