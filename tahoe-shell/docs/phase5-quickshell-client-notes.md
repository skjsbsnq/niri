# Phase 5 Quickshell Client Notes

Date: 2026-06-16

## Current Repository Layout

The aggregate/root repository remains:

- `https://github.com/skjsbsnq/niri`
- branch: `main`

The compositor source submodule now points to the independent Tahoe niri source repository:

- path: `niri/`
- url: `https://github.com/skjsbsnq/tahoe-desktop.git`
- branch: `main`
- current commit: `1583df3` (`Clean Tahoe glass build warnings`)

The Quickshell source submodule points to the Quickshell fork:

- path: `quickshell/`
- url: `https://github.com/skjsbsnq/quickshell.git`
- branch: `quickshell-tahoe-desktop`
- current commit: `066cd88` (`Implement Tahoe glass client protocol`)

Important: `tahoe-desktop` is the independent niri/Tahoe compositor source repo, not the aggregate repo.

## Phase 5 Implementation

Quickshell now has a `tahoe_glass_v1` client implementation:

- protocol XML and client stub integration
- `TahoeGlass` attached object
- `TahoeGlassRegion` QML object
- multiple regions per surface
- item-to-surface coordinate mapping
- material name, per-corner radius, and blur/shadow/clip flags
- fallback to `BackgroundEffect.blurRegion` when the protocol is unavailable

This phase only adds the client-side capability. It does not fully migrate existing Tahoe QML components yet; that is Phase 6.

## Update and Build Command

Inside the Arch VM, use:

```sh
BUILD_NIRI_FORK=auto BUILD_QUICKSHELL_FORK=auto bash scripts/arch-update.sh
```

This should:

- pull the aggregate repo
- sync submodule URLs
- update `niri/` from `skjsbsnq/tahoe-desktop`
- update `quickshell/` from `skjsbsnq/quickshell`
- rebuild niri when the niri submodule changed
- rebuild Quickshell when the Quickshell submodule changed or the installed build stamp is stale
- install the Quickshell fork to `~/.local/bin/quickshell`
- deploy Tahoe QML/config/session files as needed

If needed, force rebuilds:

```sh
FORCE_NIRI_BUILD=true FORCE_QUICKSHELL_BUILD=true bash scripts/arch-update.sh
```

## Phase 5 Test Goals

Phase 5 should verify the protocol path, not final visual polish.

Check:

- Quickshell starts with the new Tahoe glass module available.
- niri debug logs show Tahoe glass region create/update/remove/commit events.
- QML region geometry maps correctly to niri:
  - `x`
  - `y`
  - `width`
  - `height`
  - corner radii
  - material
  - flags
- multiple regions on one surface work, especially for Spotlight-style layouts.
- protocol fallback does not crash when `tahoe_glass_v1` is unavailable.

## Minimal Manual QML Probe

Before Phase 6 migration, a component must explicitly declare a Tahoe glass region to exercise the protocol.

Example shape:

```qml
import Quickshell.Wayland

PanelWindow {
    id: root

    TahoeGlass.regions: [
        TahoeGlassRegion {
            item: panel
            material: "panel"
            radius: 28
            blur: true
            shadow: true
            clip: true
        }
    ]

    Item {
        id: panel
    }
}
```

Expected result:

- niri receives the exact rounded region.
- niri logs the region.
- compositor-owned glass can render for that region.

## Expected Visual Change

Without Phase 6 component migration, visual changes may be small or invisible.

The main expected Phase 5 change is architectural:

```text
QML TahoeGlassRegion
  -> Quickshell tahoe_glass_v1 client
  -> niri committed Tahoe glass regions
  -> niri region-level blur/shadow/clip renderer
```

The obvious visual fixes are expected in Phase 6, after components move from `BackgroundEffect.blurRegion` and QML-only glass to `TahoeGlass.regions`.

Expected Phase 6 visible improvements:

- Control Center and Notification Center avoid rectangular backing artifacts.
- Spotlight search pill avoids square halo/backing.
- Dock and TopBar glass is based on the internal strip, not the full layer surface.
- shadow, blur, clip, refraction, and highlight use the same rounded rect.

## Script Notes

`scripts/arch-update.sh` already handles both fork builds:

- `BUILD_NIRI_FORK=auto`
- `BUILD_QUICKSHELL_FORK=auto`

`scripts/arch-bootstrap.sh` now runs `git submodule sync --recursive` before submodule update, so existing VM checkouts should pick up the new `niri -> tahoe-desktop` URL after pulling the aggregate repo.

## Bug Fix: Glass Blur Not Updating on Window Move

### Issue Description

**Problem**: Frosted glass blur effect does not update in real-time when windows are moved or resized in normal mode, but updates correctly when entering overview mode.

**Environment**: VMware Arch Linux running niri compositor

**Symptoms**:
- Moving windows in normal workspace: blur region stays static, shows incorrect background
- Entering overview mode: blur updates correctly and shows proper background
- Window geometry changes (resize) also do not trigger blur updates

### Root Cause

The TahoeGlass implementation in `quickshell/src/wayland/tahoe_glass/qml.cpp` only monitored `QWindow::xChanged` and `QWindow::yChanged` signals for position updates. However:

1. In niri compositor, these Qt signals may not fire reliably during window moves
2. The blur effect requires screen-absolute coordinates (see `buildSurfaceRegion()` lines 262-265) to sample the correct background area
3. Without position updates, the blur continues sampling from the old window location

### Solution

Added multiple layers of window geometry monitoring:

**1. Additional Signal Connections** (Line ~397)
```cpp
QObject::connect(this->mWindow, &QWindow::widthChanged, this, &TahoeGlass::updateRegions);
QObject::connect(this->mWindow, &QWindow::heightChanged, this, &TahoeGlass::updateRegions);
```

**2. Enhanced Event Filter** (Line ~376-395)
Added event-based monitoring for:
- `QEvent::Move` - Catches window position changes that don't emit signals
- `QEvent::Resize` - Catches window size changes
- `QEvent::UpdateRequest` - Updates during frame requests to maintain sync during animations

```cpp
else if (event->type() == QEvent::Move || event->type() == QEvent::Resize) {
    // Catch window geometry changes that don't trigger x/y/width/height signals
    // This is crucial for niri compositor where window moves may not emit signals
    this->updateRegions();
}
```

### Why Overview Mode Worked

Overview mode likely triggers a full window re-layout or compositor state change that causes Qt to re-query window positions, indirectly triggering the blur update. The fix ensures updates happen continuously during normal window operations.

### Testing

After this fix:
- ✅ Window moves should update blur in real-time
- ✅ Window resizes should update blur region
- ✅ Blur should stay synchronized during drag operations
- ✅ Overview mode continues to work correctly

### Files Modified

- `quickshell/src/wayland/tahoe_glass/qml.cpp`
  - `onWindowConnected()`: Added width/height signal connections
  - `eventFilter()`: Added Move/Resize/UpdateRequest event handling

### Related Notes

This fix is particularly important for Wayland compositors like niri that may have different event emission patterns compared to traditional X11 window managers. The multi-layered monitoring approach ensures compatibility across different compositor implementations.

