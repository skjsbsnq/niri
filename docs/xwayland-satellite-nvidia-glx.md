# Xwayland Satellite NVIDIA GLX Notes

## Problem

In the Tahoe niri session, Proton games and Windows launchers that run through
Xwayland can become extremely slow when GLX falls back to Mesa llvmpipe.

The concrete failure observed with Hearts of Iron IV / Paradox Launcher was:

- Paradox Launcher opened very slowly or became unresponsive.
- Launcher logs contained `GPU process crashed`.
- `glxinfo -B` under the niri `DISPLAY` showed:

```text
OpenGL renderer string: llvmpipe (LLVM ...)
Accelerated: no
```

This was not caused by the local minimize patch itself. The patched binary could
use hardware GLX when started with the right arguments and environment.

## Root Cause

There were two separate issues:

1. The niri-launched `xwayland-satellite` path did not force Xwayland glamor.
   Without `-glamor gl`, GLX clients can fall back to software rendering.

2. On the hybrid AMD iGPU + NVIDIA dGPU setup, even with glamor enabled, GLVND
   selected Mesa for GLX clients by default. Forcing the GLX vendor to NVIDIA
   made the same Xwayland display use the RTX 4070 immediately.

The working combination is:

```text
xwayland-satellite ... -glamor gl
__GLX_VENDOR_LIBRARY_NAME=nvidia
```

## Required Configuration

The Tahoe niri config must point at the glamor wrapper, not directly at the
patched satellite binary:

```kdl
xwayland-satellite {
    path "~/.local/lib/niri/xwayland-satellite-minimize-glamor"
}
```

The session environment must also force the NVIDIA GLX vendor:

```kdl
environment {
    __GLX_VENDOR_LIBRARY_NAME "nvidia"
}
```

The startup environment import must include `__GLX_VENDOR_LIBRARY_NAME`, so
systemd-user-launched processes inherit the same setting.

`scripts/tahoe-niri-session.sh` and `scripts/run-tahoe-session.sh` also default
this variable to `nvidia`. Keep those launchers aligned with the niri config;
otherwise Steam or a launcher started through systemd/user services can regress
to Mesa llvmpipe even though the compositor config looks correct.

## Managed Files

`scripts/arch-update.sh` manages these files:

```text
~/.local/lib/niri/xwayland-satellite-minimize
~/.local/lib/niri/xwayland-satellite-minimize-glamor
~/.config/niri/tahoe/config.kdl
```

The wrapper execs the patched satellite with `-glamor gl` while preserving niri's
display and `-listenfd` arguments.

## Verification

Check the live Xwayland command:

```sh
pgrep -af 'xwayland-satellite|Xwayland'
```

Expected:

```text
xwayland-satellite-minimize :1 -glamor gl -listenfd ...
Xwayland :1 ... -glamor gl ...
```

Check a process spawned by niri, not an old terminal that may have stale
environment:

```sh
rm -f /tmp/niri-spawn-glx.out /tmp/niri-spawn-glx.err
niri msg action spawn -- sh -lc 'printf "GLX=%s\nDISPLAY=%s\n" "${__GLX_VENDOR_LIBRARY_NAME:-}" "${DISPLAY:-}" > /tmp/niri-spawn-glx.out; glxinfo -B >> /tmp/niri-spawn-glx.out 2> /tmp/niri-spawn-glx.err'
sleep 1
sed -n '1,80p' /tmp/niri-spawn-glx.out
```

Expected:

```text
GLX=nvidia
OpenGL vendor string: NVIDIA Corporation
OpenGL renderer string: NVIDIA GeForce RTX 4070 ...
```

For a running Proton game:

```sh
pid=$(pgrep -n -x hoi4.exe)
tr '\0' '\n' < /proc/$pid/environ | rg '^(DISPLAY|__GLX_VENDOR_LIBRARY_NAME)='
ls -l /proc/$pid/fd | rg '/dev/(nvidia|dri)'
nvidia-smi
```

Expected:

```text
__GLX_VENDOR_LIBRARY_NAME=nvidia
hoi4.exe appears in nvidia-smi
```

## Common Pitfall

Running `glxinfo` in an old terminal can still show llvmpipe if that terminal was
started before the environment fix. Use `niri msg action spawn` for validation,
or start a new terminal after reloading/restarting the session.

If only the current terminal is wrong, this command should prove the live
Xwayland can still use NVIDIA:

```sh
DISPLAY=:1 __GLX_VENDOR_LIBRARY_NAME=nvidia glxinfo -B
```

## Regression Checklist

Before blaming Proton, Steam, or the Paradox Launcher, check:

- `Xwayland` command line contains `-glamor gl`.
- `__GLX_VENDOR_LIBRARY_NAME=nvidia` is present in niri-spawned processes.
- `glxinfo -B` from a niri-spawned shell reports NVIDIA, not llvmpipe.
- Steam and Proton child processes inherit `__GLX_VENDOR_LIBRARY_NAME=nvidia`.
- The game appears in `nvidia-smi`.

If the launcher is slow again and `launcher-*.log` contains `GPU process crashed`,
re-check this file before changing Proton versions or launcher flags.
