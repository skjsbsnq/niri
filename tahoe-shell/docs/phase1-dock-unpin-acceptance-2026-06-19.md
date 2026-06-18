# Tahoe Daily Desktop Phase 1 Acceptance

Date: 2026-06-19

Scope: Phase 1 from `sequential-daily-desktop-roadmap-2026-06-19.md`: add a Dock right-click entry for removing pinned applications. No Dock overflow work was included.

## Implementation

- Added `tahoe-shell/components/DockAppMenu.qml`.
  - Tahoe-styled QML menu, not a native toolkit menu.
  - Actions are limited to `打开` and `从 Dock 移除`.
  - Uses a fullscreen transparent `PanelWindow` only while open so outside clicks close the menu.
  - Registers only the menu panel as the `TahoeGlassRegion`; the fullscreen click catcher is not a glass region.
- Updated `tahoe-shell/components/Dock.qml`.
  - Non-Launchpad pinned app right-click emits `openPinnedAppMenu(app, anchorRect)`.
  - Launchpad right-click is ignored for unpin, so it cannot be removed from pinned state.
  - Dock icon width, magnification, drag reorder, file drop, Downloads, and Trash logic were not changed.
- Updated `tahoe-shell/shell.qml`.
  - Tracks Dock app menu state per screen.
  - Adds `DockAppMenu` as a sibling surface beside `Dock`.
  - Integrates the Dock menu into the existing popup mutual-close path.

## Persistence Path

The menu calls existing `Apps.unpinApp(app)`. That path already calls `setPinnedIds(next)`, which writes `Quickshell.stateDir + "/pinned-apps.json"` and bumps the pinned model revision. The active Tahoe state file is:

- `/home/wwt/.local/state/quickshell/by-shell/tahoe/pinned-apps.json`

This run did not edit that user state file.

## Checks

- `bash scripts/check-submodules.sh`: exited `0`.
  - Direct execution of `scripts/check-submodules.sh` failed first because the file is not executable.
  - The script printed git's submodule usage for its dry-run probe, then continued and exited `0`.
- `bash scripts/check-tahoe-glass-guardrails.sh`: exited `0`.
- `git diff --check -- tahoe-shell/components/Dock.qml tahoe-shell/components/DockAppMenu.qml tahoe-shell/shell.qml`: exited `0`.
- Temporary QML load check:
  - `timeout 5s /home/wwt/.local/bin/quickshell -p /home/wwt/niri/tahoe-shell --no-duplicate --no-color`
  - Reached `Configuration Loaded`; exit `124` was from `timeout`.
  - Duplicate-start warnings about the notification server and existing spring/font warnings were observed; no new QML parse/load error for the Dock menu.
- Deployed current Phase 1 QML files to `/home/wwt/.config/quickshell/tahoe` and restarted Quickshell.
  - New instance: PID `33638`, config `/home/wwt/.config/quickshell/tahoe/shell.qml`.
  - `niri msg --json layers` showed the resting Tahoe layer set: `tahoe-wallpaper`, `tahoe-topbar`, `tahoe-dock`.

## Manual Acceptance Notes

No Wayland input automation tool is available on this machine (`ydotool`, `dotool`, and `wtype` are absent), and niri has no pointer-click action. Therefore the physical right-click-and-select flow was not robotically clicked in this run.

The loaded code path for that manual test is:

1. Right-click any non-Launchpad pinned Dock icon.
2. The `DockAppMenu` should appear above that icon with `打开` and `从 Dock 移除`.
3. Click `从 Dock 移除`.
4. The fixed launcher disappears immediately; any running windows remain in the running-window section.
5. Restart Quickshell and confirm the removed app remains absent from the pinned launcher list.

