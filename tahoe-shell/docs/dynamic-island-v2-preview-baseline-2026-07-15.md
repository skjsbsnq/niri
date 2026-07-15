# Dynamic Island V2 Preview Baseline (T10)

Date: 2026-07-15
Task: T10
Base SHA: `4091088dbabb7fecb86eec3e2deb2287523bc056`
Status: non-production visual token + static preview baseline

## Purpose

Freeze the reviewed “dark focus glass” direction **before** production Overlay/scene rewrites (T11+). Production shell behavior is unchanged in T10.

## Assets

| Path | Role |
| --- | --- |
| `tahoe-shell/preview/dynamic-island-v2/` | Interactive QML preview window |
| `tahoe-shell/docs/visual-baselines/dynamic-island-v2-preview/matrix/` | Offline SVG/PNG state matrix |
| `tahoe-shell/components/settings/SettingsTheme.js` | `island*` color tokens |
| `tahoe-shell/components/DynamicIslandMotion.js` | `v2*` motion/geometry tokens |

## Launch

```bash
qml tahoe-shell/preview/dynamic-island-v2/DynamicIslandV2Preview.qml
```

Preview guarantees:

- `registersIpc: false`
- no Notifications / MPRIS / niri socket
- not imported by `shell.qml`
- no `DynamicIslandTheme.js`
- no eighth material profile

## Color tokens (SettingsTheme)

| Token | Value / rule |
| --- | --- |
| `islandTextPrimary` | `#f7f8fa` |
| `islandTextSecondary` | `#aeb6c2` |
| `islandTextMuted` | `#7f8996` |
| `islandSurfaceFill(compact)` | `#cc10141a` (~80%) |
| `islandSurfaceFill(transient)` | `#d610141a` (~84%) |
| `islandSurfaceFill(expanded)` | `#df10141a` (~87%) |
| `islandSurfaceStroke` | `#24ffffff` → `#30ffffff` by role |
| `islandProgressTrack` | `#30ffffff` |
| `islandControlFill` | `#20ffffff` |
| accent | `SettingsTheme.accent(darkMode, accentId)` — no hard-coded `#b56cff` |

## Geometry / radius (DynamicIslandMotion `v2*`)

| State | Size band | Radius |
| --- | --- | --- |
| Resting clock | 112–136 × 32 | 16 |
| Compact media | 200–224 × 36 | 18 |
| OSD | 220–240 × 44 | 22 |
| Workspace | 140–168 × 36 | 18 |
| Notification compact | 300–420 × 60–80 | 22–26 |
| Media expanded | 404–432 × 160–172 | 28–32 |
| Notification expanded | 380–440 × 96–176 | 28–32 |
| Timer expanded | 340–380 × 136–152 | 28–32 |

Expanded radius is **capped 28–32**; never `height / 2` ellipses.

Compact top inset target: **y = 4** (`v2CompactTopInset`).

## Motion tokens (V2; production still uses legacy until T19)

| Token | Value |
| --- | --- |
| compact → transient | 240 ms |
| compact → expanded | 280 ms |
| expanded → compact | 240 ms |
| content exit | 110 ms |
| content enter | 170 ms |
| max content travel | 6 px |
| reduced geometry/content | 80 ms |
| whole-content scale 0.9→1 | **not** the V2 default |

## Mock state matrix (preview + offline)

Required kinds:

1. clock (zh / en)
2. compact media (playing / paused / long title)
3. OSD volume / muted / brightness 0 / brightness 100
4. notification short / long / critical
5. notification expanded + actions
6. expanded media (default / long metadata)
7. workspace
8. timer compact / expanded

Viewport / appearance matrix dimensions:

- logical widths: 1366, 1920, 2048
- scales: 1.0, 1.25
- locales: zh-CN, en-US
- shell modes: light, dark
- wallpaper simulation: bright, dark

Offline tiles are generated under `visual-baselines/dynamic-island-v2-preview/matrix/` by `test_dynamic_island_v2_preview.py` (SVG always; PNG when rsvg-convert/ImageMagick is available). See `matrix/MANIFEST.md` for SHA-256.

## Visual direction checklist

| Check | Expected |
| --- | --- |
| Not Tide pure-black capsule | deep neutral with glass-visible alpha |
| Not control-center light glass mini | dedicated island fill roles |
| Expanded shape | rounded panel (r≤32), not tall ellipse |
| Letter spacing | 0 only |
| OSD | horizontal bar + value, no ring |
| Expanded media | no fake sine visualizer |
| Notification | app identity leading, not generic bell-only |
| TopBar relationship | compact y≈4 over simulated 32px bar |

## Production impact

| Area | T10 change |
| --- | --- |
| `shell.qml` | none |
| `DynamicIslandOverlay.qml` | none |
| `DynamicIslandContent.qml` | none |
| Services | none |
| Deployment | none |

Additive-only exports in SettingsTheme / DynamicIslandMotion do not alter existing call sites until later tasks consume them.

## How to re-verify

```bash
git diff --check
PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider \
  tahoe-shell/tests/test_dynamic_island_v2_preview.py \
  tahoe-shell/tests/test_settings_theme_tokens.py \
  tahoe-shell/tests/test_motion_token_convergence.py
PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider
qml tahoe-shell/preview/dynamic-island-v2/DynamicIslandV2Preview.qml
```

## Offline matrix comparability

Offline SVG/PNG tiles intentionally vary rendered pixels across axes:

| Axis | Pixel difference |
| --- | --- |
| wallpaper bright/dark | canvas background `#d8e2ec` vs `#1a1c20` |
| shell light/dark | simulated top-bar chrome fill |
| scale 1.0 / 1.25 | capsule draw size = logical × scale |
| locale zh/en | label strings differ (clock, OSD, notification, media, timer) |
| viewport width | footer annotation + chrome width band |

Appearance product: locale × shell × wallpaper × scale × {1366,1920,2048} for compact-media.
Core states × locale on default dark/dark/s1.0/2048 including critical notification.

Interactive preview chips: light/dark shell, bright/dark wallpaper, zh/en, 1366/1920/2048, scale 1.0/1.25.
`MockStates.allStates(localeTag)` threads locale through every mock kind.
