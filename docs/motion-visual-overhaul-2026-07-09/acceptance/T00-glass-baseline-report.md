# Tahoe glass Phase 0 runtime baseline

- Generated local time: `2026-07-09 13:00:21 +0800`
- Generated UTC: `2026-07-09 05:00:21 UTC`
- Host: `unknown`
- User: `wwt`
- Repo: `/home/wwt/niri`

Reference screenshots are tracked under:

- `tahoe-shell/docs/visual-baselines/2026-06-15-phase0-glass-geometry/spotlight-search-halo.png`
- `tahoe-shell/docs/visual-baselines/2026-06-15-phase0-glass-geometry/notification-center-rectangular-backing.png`
- `tahoe-shell/docs/visual-baselines/2026-06-15-phase0-glass-geometry/control-center-rectangular-backing.png`

## Root repo

- Path: `/home/wwt/niri`
- HEAD: `e736f52813d8c11b019a52b60b8389e6ab6ea0b5`
- Branch: `main`
- Last commit: `e736f52 Update quickshell Bluetooth pairing fix`

### Status

```text
## main...origin/main
 M tahoe-shell/tests/test_motion_default_policy.py
?? docs/motion-visual-overhaul-2026-07-09/
?? tahoe-shell/services/__pycache__/
?? tahoe-shell/tests/__pycache__/

```

## niri submodule

- Path: `/home/wwt/niri/niri`
- HEAD: `571fe4fa4f5f6b373a95c3a2ea463b53db97f2e4`
- Branch: `tahoe-layer-animations`
- Last commit: `571fe4fa Fix maximized window drag and stacking`

### Status

```text
## tahoe-layer-animations...origin/tahoe-layer-animations

```

## Quickshell submodule

- Path: `/home/wwt/niri/quickshell`
- HEAD: `87a45905d69d680ba492b1da651b4e935f0c372b`
- Branch: `quickshell-tahoe-desktop`
- Last commit: `87a4590 Fix Bluetooth pairing flow`

### Status

```text
## quickshell-tahoe-desktop...origin/quickshell-tahoe-desktop

```

## Baseline screenshot assets

- Directory: `/home/wwt/niri/tahoe-shell/docs/visual-baselines/2026-06-15-phase0-glass-geometry`

| File | SHA-256 |
| --- | --- |
| `(baseline directory missing)` | `(missing)` |

## Tahoe config hashes

| File | SHA-256 |
| --- | --- |
| `/home/wwt/niri/config/niri/tahoe-phase0.kdl` | `dfd7df4f818c713304a46b727d7292c68a174ecd05f90394da2c843f64331a48` |
| `/home/wwt/.config/niri/tahoe/config.kdl` | `dfd7df4f818c713304a46b727d7292c68a174ecd05f90394da2c843f64331a48` |
| `/home/wwt/.config/quickshell/tahoe/shell.qml` | `4ff4ce8af47ea1cd44763c351d853e2249e0a12f560abfcd63d135e12ea4f686` |

## Session environment

```text
XDG_SESSION_TYPE=wayland
XDG_CURRENT_DESKTOP=niri
WAYLAND_DISPLAY=wayland-1
DISPLAY=:1
NIRI_SOCKET=/run/user/1000/niri.wayland-1.1239.sock
TAHOE_CONFIG_DIR=/home/wwt/.config/quickshell/tahoe
NIRI_CONFIG_TARGET=/home/wwt/.config/niri/tahoe/config.kdl
```

## niri version

Command: `niri --version`

```text
niri 26.04 (571fe4fa)

```

## quickshell version

Command: `quickshell --version`

```text
Quickshell 0.3.0 (revision 87a45905d69d680ba492b1da651b4e935f0c372b, distributed by Tahoe fork)

```

## niri focused output

Command: `niri msg focused-output`

```text
Output "Thermotrex Corporation TL160ADMP11-0 Unknown" (eDP-2)
  Current mode: 2560x1600 @ 239.998 Hz
  Variable refresh rate: supported, disabled
  Physical size: 350x220 mm
  Logical position: 0, 0
  Logical size: 2048x1280
  Scale: 1.25
  Transform: normal
  Available modes:
    2560x1600@59.999 (preferred)
    2560x1600@239.998 (current)

```

## niri outputs

Command: `niri msg outputs`

```text
Output "Thermotrex Corporation TL160ADMP11-0 Unknown" (eDP-2)
  Current mode: 2560x1600 @ 239.998 Hz
  Variable refresh rate: supported, disabled
  Physical size: 350x220 mm
  Logical position: 0, 0
  Logical size: 2048x1280
  Scale: 1.25
  Transform: normal
  Available modes:
    2560x1600@59.999 (preferred)
    2560x1600@239.998 (current)


```

## niri outputs JSON

Command: `niri msg --json outputs`

```text
{"eDP-2":{"name":"eDP-2","make":"Thermotrex Corporation","model":"TL160ADMP11-0","serial":null,"physical_size":[350,220],"modes":[{"width":2560,"height":1600,"refresh_rate":59999,"is_preferred":true},{"width":2560,"height":1600,"refresh_rate":239998,"is_preferred":false}],"current_mode":1,"is_custom_mode":false,"vrr_supported":true,"vrr_enabled":false,"logical":{"x":0,"y":0,"width":2048,"height":1280,"scale":1.25,"transform":"Normal"},"max_bpc":null}}

```

## pacman niri package

Command: `pacman -Q niri`

```text
niri 26.04-1

```

## pacman quickshell packages

Command: `pacman -Q quickshell quickshell-git quickshell-xdg`

```text
错误：软件包 'quickshell' 未找到
警告：'quickshell' 是一个文件，您可能打算使用 -p/--file。
错误：软件包 'quickshell-git' 未找到
错误：软件包 'quickshell-xdg' 未找到

```

