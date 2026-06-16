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

## TahoeGlass Coordinate Contract

TahoeGlass regions are submitted as surface-local logical coordinates. `buildSurfaceRegion()` must not add `QWindow::position()` or device-pixel scaling before sending a region through `tahoe_glass_v1`.

The compositor is responsible for placing those regions on the output. In niri, layer rendering passes the surface location into TahoeGlass rendering and `render_region()` samples at `surface_location + rect.loc`.

`clientSideMargins()` is still applied on the client side because QML item geometry is relative to the window content area, while the protocol region is relative to the `wl_surface`. For Tahoe layer-shell windows this is expected to be zero, but keeping the translation preserves correctness for decorated or margin-bearing Wayland surfaces.

Window move/resize monitoring can remain useful to schedule repolish work, but it must not change the coordinate space of the committed regions. Moving a window should not require resubmitting screen coordinates; the surface-local rect stays stable and niri updates the output-space sampling location.
