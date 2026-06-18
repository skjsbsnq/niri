# Tahoe Daily Desktop Phase 4 Acceptance

Date: 2026-06-19

Scope: Phase 4 from `sequential-daily-desktop-roadmap-2026-06-19.md`: add Tahoe-owned task switching and window overview UI while keeping niri's native overview available.

## Implementation

- Added `tahoe-shell/components/TaskSwitcher.qml`.
  - Uses `Windows.qml.recentWindowList` as the only window source.
  - Shows a centered Tahoe glass switcher with app icon, title, workspace/output details, focused/minimized state, keyboard selection, mouse hover selection, and click activation.
  - Restores minimized windows through `Windows.restore(window)` and activates normal windows through `Windows.activate(window)`.
  - Handles Tab, Shift+Tab, arrow keys, Enter/Space, Escape, and modifier-release confirmation when opened in keyboard mode.
- Added `tahoe-shell/components/WindowOverview.qml`.
  - Uses `Windows.qml.windowList` and `Windows.qml.workspaceList`.
  - Groups cards by workspace/output and shows each window's icon, title, app id/minimized state, and niri layout geometry.
  - Recomputes groups from the live model so closed windows and workspace changes do not keep stale cards.
- Updated `tahoe-shell/shell.qml`.
  - Added a `tahoe` `IpcHandler` target with task-switcher and overview functions.
  - Routes both overlays to the focused output when niri provides one.
  - Integrates the overlays with the existing popup close model, so Dock menus, top-bar popups, Spotlight, and Launchpad close the navigation overlays.
- Updated `config/niri/tahoe-phase0.kdl`.
  - Keeps `Mod+O { toggle-overview; }` for niri's native overview.
  - Leaves niri `recent-windows` default `Mod+Tab` / `Mod+Shift+Tab` MRU bindings untouched.
  - Adds `Mod+Ctrl+Tab` and `Mod+Ctrl+Shift+Tab` for Tahoe task switching.
  - Adds `Mod+Shift+O` for Tahoe window overview.
  - Uses the deployed Tahoe Quickshell config path with `quickshell ipc -p "$TAHOE_CONFIG_DIR"` instead of relying on a nonexistent default config.

## Target Safety

- No second window model was introduced; both views consume `Windows.qml`.
- No screencopy or live texture path was added in this phase; overview cards use existing metadata and geometry only.
- Window activation remains routed through existing `Windows.activate()` / `Windows.restore()` wrappers.
- niri's compositor overview and recent-window machinery remain available; Tahoe only adds separate UI entry points.
- New layer surfaces use explicit `tahoe-task-switcher` and `tahoe-window-overview` namespaces and bounded TahoeGlass regions.

## Runtime Checks

- `git diff --check -- tahoe-shell/components/TaskSwitcher.qml tahoe-shell/components/WindowOverview.qml tahoe-shell/shell.qml config/niri/tahoe-phase0.kdl`: exited `0`.
- `bash scripts/check-tahoe-glass-guardrails.sh`: exited `0`.
- `bash scripts/check-submodules.sh`: exited `0`.
  - The script still prints git's `submodule` usage during its dry-run probe, then continues and exits `0`; this is pre-existing script behavior.
- `niri/target/release/niri validate -c config/niri/tahoe-phase0.kdl`: exited `0`.
- Temporary QML load:
  - `timeout 8s /home/wwt/.local/bin/quickshell --no-color --path /home/wwt/niri/tahoe-shell`
  - Reached `Configuration Loaded`; exit `124` was from `timeout`.
  - Existing warnings remained: duplicate Behavior interceptor warnings, `Qt.application.font` read-only warning, notification daemon conflict during temp load, and portal app-id warning. No TaskSwitcher or WindowOverview parse/load failure appeared.
- Deployed current QML to `/home/wwt/.config/quickshell/tahoe` and restarted Quickshell.
  - New instance: PID `75514`, config `/home/wwt/.config/quickshell/tahoe/shell.qml`.
  - `quickshell ipc -p /home/wwt/.config/quickshell/tahoe show` lists target `tahoe` with `openTaskSwitcher`, `cycleTaskSwitcher`, `showTaskSwitcher`, `openWindowOverview`, `toggleWindowOverview`, and close functions.
- Deployed current Tahoe niri config to `/home/wwt/.config/niri/tahoe/config.kdl`.
  - `niri msg action load-config-file` exited `0`.
  - `niri msg action reload-config` is not available in this niri build; `load-config-file` is the supported reload action.
- IPC smoke:
  - `openWindowOverview` opened a `tahoe-window-overview` overlay layer with keyboard interactivity `OnDemand`.
  - `cycleTaskSwitcher 1` opened a `tahoe-task-switcher` overlay layer with keyboard interactivity `OnDemand`.
  - `cycleTaskSwitcher -1` succeeded while the switcher was open.
  - `closeWindowOverview` and `closeTaskSwitcher` returned the layer list to the resting `tahoe-wallpaper`, `tahoe-topbar`, and `tahoe-dock` surfaces.
- Current IPC data during verification:
  - `niri msg --json windows` showed 6 windows with concrete ids, workspace ids, app ids, focus state, and geometry.
  - `niri msg --json workspaces` showed 4 workspaces on `eDP-2`.

## Manual Acceptance Notes

- No Wayland input automation tool is installed on this machine (`ydotool`, `dotool`, `wtype`, `wl-click`, and `wlrctl` are absent), so physical `Mod+Ctrl+Tab` release confirmation was not robotically tested.
- The QML release-confirm path is implemented in `TaskSwitcher.qml` via modifier key release while `keyboardMode` is active.
- Expected physical smoke:
  1. Press `Mod+Ctrl+Tab`; Tahoe switcher should open on the focused output and select a recent window.
  2. Press `Mod+Ctrl+Tab` or `Mod+Ctrl+Shift+Tab` again while it is open; selection should cycle predictably.
  3. Release the modifier or press Enter; the selected window should activate, restoring it first if minimized.
  4. Press Escape; the switcher should close without activating a different window.
  5. Press `Mod+Shift+O`; Tahoe overview should open, group windows by workspace/output, and clicking a card should activate that window across workspaces.
