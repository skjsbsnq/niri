# Tahoe Daily Desktop Phase 7 Acceptance

Date: 2026-06-19

Scope: Phase 7 from `sequential-daily-desktop-roadmap-2026-06-19.md`: improve application compatibility diagnostics and add a real native app menu/dbus-menu path for the focused app.

## Implementation

- Added `tahoe-shell/services/appmenu_probe.py`.
  - Uses `busctl --user --json=short` instead of parsing human-readable DBus output.
  - Detects `com.canonical.AppMenu.Registrar` and calls `GetMenuForWindow(windowId)` when available.
  - Falls back to focused app DBus names matched by PID/app id and common DBusMenu paths such as `/MenuBar`.
  - Reads `com.canonical.dbusmenu.GetLayout`, flattens first-level app menu groups into Tahoe menu rows, preserves separators, disabled state, checked state, and item ids.
- Updated `tahoe-shell/services/AppMenu.qml`.
  - Exposes registrar status, native menu source, status text, and real menu item model.
  - Refreshes on focused-window changes and when the application menu popup opens.
  - Triggers selected native menu rows through `com.canonical.dbusmenu.Event(clicked)`.
  - Keeps existing focused-window actions as the no-menu fallback.
- Updated `tahoe-shell/components/AppMenuPopup.qml`.
  - Renders real native menu rows above the fallback window actions.
  - Adds a bounded, scrollable popup body so long app menus do not run off-screen.
  - Uses the existing TahoeGlass popup region and close model.
- Updated `tahoe-shell/services/SystemStatus.qml`.
  - Adds explicit AppMenu registrar diagnostics.
  - Expands legacy tray bridge diagnostics to show `xembedsniproxy` install/run/autostart state and the affected app classes.

## Compatibility Matrix

| App class | Expected path | Phase 7 status |
| --- | --- | --- |
| Browser | SNI if published; appmenu via registrar or `/MenuBar` when toolkit supports it | Supported by generic SNI and appmenu probing paths |
| Terminal | Usually no appmenu; window fallback actions remain available | Verified no-menu fallback with `org.gnome.Console` |
| File manager | Usually no appmenu on GNOME; window fallback actions remain available | Covered by focused-window fallback path |
| IDE/editor | Appmenu via registrar or `/MenuBar` when toolkit/plugin supports it | Supported by generic probing path |
| Chat apps | SNI tray icon/menu; attention state through SNI | Existing `Tray.qml`/`TrayMenu.qml` path retained |
| Steam / legacy tray | Requires `xembedsniproxy` bridge | Health page now diagnoses missing/not-running/no-autostart states |
| FClash / modern tray apps | SNI icon, attention, and menu | Existing SNI menu path retained |
| Input method | SNI menu and fcitx status | DBusMenu parser verified against fcitx `/MenuBar` |
| Screenshot/recording tools | Portal/PipeWire/tool diagnostics | Phase 6 health checks retained |

## Acceptance

- Common SNI app icons, attention, and menus remain on the existing `SystemTray.items` plus Tahoe `TrayMenu` path.
- Legacy XEmbed tray bridge failures are no longer silent:
  - Health shows `xembedsniproxy` missing, installed-not-running, running, and autostart hints.
  - The row explicitly calls out Steam, input method panels, and sync clients.
- Native menu support now has a real DBusMenu path:
  - `AppMenu.qml` no longer only checks registrar ownership.
  - `appmenu_probe.py` reads real `GetLayout` JSON and returns renderable Tahoe menu items.
  - Selecting a leaf row sends the DBusMenu `Event(clicked)` call to the same service/path.
- Current session has no `com.canonical.AppMenu.Registrar`; this is now surfaced as a warning, not treated as success.
- The focused-app fallback was verified against the live fcitx DBusMenu provider:
  - `python3 tahoe-shell/services/appmenu_probe.py 0 110061 org.fcitx.Fcitx5 fcitx5` returned real rows including `键盘 - 英语（美国）`, `拼音`, separators, checked state, and action ids.
- No-menu fallback was verified with `org.gnome.Console`:
  - The helper returned no native rows and a clear `未检测到 AppMenu registrar` status instead of fake menu entries.

## Runtime Checks

- `python3 -m py_compile tahoe-shell/services/appmenu_probe.py`: exited `0`.
- `git diff --check -- tahoe-shell/services/AppMenu.qml tahoe-shell/components/AppMenuPopup.qml tahoe-shell/docs/sequential-daily-desktop-roadmap-2026-06-19.md`: exited `0`.
- `grep -n '[[:blank:]]$' tahoe-shell/services/appmenu_probe.py tahoe-shell/docs/phase7-app-compat-native-menu-acceptance-2026-06-19.md tahoe-shell/services/SystemStatus.qml`: no trailing whitespace output.
- `bash scripts/check-tahoe-glass-guardrails.sh`: exited `0`.
- `bash scripts/check-submodules.sh`: exited `0`.
  - The script still prints git's `submodule` usage during its dry-run probe, then continues and exits `0`; this is pre-existing script behavior.
- `niri/target/release/niri validate -c config/niri/tahoe-phase0.kdl`: exited `0`.
- Temporary QML load:
  - `timeout 8s /home/wwt/.local/bin/quickshell --no-color --path /home/wwt/niri/tahoe-shell`
  - Reached `Configuration Loaded`; timeout exit `124` was expected.
  - Existing warnings remained: duplicate Behavior interceptor warnings, `Qt.application.font` read-only warning, notification DBus ownership conflict from the already-running live shell, MPRIS no-player warnings, and portal app-id warning.
  - No `AppMenu`, `AppMenuPopup`, `SystemStatus`, or `appmenu_probe.py` load failure appeared.
- Deployed current Tahoe shell to `/home/wwt/.config/quickshell/tahoe` with `rsync -a`.
- Restarted the live Tahoe Quickshell instance.
  - Old instance: `wp72pfdugt` / PID `103316`.
  - New instance: `9ws2cceugt` / PID `130761`.
  - Startup reached `Configuration Loaded`.
- `diff -qr /home/wwt/niri/tahoe-shell /home/wwt/.config/quickshell/tahoe`: exited `0`.
- `quickshell ipc -p /home/wwt/.config/quickshell/tahoe show`: listed the existing `tahoe` IPC target after restart.
- IPC smoke:
  - `openSystemHealth` opened the Settings/Health overlay.
  - `closeSettings` closed it cleanly.
- `quickshell log -i 9ws2cceugt --tail 240 --no-color | grep -iE 'AppMenu|AppMenuPopup|appmenu_probe|SystemStatus|Traceback|ReferenceError|SyntaxError|TypeError|failed|cannot'`: produced no matching stage-7 load/runtime errors.

## Residual Risk

- This machine does not currently run an AppMenu registrar or an app with registrar-backed appmenu, so the registrar `GetMenuForWindow` path is implemented but not live-validated against a real GUI app in this session.
- GJS was able to own a temporary mock registrar name, but its automatic packing of `com.canonical.dbusmenu.GetLayout`'s nested `a{sv}`/`av` return type failed; the mock was discarded and no DBus owner was left behind.
