# Phase 4 Liquid Glass Notes

Windows-side implementation status:

- Quickshell panels use `BackgroundEffect.blurRegion` on Dock, TopBar, Control Center, and Launchpad surfaces.
- Quickshell layer-shell panels force `xray false` so the effect samples the real framebuffer behind the panel instead of only the workspace backdrop.
- Dock, TopBar, and Control Center now use lower-alpha QML fills so compositor blur remains visible.
- niri `background-effect` still owns blur/noise/saturation and now carries glass tint, edge highlight, and refraction parameters.
- The existing `postprocess.frag` path is sufficient for the first Liquid Glass pass; no new shader file is needed yet.
- Active windows, inactive windows, popups, and Quickshell layer-shell panels use separate glass strengths in `config/niri/tahoe-phase0.kdl`.

Compositor parameters added under `background-effect`:

- `tint-color`: unpremultiplied glass tint color.
- `tint-amount`: blend amount for the tint color.
- `edge-highlight`: strength for top/edge lighting in the postprocess shader.
- `refraction`: small sampling offset used as a displacement prototype.

Current Tahoe defaults:

- Active windows: stronger saturation, moderate tint, stronger edge highlight.
- Inactive windows: lower saturation, lower tint, lower edge highlight, minimal refraction.
- Popups: brighter tint and highlight than normal windows.
- Quickshell layer-shell panels: framebuffer blur with light tint/highlight.

Real-machine follow-up items:

- Verify multi-monitor layer-shell blur regions on every output.
- Verify fractional scale alignment for blur regions, rounded clipping, and edge highlights.
- Compare Hyper-V blur/FPS results against real GPU behavior before tuning shader cost.
- Decide whether true coordinate-space refraction should move from the current prototype into a dedicated sampled-surface shader.
