# Tahoe Daily Desktop Phase 3 Acceptance

Date: 2026-06-19

Scope: Phase 3 from `sequential-daily-desktop-roadmap-2026-06-19.md`: add Dock running-window context menus and reliable target-window management actions.

## Implementation

- Added `tahoe-shell/components/DockWindowMenu.qml`.
  - Uses the same fullscreen transparent popup model, Tahoe glass region, panel radius, row sizing, outside-click close behavior, and bottom Dock anchoring style as the fixed-app Dock menu.
  - Keeps a separate window action model from `DockAppMenu.qml`: display/restore, minimize, pin/unpin app, close window, and move to workspace.
  - Shows disabled rows for actions that do not have a reliable target, such as close and workspace move when a window has no niri id.
  - Lists target workspaces from the niri workspace event model; the current workspace row is disabled and marked as current.
- Updated `tahoe-shell/components/WindowButton.qml`.
  - Right click now emits `contextMenuRequested(window)` instead of directly pinning the app.
  - Left click activate/restore/toggle-minimize and middle click minimize are unchanged.
- Updated `tahoe-shell/components/Dock.qml`.
  - Added `openWindowMenu(window, anchorRect)` and routes `WindowButton.contextMenuRequested` through the existing Dock anchor rectangle helper.
  - The Phase 2 width/magnification constraints remain unchanged; the window delegate still has fixed geometry.
- Updated `tahoe-shell/shell.qml`.
  - Added window menu state, per-screen open checks, and mutual popup closing with the existing top bar and Dock app menu close model.
  - Instantiates `DockWindowMenu` for each screen.
- Updated `tahoe-shell/services/Windows.qml`.
  - Added `closeWindow(window)` using `niri msg action close-window --id <id>`.
  - Added `moveWindowToWorkspace(window, workspace, focus)` using `niri msg action move-window-to-workspace --window-id <id> --focus false <reference>`.
  - Added workspace list normalization, display labels, action references, current-workspace checks, and `hasWindowId()`.
  - Renamed the internal event-stream removal helper to `removeClosedWindow()` so UI close action and IPC close events are separate.
- Updated `tahoe-shell/services/Apps.qml`.
  - Added window-level app lookup and `isWindowPinned()`, `unpinWindow()`, and `togglePinnedWindow()` helpers.
  - Existing pinned-state persistence still flows through `setPinnedIds()` and the same JSON state file.

## Target Safety

- Close and workspace move are enabled only when the menu target has a niri window id.
- The close row calls `close-window --id`, not focus-window plus close, so it does not rely on whichever window happens to be focused later.
- Workspace move uses workspace name when present and falls back to `idx`, not the internal workspace id, matching niri's workspace reference semantics.
- Pure foreign-toplevel fallback windows can still show, restore, minimize, and pin/unpin when enough data exists; id-only niri actions remain disabled.

## Runtime Checks

- `git diff --check -- tahoe-shell/services/Windows.qml tahoe-shell/services/Apps.qml tahoe-shell/components/WindowButton.qml tahoe-shell/components/Dock.qml tahoe-shell/components/DockWindowMenu.qml tahoe-shell/shell.qml`: exited `0`.
- `bash scripts/check-tahoe-glass-guardrails.sh`: exited `0`.
- `bash scripts/check-submodules.sh`: exited `0`.
  - Directly executing `scripts/check-submodules.sh` still fails with permission denied because the script is not executable; running it through `bash` is the expected path.
  - The script still prints git's `submodule` usage during its dry-run probe, then continues and exits `0`; this is pre-existing script behavior.
- Temporary QML load:
  - `timeout 8s quickshell/build-tahoe/src/quickshell --no-color --path /home/wwt/niri/tahoe-shell`
  - Reached `Configuration Loaded`; exit `124` was from `timeout`.
  - Existing warnings remained: duplicate Behavior interceptor warnings, `Qt.application.font` read-only warning, notification daemon conflict, and portal app-id warning. No new Dock window menu parse/load failure appeared.
- Verified niri action shape:
  - `niri msg action close-window --help` exposes `--id <ID>`.
  - `niri msg action move-window-to-workspace --help` exposes `--window-id <WINDOW_ID>` and `--focus`.
- Current IPC data during verification:
  - `niri msg --json windows` showed 6 windows with concrete ids.
  - `niri msg --json workspaces` showed 4 workspaces on `eDP-2` with `idx` values.
- Deployed current QML to `/home/wwt/.config/quickshell/tahoe` with `rsync -a --delete tahoe-shell/ /home/wwt/.config/quickshell/tahoe/` and restarted Quickshell.
  - New instance: PID `62057`, config `/home/wwt/.config/quickshell/tahoe/shell.qml`.
  - `niri msg --json layers` showed the expected resting layer set: `tahoe-wallpaper`, `tahoe-topbar`, `tahoe-dock`.

## Manual Acceptance Notes

- No Wayland input automation tool is available on this machine (`ydotool`, `dotool`, `wtype`, `wl-click`, and `wlrctl` are absent), so the physical right-click-and-select flow was not robotically clicked in this run.
- The deployed shell loaded successfully with the new menu component present at `/home/wwt/.config/quickshell/tahoe/components/DockWindowMenu.qml`.
- Expected manual smoke path:
  1. Right-click any running window button in the Dock.
  2. Confirm the Tahoe menu opens above that exact Dock button.
  3. Confirm display/restore, minimize, pin/unpin, close, and workspace rows show enabled or disabled states according to the target window.
  4. Use close only on a disposable test window; it should close that target window, not the focused window.
  5. Move a test window to another workspace and confirm the current workspace row is disabled.
  6. Right-click a fixed app icon and confirm the Phase 1 fixed-app unpin menu still opens separately.
