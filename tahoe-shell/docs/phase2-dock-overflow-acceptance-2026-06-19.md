# Tahoe Daily Desktop Phase 2 Acceptance

Date: 2026-06-19

Scope: Phase 2 from `sequential-daily-desktop-roadmap-2026-06-19.md`: keep Dock contents inside the screen when pinned apps and running windows are numerous.

## Implementation

- Updated `tahoe-shell/components/Dock.qml`.
  - Added explicit Dock width budget properties for outer margin, glass padding, item spacing, pinned app width, window title width, window icon width, separators, and right-side tools.
  - The glass width remains capped by the output width minus the existing 28 px safety margin.
  - Running windows first degrade from titled buttons to icon-only buttons when titled width no longer fits.
  - Running windows are then constrained inside a horizontal `Flickable`; left click, middle click, right click, active state, minimized state, and magnification still target the original `WindowButton` delegates.
  - The pinned-app area also uses a horizontal `Flickable` only when the pinned list itself exceeds its budget. Pinned icon delegate width remains fixed at 62 px and still does not depend on magnification.
  - Downloads and Trash are outside the flexible sections, so they stay visible while pinned/window sections scroll.
- Updated `tahoe-shell/components/WindowButton.qml`.
  - Icon-only window buttons show a hover label so window identity is still available after title degradation.
  - Window button width remains fixed at 132 px with title and 56 px icon-only; neither width depends on magnification.

## Offset Regression Caught During Acceptance

The first implementation made the pinned/window `Flickable` itself 104 px tall so labels had vertical room. Because that `Flickable` participated directly in `dockRow` layout, the whole Dock content row was vertically centered against 104 px instead of the original 70/58 px delegates. User screenshots showed the resulting severe downward offset.

Fix: the `Flickable` now sits inside a fixed-height wrapper (`70` px for pinned apps, `58` px for window buttons). The wrapper participates in the `Row`; the inner `Flickable` is shifted upward only to provide hover-label clip space. Horizontal clipping/scrolling no longer changes Dock vertical geometry.

## Budget Checks

Computed scenarios using the same constants as `Dock.qml`:

| Logical width | Pinned apps | Windows | Window mode | Surface width | Safe max |
| --- | ---: | ---: | --- | ---: | ---: |
| 1366 | 10 | 16 | icon-only + window scroll | 1338 | 1338 |
| 1366 | 20 | 16 | icon-only + pinned/window scroll | 1338 | 1338 |
| 1366 | 20 | 0 | pinned scroll | 1338 | 1338 |
| 1920 | 10 | 16 | icon-only, all windows visible | 1892 | 1892 |
| 1920 | 20 | 16 | icon-only + window scroll | 1892 | 1892 |
| 3440 | 10 | 16 | titled windows | 3108 | 3412 |
| 3440 | 20 | 16 | icon-only, all windows visible | 2592 | 3412 |

## Runtime Checks

- `git diff --check -- tahoe-shell/components/Dock.qml tahoe-shell/components/WindowButton.qml tahoe-shell/components/DockAppMenu.qml tahoe-shell/shell.qml`: exited `0`.
- `bash scripts/check-tahoe-glass-guardrails.sh`: exited `0`.
- `bash scripts/check-submodules.sh`: exited `0`.
  - The script still prints git's `submodule` usage during its dry-run probe, then continues and exits `0`; this is pre-existing script behavior.
- Temporary QML load:
  - `timeout 5s /home/wwt/.local/bin/quickshell -p /home/wwt/niri/tahoe-shell --no-color --log-rules 'qml=true'`
  - Reached `Configuration Loaded`; exit `124` was from `timeout`.
  - Existing warnings remained: duplicate Behavior interceptor warnings, `Qt.application.font` read-only warning, and notification/portal duplicate-environment warnings. No new Dock parse/load failure appeared.
- Deployed current QML to `/home/wwt/.config/quickshell/tahoe` and restarted Quickshell.
  - New instance after final fix: PID `50617`, config `/home/wwt/.config/quickshell/tahoe/shell.qml`.
  - `niri msg --json layers` showed the expected resting layer set: `tahoe-wallpaper`, `tahoe-topbar`, `tahoe-dock`.
  - Screenshot after the offset fix: `/tmp/tahoe-phase2/dock-offset-fixed.png`.

## Manual Acceptance Notes

Current machine state at final verification:

- Output: `eDP-2`, logical `2048x1280`, scale `1.25`.
- Actual windows available during verification: 4.
- Actual screenshot confirms Dock is visible, centered on the bottom edge, and Downloads/Trash remain visible.

No Wayland input automation tool was available to create and interact with a 16+ window scenario without disrupting the active session. The 16-window and narrow-width acceptance was therefore verified by the deterministic budget calculation above plus QML load/runtime checks.
