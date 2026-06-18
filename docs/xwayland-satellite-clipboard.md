# Xwayland Satellite Clipboard Notes

## Problem

X11 apps and Wayland apps could not reliably copy and paste between each other
under Tahoe niri.

The misleading part: niri already exposed the relevant Wayland selection
protocols:

- `wl_data_device_manager`
- `zwp_primary_selection_device_manager_v1`
- `zwlr_data_control_manager_v1`
- `ext_data_control_manager_v1`

So this was not fixed by adding another niri protocol or by only changing the
Tahoe shell clipboard history.

## Root Cause

The bridge is `xwayland-satellite`, not Quickshell and not niri's clipboard
history.

In `xwayland-satellite` v0.8.1, `src/server/selection.rs` only consumed a new
Wayland clipboard offer when its internal `state.source` was empty. If a
Wayland client replaced the clipboard with another Wayland offer, the old
foreign offer could stay in `state.source`, leaving X11 clients with stale or
missing clipboard data.

The local patch in `patches/xwayland-satellite-minimize.patch` therefore does
two things:

1. Forwards X11 `WM_CHANGE_STATE/IconicState` minimize requests to Wayland
   `xdg_toplevel.set_minimized()`.
2. Refreshes stale Wayland clipboard offers while preserving X11-owned
   selections until the compositor cancels them.

Do not split these responsibilities casually: Tahoe's niri config points at the
single patched binary through the glamor wrapper.

## Local Paths

- Patch: `patches/xwayland-satellite-minimize.patch`
- Patched binary: `~/.local/lib/niri/xwayland-satellite-minimize`
- Glamor wrapper: `~/.local/lib/niri/xwayland-satellite-minimize-glamor`
- Build script: `scripts/arch-update.sh`
- Config reference: `config/niri/tahoe-phase0.kdl`
- Probe tool: `tools/x11_clipboard_probe.c`

The wrapper is intentionally used because this setup also needs `-glamor gl` for
Xwayland GLX clients. See `docs/xwayland-satellite-nvidia-glx.md` before
changing the wrapper path or NVIDIA GLX environment.

## Verification

Patch application and targeted upstream tests:

```sh
rm -rf /tmp/xwayland-satellite-patchcheck
git clone https://github.com/Supreeeme/xwayland-satellite.git /tmp/xwayland-satellite-patchcheck
git -C /tmp/xwayland-satellite-patchcheck checkout v0.8.1
git -C /tmp/xwayland-satellite-patchcheck apply /home/wwt/niri/patches/xwayland-satellite-minimize.patch
cargo test selection --locked --manifest-path /tmp/xwayland-satellite-patchcheck/Cargo.toml
cargo test quick_empty_data_offer --locked --manifest-path /tmp/xwayland-satellite-patchcheck/Cargo.toml
```

Build and wrapper self-check:

```sh
bash scripts/arch-update.sh
~/.local/lib/niri/xwayland-satellite-minimize :0 --test-listenfd-support
~/.local/lib/niri/xwayland-satellite-minimize-glamor :0 --test-listenfd-support
```

Manual clipboard probe:

```sh
gcc tools/x11_clipboard_probe.c -o /tmp/x11_clipboard_probe $(pkg-config --cflags --libs x11)

printf 'from-wayland' | wl-copy
DISPLAY=:1 /tmp/x11_clipboard_probe read

DISPLAY=:1 /tmp/x11_clipboard_probe own 'from-x11' &
sleep 0.5
wl-paste --no-newline
```

Use the live `$DISPLAY` from the session, usually `:1` in Tahoe niri. If unsure:

```sh
env | grep '^DISPLAY='
pgrep -af 'xwayland-satellite|Xwayland'
```

## Runtime Gotcha

Installing a new patched binary is not enough if `xwayland-satellite` is already
running. After replacing the binary, the old process can keep running from a
deleted inode:

```sh
readlink -f /proc/$(pgrep -n xwayland-satellite)/exe
```

If it prints a path ending in `(deleted)`, the running bridge is still the old
code. Restart niri, or close all X11 apps and let niri spawn
`xwayland-satellite` again. Existing X11 apps will not magically move to the new
bridge process.

## What Not To Do

- Do not debug this first in Quickshell's clipboard history. `cliphist` only
  stores Wayland clipboard history; it is not the X11 bridge.
- Do not assume `wl-copy`/`wl-paste` passing means X11 interop works. That only
  proves Wayland-side selection works.
- Do not replace the glamor wrapper with `/usr/bin/xwayland-satellite`; the
  system package can be older and misses both the Tahoe minimize patch and this
  clipboard patch.
- Do not forget to restart the running bridge after installing a new binary.
