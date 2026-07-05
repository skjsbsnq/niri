# Tahoe Daily Desktop Phase 6 Acceptance

Date: 2026-06-19

Scope: Phase 6 from `sequential-daily-desktop-roadmap-2026-06-19.md`: add Tahoe-owned Settings, About, and system health surfaces with real dependency diagnostics and persisted desktop preferences.

## Implementation

- Added `tahoe-shell/services/DesktopSettings.qml`.
  - Persists desktop preferences to Quickshell state as `desktop-settings.json`.
  - Stores Dock window title mode, screenshot save directory, screenshot copy/action toggles, and startup note.
  - Exposes the XDG autostart folder opener.
- Added `tahoe-shell/services/SystemStatus.qml`.
  - Runs real probes for Desktop Portal, PipeWire, NetworkManager, Bluetooth, UPower, fcitx5, screenshot tools, clipboard tools, SNI, legacy tray bridge, xwayland-satellite, and niri IPC.
  - Collects About data for repo commit, niri/quickshell submodule commits, runtime versions, GPU, session, backend, and Quickshell state path.
- Added `tahoe-shell/components/SettingsPanel.qml`.
  - Provides Tahoe Settings, System Health, and About pages in a single overlay surface.
  - Settings page controls appearance, night mode/color temperature, DND, notification history, input method refresh/toggle, screenshot directory/options, Dock title preference, and startup folder/notes.
  - Health page shows explicit ok/warn/missing rows with impact and remediation text.
  - About page shows version, commit, submodule, runtime, GPU, session, backend, and state information.
- Updated existing services and components.
  - `Appearance.qml` now exposes `setColorTemperature()`.
  - `Screenshot.qml` reads persisted screenshot directory/copy/action preferences.
  - `Dock.qml` reads the persisted Dock icon-only preference while preserving the Phase 2 no-overflow budget.
  - `MenuPopup.qml` opens Tahoe About and Settings instead of closing placeholder rows.
  - `Search.qml` prioritizes internal Tahoe Settings, System Health, and About results, while retaining external system settings entries.
  - `shell.qml` owns Settings overlay state, adds `openSettings`, `openAbout`, `openSystemHealth`, and `closeSettings` IPC functions, and wires menu/Search activation to the overlay.

## Acceptance

- Missing dependencies are shown as real probe results, not static green statuses.
  - Health rows include the missing component, affected feature, and suggested remediation.
  - Optional degraded states are represented as warnings, e.g. screenshot works without `swappy` but annotation is unavailable.
- Settings persist through Quickshell state.
  - Live state file created at `/home/wwt/.local/state/quickshell/by-shell/tahoe/desktop-settings.json`.
  - Default contents include `dockWindowTitleMode`, `screenshotDirectory`, `screenshotCopyToClipboard`, `screenshotOfferActions`, and `startupNote`.
- Settings/About/Health are reachable from shell-level entry points.
  - Tahoe menu rows now emit Settings/About requests.
  - Spotlight provider results now emit internal Settings/About/Health requests.
  - IPC exposes `openSettings`, `openAbout`, `openSystemHealth`, and `closeSettings`.
- The new overlay uses explicit namespace `tahoe-settings`, overlay layer, bounded TahoeGlass region, and the existing modal close model.

## Runtime Checks

- `git diff --check -- tahoe-shell/services/DesktopSettings.qml tahoe-shell/services/SystemStatus.qml tahoe-shell/components/SettingsPanel.qml tahoe-shell/components/Screenshot.qml tahoe-shell/components/Dock.qml tahoe-shell/components/MenuPopup.qml tahoe-shell/services/Search.qml tahoe-shell/services/Appearance.qml tahoe-shell/shell.qml`: exited `0`.
- `bash scripts/check-tahoe-glass-guardrails.sh`: exited `0`.
- `bash scripts/check-submodules.sh`: exited `0`.
  - The script still prints git's `submodule` usage during its dry-run probe, then continues and exits `0`; this is pre-existing script behavior.
- `niri/target/release/niri validate -c config/niri/tahoe-phase0.kdl`: exited `0`.
- `qmllint` on new/changed QML files exited `0`; warnings were limited to unresolved Quickshell imports/types in the system Qt lint environment.
- Deployed current Tahoe shell to `/home/wwt/.config/quickshell/tahoe` with `rsync -a`.
- Restarted the live Tahoe Quickshell instance.
  - Old instance: `fyx1jocugt` / PID `90663`.
  - New instance: `wp72pfdugt` / PID `103316`.
  - Foreground load reached `Configuration Loaded`; timeout exit `124` was expected.
  - Existing warnings remained: duplicate Behavior interceptor warnings, `Qt.application.font` read-only warning, and portal app-id warning.
  - No `SettingsPanel`, `DesktopSettings`, `SystemStatus`, `Search`, `MenuPopup`, `Screenshot`, or `Dock` load failure appeared.
- `quickshell ipc -p /home/wwt/.config/quickshell/tahoe show` lists the new `openSettings`, `openAbout`, `openSystemHealth`, and `closeSettings` functions.
- IPC smoke:
  - `openSettings` opened a `tahoe-settings` overlay layer with keyboard interactivity `OnDemand`.
  - `openSystemHealth` opened the same overlay path.
  - `openAbout` opened the same overlay path.
  - `closeSettings` returned the layer list to resting `tahoe-wallpaper`, `tahoe-topbar`, and `tahoe-dock`.
- After deploy, `diff -qr /home/wwt/niri/tahoe-shell /home/wwt/.config/quickshell/tahoe` exited `0`.

## Residual Risk

- Physical pointer/keyboard smoke through the Tahoe menu and Spotlight was not automated because no Wayland input automation tool is installed in this environment.
- The same open path was verified through IPC; menu and Spotlight both route to that shell function in source.
