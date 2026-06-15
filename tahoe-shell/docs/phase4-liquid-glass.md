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
- Quickshell layer-shell panels: framebuffer blur with light tint/highlight, `refraction 0.022`.

2026-06-15 glass redo:

- Refraction clamp increased from `0.05` to `0.12` in `postprocess.frag`.
- The old center-vector displacement was replaced with a pseudo height-field normal built from a glass dome, rim falloff, and value-noise turbulence.
- Edge highlight now uses that normal with a top-left light vector, specular response, rim light, and a small caustic term instead of fixed top/left bands only.
- Refraction sampling is clamped in `clipped_surface.frag` so stronger displacement does not sample outside the texture edge.
- QML panel fills/strokes were reduced slightly because compositor glass now supplies more of the visible highlight.

Real-machine follow-up items:

- Verify multi-monitor layer-shell blur regions on every output.
- Verify fractional scale alignment for blur regions, rounded clipping, and edge highlights.
- Compare Hyper-V blur/FPS results against real GPU behavior before tuning shader cost.
- Compare the stronger shader against real GPU behavior before raising blur/refraction further.
- Decide whether coordinate-space refraction still needs a dedicated sampled-surface shader after real-machine review.
