# Tahoe Daily Desktop Phase 0 Baseline

Date: 2026-06-19

Scope: baseline and acceptance record for `sequential-daily-desktop-roadmap-2026-06-19.md` phase 0. This phase did not implement Dock behavior changes.

## Repository Baseline

- Parent repo HEAD: `6f3f2fdc59fe69955253427ec116d64cd995a427`.
- `git status --short`: clean at the start of phase 0.
- Submodules:
  - `niri`: `15911c51cad331899ccbd0ea2b397bb393741aa8` on `heads/main`.
  - `quickshell`: `8b3b864db99e78e70e247af4ff2f99e7706924e5` on `quickshell-tahoe-desktop`.
- Running session observed:
  - `niri`: `/home/wwt/.local/bin/niri --session --config /home/wwt/.config/niri/tahoe/config.kdl`.
  - `quickshell`: `/home/wwt/.local/bin/quickshell -p /home/wwt/.config/quickshell/tahoe`.
  - Output `eDP-2`: current mode `2560x1600`, logical size `2048x1280`, scale `1.25`.
  - Base layer surfaces: `tahoe-wallpaper`, `tahoe-topbar`, `tahoe-dock`.

## Source Facts

- Dock glass width is capped at `Math.min(parent.width - 28, dockRow.implicitWidth + 34)` in `tahoe-shell/components/Dock.qml:197`.
- The inner Dock content is a centered `Row` with `spacing: 8` and no clipping, scroll area, or overflow menu in `tahoe-shell/components/Dock.qml:232-235`.
- Pinned delegates have fixed `width: 62`; the nearby comment explicitly protects against magnification-driven width binding loops in `tahoe-shell/components/Dock.qml:266-274`.
- Pinned icon right click currently bounces and immediately returns, so no unpin UI exists in `tahoe-shell/components/Dock.qml:433-439`.
- Pinned drag reorder is already implemented through `finishPinnedReorder()` and `appsService.movePinnedApp()` in `tahoe-shell/components/Dock.qml:105-115` and `tahoe-shell/components/Dock.qml:388-424`.
- File drop to pinned applications is already implemented through `openFilesWithApp()` in `tahoe-shell/components/Dock.qml:289-301` and `tahoe-shell/services/Apps.qml:632-649`.
- Downloads and Trash are already present in the Dock right segment in `tahoe-shell/components/Dock.qml:545-559`.
- Trash accepts dropped URLs and calls `gio trash` through `trashUrls()` and `DockToolButton.onUrlsDropped` in `tahoe-shell/components/Dock.qml:136-150` and `tahoe-shell/components/Dock.qml:551-558`.
- Window buttons are created from `niriService.windowList` with `showTitle: true` in `tahoe-shell/components/Dock.qml:510-526`.
- `WindowButton` uses fixed width `showTitle ? 132 : 56`; its comment also protects magnification/width decoupling in `tahoe-shell/components/WindowButton.qml:34-40`.
- Running window right click currently pins the window's app directly, without a context menu, in `tahoe-shell/components/WindowButton.qml:161-166`.
- Apps persistence and pin APIs already exist:
  - `setPinnedIds()` writes state and bumps revision in `tahoe-shell/services/Apps.qml:429-435`.
  - `writePinnedState()` writes JSON in `tahoe-shell/services/Apps.qml:482-488`.
  - `unpinApp()`, `togglePinnedApp()`, and `movePinnedApp()` are present in `tahoe-shell/services/Apps.qml:564-623`.

## Reproduction Record

### Fixed App Unpin

Reproducible from source.

Current behavior: right clicking a pinned Dock app does not expose any action. The code path accepts right click and returns before calling `Apps.unpinApp()`.

Existing API: `Apps.unpinApp(app)` and `Apps.togglePinnedApp(app)` are available, so the missing piece is UI wiring, not persistence plumbing.

### Dock Overflow

Reproducible from source and user screenshot.

User screenshot: `/home/wwt/Pictures/Screenshots/Screenshot from 2026-06-19 01-04-57.png`, size `2560x137`. It shows Dock content extending into the right side when pinned apps and windows are numerous.

Width model used for phase 0:

- Visual pinned count includes Launchpad.
- Pinned app item width plus spacing: `62 + 8 = 70`.
- Running window item width plus spacing: `132 + 8 = 140`.
- Right segment and separators, including spacing, accounts for about `134`.
- Dock surface maximum width is `screen width - 28`.

Calculated overflow:

| Screen | Visual pinned | Windows | Row implicit width | Surface max | Row over surface |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1366 | 9 | 9 | 2024 | 1338 | +686 |
| 1366 | 10 | 4 | 1394 | 1338 | +56 |
| 1366 | 10 | 8 | 1954 | 1338 | +616 |
| 1366 | 10 | 16 | 3074 | 1338 | +1736 |
| 1920 | 9 | 9 | 2024 | 1892 | +132 |
| 1920 | 10 | 8 | 1954 | 1892 | +62 |
| 1920 | 10 | 16 | 3074 | 1892 | +1182 |
| 2560 | 10 | 16 | 3074 | 2532 | +542 |
| 2560 | 12 | 16 | 3214 | 2532 | +682 |

Conclusion: the outer Dock surface is constrained, but the centered inner `Row` can be wider than the surface. There is currently no clip, horizontal `Flickable`, icon-only fallback, or overflow menu.

## Checks Run

- `bash scripts/check-submodules.sh`: exited `0`.
  - Confirmed `niri/`, `quickshell/`, and `tahoe-shell/` directories exist.
  - `niri/` and `quickshell/` are git repositories at the expected commits.
  - The script's `git submodule update --init --recursive --dry-run` form printed Git usage because this Git does not accept that dry-run form, then the script continued as designed.
- `scripts/check-tahoe-glass-guardrails.sh`: exited `0`.
  - Re-run after current worktree guardrail updates also exited `0`.
  - Current output includes `niri config keeps variable-refresh-rate disabled`.
  - No broad `namespace="^quickshell"` rule.
  - Tahoe QML has no direct `BackgroundEffect` or `blurRegion` usage.
  - Checked 15 `PanelWindow` namespace declarations.
  - Checked 15 `TahoeGlassRegion` declarations.
  - Checked 14 `TahoeGlass.regions` files for material/radius item properties.
  - Phase 7 guardrails passed.

## Smoke Record

Confirmed running session and base Tahoe layer surfaces with `niri msg --json layers`.

Confirmed DBus ownership:

- `org.freedesktop.Notifications` is owned by `quickshell`.
- `org.kde.StatusNotifierWatcher` and a `StatusNotifierHost` are owned by `quickshell`.

Confirmed source wiring for daily entry points:

- Control Center, Notification Center, Spotlight, Launchpad, tray menu, screenshot, and input method are wired through `TopBar` signals in `tahoe-shell/shell.qml:221-293`.
- `ControlCenter`, `Launchpad`, `Spotlight`, `NotificationCenter`, `BatteryPopup`, `WifiPopup`, `FanPopup`, `ClipboardPopup`, and `TrayMenu` instances are present in `tahoe-shell/shell.qml:327-403`.
- Screenshot entry calls `screenshotService.captureSelection()` in `tahoe-shell/shell.qml:279-284`; the screenshot component checks `grim` and `slurp` in `tahoe-shell/components/Screenshot.qml:41-63`.
- Lock screen entry is present in the niri menu and routes to `Power.requestAction("lock")`/`LockScreen.lock()` through `tahoe-shell/components/MenuPopup.qml:172` and `tahoe-shell/services/Power.qml:50-107`.
- Tray items use `SystemTray.items`; right click opens Tahoe `TrayMenu` through `tahoe-shell/components/Tray.qml:77-158` and `tahoe-shell/shell.qml:286-293`.

Limitations:

- Tahoe shell exposes no `IpcHandler`; `/home/wwt/.local/bin/quickshell ipc --pid 1276 show` returned no callable targets.
- Common Wayland input helpers (`ydotool`, `dotool`, `wtype`, `wlrctl`) were not installed.
- A temporary `/dev/uinput` virtual pointer test did not trigger TopBar layer changes, so command-side click smoke could not reliably open/close Control Center, Notification Center, Spotlight, Launchpad, or TrayMenu.
- `notify-send` returned successfully against the Tahoe notification daemon, but no extra toast layer was visible in `niri msg --json layers` at the sampled moment.
- The lock action was not executed to avoid locking the user's active session without an unlock credential path in this automation context.

## Acceptance

- Current fixed-app unpin issue: reproducible.
- Current Dock overflow issue: reproducible.
- Existing Dock right segment: confirmed present from source.
- Existing pinned drag reorder: confirmed present from source.
- Existing file drop to pinned app: confirmed present from source.
- Existing Trash drop: confirmed present from source.
- Code changes in phase 0: none.
- Phase 0 repository changes: this record document plus one roadmap link/status line.

Exit gate: phase 0 baseline is complete. Stage 1 may start only after accepting this record.
