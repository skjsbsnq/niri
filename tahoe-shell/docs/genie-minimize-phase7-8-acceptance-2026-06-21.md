# Genie minimize Phase 7/8 acceptance

Date: 2026-06-21

Scope: Tahoe Dock + niri Genie minimize/restore visual tuning, performance guardrails, tests, and documentation.

## Phase 7 status

Implemented in niri:

- `src/render_helpers/shaders/genie.frag`
  - Bottom edge still leads the top edge, but with a softer curve to avoid a snap into the Dock.
  - Top edge lag is reduced enough to keep the pulled-into-Dock feel without a hard stretch.
  - End fade waits until the final 12% of the morph so the motion reads as continuous.
  - Target-side x/y squash is subtle, keeping the last visible frames from becoming a hard rectangle.
- `src/layout/minimize_window_animation.rs`
  - Shader draw area remains `window_rect union target_rect + 24px padding`.
  - Unit tests cover the bounded area calculation so future edits do not accidentally damage/draw the whole output.
  - Valid Genie target/source rectangles use a smoother curve and at least 320 ms duration, while no-rect fallback fade keeps the normal window animation timing.

Fallback behavior:

- Missing Dock rectangle: use the normal fade path.
- Empty target/source rectangle: clear the saved foreign-toplevel rect and use the normal path.
- Rectangle from another output: snapshot workspace filtering drops it before Genie rendering.
- Genie shader compile failure: rendering falls back to texture fade.

Known limitations:

- Real 60fps confirmation still depends on the physical GPU/session. Use the script below and niri damage debug when testing VMware, Hyper-V, or other low-end renderers.
- The first visual tuning target is stable, restrained Genie motion. Exact macOS/GNOME parity is intentionally left for later visual iteration.

## Phase 8 status

Automated guardrails added:

- Layout state:
  - `minimize_restore_with_rect_keeps_ipc_layout`
  - `repeated_minimize_restore_with_rect_keeps_ipc_layout`
- XDG minimize:
  - Native window minimize requests keep working and now consume the saved Dock rectangle when one is available.
- Foreign toplevel rectangle behavior:
  - Valid layer-surface rect is stored in output logical coordinates.
  - Minimize/restore preserves the saved rect.
  - Empty rect clears it.
  - Non-layer source surface clears stale rect state.
  - Destroyed Dock layer surface clears stale rect state.
- Shader area:
  - `genie_area_is_window_target_union_with_padding`
  - `genie_area_does_not_expand_beyond_local_union`
- Genie timing:
  - `genie_animation_config_slows_valid_target_rect`
  - `genie_animation_config_preserves_fallback_fade`

Manual test entrypoint:

```sh
scripts/check-genie-minimize-phase7-8.sh
```

The script runs the targeted cargo tests and prints the required visual matrix:

- floating
- scrolling
- multi-output
- fractional scale
- CSD shadow
- SSD/borderless
- minimized restore
- rapid repeated clicks
- Dock restart
- performance/damage area check

User-facing documentation:

- niri animation docs now note that Tahoe builds use `window-close` timing for minimize and `window-open` timing for restore.
- The docs record fallback behavior for missing/invalid Dock rects, cross-output rects, and shader unavailability.

## Acceptance commands

Run from the repository root:

```sh
scripts/check-genie-minimize-phase7-8.sh
```

Or run individual niri tests:

```sh
cd niri
cargo test -p niri minimize_restore_with_rect
cargo test -p niri genie_area
cargo test -p niri foreign_toplevel_set_rectangle_tracks_layer_surface_rect
cargo test -p niri xdg_toplevel_set_minimized_minimizes_window
```
