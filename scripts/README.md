# Arch VM Scripts

These scripts are intended to be run inside the Hyper-V Arch Linux VM.

If the repository was cloned without `--recurse-submodules`, both `arch-bootstrap.sh` and `arch-update.sh` initialize the registered submodules before they deploy configs or build niri.

## Bare-Metal One-Shot Install

```sh
bash scripts/baremetal-install.sh
```

`baremetal-install.sh` is the one-shot installer for a real Arch Linux machine set up with `archinstall`'s minimal profile (no GUI, no display manager). Run it once on a TTY as a normal user with `sudo` rights and an internet connection. It is safe to re-run.

It does only what a minimal install is missing, and otherwise drives the existing scripts:

1. clones the repo to `~/niri` (or `git pull --ff-only` + submodule update if it already exists; refuses to overwrite uncommitted changes),
2. installs `lightdm` + `lightdm-gtk-greeter` and the GUI apps/runtime helpers the config/shell call directly (`alacritty`, `fuzzel`, `grim`, `slurp`, `swappy`, `gammastep`, `qt6ct`, `kvantum`, `swaylock` as an emergency lock fallback, `swaybg`, `brightnessctl`, `cliphist`, `wl-clipboard`, `network-manager-applet`, `nm-connection-editor`, `power-profiles-daemon`, `xwayland-satellite`, `xdg-desktop-portal`, `xdg-desktop-portal-gnome`, `xdg-desktop-portal-gtk`),
3. enables `NetworkManager` and `lightdm` (lightdm starts on next boot, not now, so it does not seize a running session),
4. runs `arch-bootstrap.sh` with `BUILD_NIRI_FORK=auto BUILD_QUICKSHELL_FORK=auto`, so the first deploy pass builds and installs both forks under `~/.local/bin` for full compositor/shell validation,
5. runs `arch-zh-setup.sh` for CJK locale/fonts/fcitx5,
6. prints a summary and, if run from a real TTY as a non-root user, asks whether to launch the Tahoe session immediately.

It intentionally does not install GPU vendor drivers, an AUR helper, or modify `/etc/lightdm/lightdm.conf` — install your GPU driver (NVIDIA/AMD proprietary, etc.) yourself before running it.

Environment overrides:

```sh
INSTALL_DIR=~/tahoe-desktop bash scripts/baremetal-install.sh   # clone target (default ~/niri)
SKIP_SYSTEM_PACKAGES=true bash scripts/baremetal-install.sh     # skip the pacman step
SKIP_ZH_SETUP=true bash scripts/baremetal-install.sh            # skip CJK/locale/fcitx5
AUTO_LAUNCH_SESSION=true bash scripts/baremetal-install.sh      # launch session without prompting (TTY only)
AUTO_LAUNCH_SESSION=false bash scripts/baremetal-install.sh     # never launch, just print the summary
```

After it finishes, reboot (or `sudo systemctl start lightdm` from a TTY) and pick `Tahoe Niri` in the greeter, or launch directly with `bash scripts/run-tahoe-session.sh`.

## First Setup

```sh
bash scripts/arch-bootstrap.sh
```

`arch-bootstrap.sh` installs baseline Arch build/runtime packages when `pacman` is available, including the distro `niri` package for Phase 0, checks for Quickshell, then runs `arch-update.sh` for the first deploy pass.

The project niri config is deployed to `~/.config/niri/tahoe/config.kdl`. This avoids overwriting an existing user `~/.config/niri/config.kdl`.

## Every Windows Push

```sh
bash scripts/arch-update.sh
```

This is the only update command expected during normal Tahoe work. It pulls the latest code, updates submodules, optionally rebuilds the local niri/Quickshell forks, deploys `tahoe-shell/` and `config/niri/tahoe-phase0.kdl` when needed, and prints whether niri or Quickshell should be restarted.

Phase 0 uses the distro `niri` package installed by `pacman`; it does not build the local niri fork by default.

Do not manually run `cargo build`, `cmake`, `ninja`, or copy QML/config files during normal phase validation. If a manual command becomes necessary, add that missing behavior to `arch-update.sh`.

To force a niri fork build even when no niri changes were pulled:

```sh
FORCE_NIRI_BUILD=true bash scripts/arch-update.sh
```

From Phase 2 onward, enable automatic niri fork builds when niri source changes:

```sh
BUILD_NIRI_FORK=auto bash scripts/arch-update.sh
```

From Phase 5 onward, enable automatic Quickshell fork builds when the Quickshell submodule changes or when the installed local Quickshell binary is missing/out of date:

```sh
BUILD_QUICKSHELL_FORK=auto bash scripts/arch-update.sh
```

To update both compositor and shell protocol sides in one pass:

```sh
BUILD_NIRI_FORK=auto BUILD_QUICKSHELL_FORK=auto bash scripts/arch-update.sh
```

To force a Quickshell rebuild even when no Quickshell changes were pulled:

```sh
FORCE_QUICKSHELL_BUILD=true bash scripts/arch-update.sh
```

The Quickshell fork is installed under `~/.local/bin/quickshell` by default, matching the Tahoe session launcher's normal `PATH`-based lookup.

When a Quickshell build is needed on Arch, `arch-update.sh` installs the required build packages first, including `qt6-shadertools`, `spirv-tools`, `qt6-wayland`, and `vulkan-headers`. Set `INSTALL_QUICKSHELL_BUILD_DEPS=false` to skip that package install step.

`arch-update.sh` also maintains a patched `xwayland-satellite` under `~/.local/lib/niri/xwayland-satellite-minimize` by default. This is the X11 fallback needed by apps such as Linux WeChat whose visible window still goes through xwayland-satellite. The patch forwards X11 `WM_CHANGE_STATE/IconicState` minimize requests to Wayland `xdg_toplevel.set_minimized()` and refreshes stale Wayland clipboard offers so X11 apps can see clipboard updates from Wayland apps. See `docs/xwayland-satellite-clipboard.md` before changing the patch or clipboard bridge behavior.

The niri Tahoe config intentionally points at `~/.local/lib/niri/xwayland-satellite-minimize-glamor`, a wrapper generated by `arch-update.sh`. The wrapper preserves the minimize patch and forces `-glamor gl`, because on the hybrid AMD + NVIDIA Tahoe setup Xwayland GLX clients otherwise fall back to Mesa llvmpipe. The config and Tahoe session launchers also set `__GLX_VENDOR_LIBRARY_NAME=nvidia` so GLVND selects the NVIDIA GLX vendor. See `docs/xwayland-satellite-nvidia-glx.md` before changing this path or environment variable.

The patched satellite build defaults to `BUILD_XWAYLAND_SATELLITE=auto`: it rebuilds when the binary is missing, the selected upstream ref changes, or `patches/xwayland-satellite-minimize.patch` changes. To force it:

```sh
FORCE_XWAYLAND_SATELLITE_BUILD=true bash scripts/arch-update.sh
```

By default, the satellite source is pinned to the verified Arch package version tag:

```sh
XWAYLAND_SATELLITE_REF=v0.8.1
```

To test a newer upstream tag or branch without hand-building:

```sh
XWAYLAND_SATELLITE_REF=v0.8.2 FORCE_XWAYLAND_SATELLITE_BUILD=true bash scripts/arch-update.sh
XWAYLAND_SATELLITE_REF=main FORCE_XWAYLAND_SATELLITE_BUILD=true bash scripts/arch-update.sh
```

If upstream has merged equivalent minimize support and the local patch no longer applies, the script will build without the local patch when it detects native `set_minimized` plus `WM_CHANGE_STATE` support. Otherwise it stops with a clear patch-update error. Set `BUILD_XWAYLAND_SATELLITE=false` to skip this stage temporarily.

The XWayland compatibility diagnostics are split out into:

```sh
bash scripts/check-xwayland-satellite-compat.sh --status
```

It prints Tahoe health-page `STATUS|...` rows for the patched satellite path, the selected upstream ref, patch hash, build stamp, wrapper executable, niri config path, runtime process, and the minimize/clipboard bridge regression anchors in `patches/xwayland-satellite-minimize.patch`. `arch-update.sh` runs the same check with `--strict` after build/deploy; static `missing`, `stale`, or `broken` states fail the update, while a currently running old satellite process is reported but only requires restarting niri or reopening X11 apps.

Before deploying, `arch-update.sh` runs the Phase 7 Tahoe Glass guardrails. The check rejects broad `namespace="^quickshell"` glass rules, direct Tahoe QML `BackgroundEffect.blurRegion` usage, `PanelWindow` files without `tahoe-*` namespaces, and `TahoeGlassRegion` declarations without material/radius.

Run the same check manually with:

```sh
bash scripts/check-tahoe-glass-guardrails.sh
```

For a local emergency debug pass only, skip it with:

```sh
RUN_TAHOE_GLASS_GUARDRAILS=false bash scripts/arch-update.sh
```

## Capture Glass Baseline

```sh
bash scripts/capture-glass-baseline.sh
```

Run this inside the Arch VM before and after Tahoe Glass architecture changes.
It writes a timestamped report under
`tahoe-shell/docs/visual-baselines/runtime/` with the root/niri/Quickshell
commits, Tahoe config hashes, session environment, and `niri msg outputs` data
when niri IPC is reachable. The static Phase 0 reference screenshots live under
`tahoe-shell/docs/visual-baselines/2026-06-15-phase0-glass-geometry/`.

This is a baseline/forensics script only. It does not deploy configs, build
niri, restart Quickshell, or fix the glass artifacts. Use it to bind screenshots
to the exact code/config/output state that produced them.

## Chinese Locale, Fonts, and Input Method

```sh
bash scripts/arch-zh-setup.sh
```

Run this inside the Arch VM as the target desktop user, not with `sudo`. The script installs CJK/emoji fonts, enables `zh_CN.UTF-8` and `en_US.UTF-8`, sets system `LANG=zh_CN.UTF-8`, writes a user fontconfig fallback for simplified Chinese, installs fcitx5 with Chinese addons, writes the common fcitx environment variables, creates a default `keyboard-us + pinyin` fcitx5 profile only when one does not already exist, and tries to enable `fcitx5.service` for the current user.

To keep the desktop UI in English while still installing Chinese fonts and input support:

```sh
SET_SYSTEM_LOCALE=false bash scripts/arch-zh-setup.sh
```

To install only Chinese fonts and locale support without fcitx5:

```sh
INSTALL_INPUT_METHOD=false bash scripts/arch-zh-setup.sh
```

After running it, log out and log back in so locale, fontconfig, and input method environment changes apply to the whole session.

## Deployed Paths

`arch-update.sh` manages only project-owned Tahoe paths:

- niri config: `~/.config/niri/tahoe/config.kdl`
- Quickshell binary: `~/.local/bin/quickshell`
- patched xwayland-satellite: `~/.local/lib/niri/xwayland-satellite-minimize`
- patched xwayland-satellite glamor wrapper: `~/.local/lib/niri/xwayland-satellite-minimize-glamor`
- Tahoe shell: `~/.config/quickshell/tahoe`
- Tahoe XWayland health helper: `~/.config/quickshell/tahoe/scripts/check-xwayland-satellite-compat.sh`
- session launcher: `~/.local/bin/tahoe-niri-session`
- system session launcher: `/usr/local/bin/tahoe-niri-session`
- user Wayland session entry: `~/.local/share/wayland-sessions/tahoe-niri.desktop`
- system Wayland session entry: `/usr/share/wayland-sessions/tahoe-niri.desktop`

### Tahoe shell source/runtime parity

`arch-update.sh` is the only normal deploy entry for the Tahoe shell tree. Do not add parallel deploy scripts or hand-run ungoverned `rsync` of `tahoe-shell/`.

Desired installed tree:

1. filtered contents of `tahoe-shell/`
2. plus the single declared overlay `scripts/check-xwayland-satellite-compat.sh` → `~/.config/quickshell/tahoe/scripts/check-xwayland-satellite-compat.sh`

Sync and manifest share the same exclude list. Only these cache paths are excluded:

- `__pycache__/`
- `*.pyc`
- `.pytest_cache/`

After every shell deploy, the script verifies missing files, extra files, and content hashes. On success it records under `~/.local/state/tahoe-niri/`:

- `tahoe-shell-deployed-root-commit`
- `tahoe-shell-deployed-manifest.sha256`
- `tahoe-shell-deployed-manifest.txt`

Read-only check (does not write user config):

```sh
bash scripts/arch-update.sh --verify-tahoe-shell
```

Deploy only the shell tree (filtered sync + overlay + verify + state record; no niri/Quickshell build):

```sh
bash scripts/arch-update.sh --deploy-tahoe-shell
```

It does not overwrite `~/.config/niri/config.kdl` or the stock `niri.desktop` session.

Run `arch-update.sh` as the target user, not with `sudo`. The script may prompt for `sudo` internally when it installs or removes system session files.

Most display managers scan `/usr/share/wayland-sessions`, so `arch-update.sh` deploys that system entry by default. An earlier compatibility pass also installed `/usr/share/xsessions/tahoe-niri.desktop`; the script now removes that stale entry by default because this greeter shows both files as duplicate `Tahoe Niri` sessions.

Set `DEPLOY_TAHOE_SESSION_ENTRY=false` to skip the user entry. Set `DEPLOY_TAHOE_SYSTEM_SESSION_ENTRY=false` to skip the system Wayland entry. Set `CLEANUP_TAHOE_XSESSION_ENTRY=false` only if you intentionally want to keep an existing xsession-compatible file. Set `DEPLOY_TAHOE_XSESSION_ENTRY=true` only on a display manager that cannot read Wayland session entries.

## Switch Output Resolution

```sh
bash scripts/niri-set-resolution.sh
bash scripts/niri-set-resolution.sh 1920x1080@60
bash scripts/niri-set-resolution.sh 1280x800
OUTPUT_NAME=Virtual-1 bash scripts/niri-set-resolution.sh 1600x900@60
```

`niri-set-resolution.sh` calls `niri msg output <name> mode <WxH@Hz>` against the currently focused output (override with `OUTPUT_NAME`). It parses niri's plain-text output, so no `jq` is required. The change is **temporary** — it is not written back to `~/.config/niri/tahoe/config.kdl`. To persist it, add an `output "<name>" { mode 1920x1080.000; }` block there.

On Hyper-V, switching modes only works when niri drives the virtual output directly (i.e. the hyperv_drm path). When Hyper-V Enhanced Session (RDP) is in use, the resolution is negotiated by the RDP client and `niri msg output mode` may report that the requested mode is unsupported — resize the Enhanced Session window or reconnect at the desired resolution instead.

## Start Session

```sh
bash scripts/run-tahoe-session.sh
```

`run-tahoe-session.sh` defaults to `NIRI_MODE=auto`: it starts nested niri when it sees an existing `WAYLAND_DISPLAY` or `DISPLAY`, and starts a full session when run from a real TTY.

Before manual Phase 0 window-behavior validation, check that the deployed Tahoe config still matches the intended baseline:

```sh
bash scripts/check-phase0-window-ops.sh
```

That baseline is intentionally narrow:

- new windows still default to floating;
- the Scheme A Phase 0 repro is a mixed-layout case created manually by opening two windows and pressing `Mod+V` on one window, producing one tiled plus one floating window;
- maximize stays on stock niri behavior for now, so `Mod+F` remains `maximize-column` and `Mod+M` remains `maximize-window-to-edges`; Phase 0 does not replace this with floating-native maximize or add default `open-maximized` / `open-maximized-to-edges` rules.

The script also defaults to `TAHOE_SHELL_LAUNCH_MODE=auto`:

- nested mode uses `child` launch mode, so niri runs Quickshell as the command after `--`.
- session mode uses `config` launch mode, so `~/.config/niri/tahoe/config.kdl` starts Quickshell with `spawn-sh-at-startup`.

In child mode the script exports `TAHOE_SKIP_QUICKSHELL_AUTOSTART=1`, which prevents the config startup hook from creating a second Tahoe shell.

Nested mode also exports `TAHOE_NESTED_SESSION=1`. The Tahoe niri config uses it to skip session-wide systemd/DBus environment imports, Fcitx replacement, and the duplicate polkit agent, so closing a preview cannot leave the real desktop attached to the preview's temporary displays.

Both Tahoe session launchers default to `TAHOE_POWER_PROFILE=auto`. When the machine is on external power, or when no battery is present, they ask `power-profiles-daemon` for the `performance` profile for the lifetime of the niri session and restore the previous profile when niri exits. This avoids GPU/CPU downclock stutter after the desktop has been idle. On battery, `auto` leaves the profile unchanged.

When running from a terminal inside an existing desktop, force nested mode if needed:

```sh
NIRI_MODE=nested bash scripts/run-tahoe-session.sh
```

When running from a real TTY and you want niri to own the session:

```sh
NIRI_MODE=session bash scripts/run-tahoe-session.sh
```

This starts niri with the Tahoe config and lets the config autostart Quickshell. It does not pass Quickshell as a child command.

After `arch-update.sh` deploys the login entry, a display manager can start the same path by selecting `Tahoe Niri`. If the entry is not visible immediately, log out and restart the display manager so it rescans `/usr/share/wayland-sessions`.

The login launcher writes diagnostics to:

```sh
~/.local/state/tahoe-niri/session.log
```

The launcher starts a custom built `~/.local/bin/niri` directly when that binary exists. Otherwise it falls back to the distro `niri-session` wrapper and passes Tahoe's config through the `NIRI_CONFIG` environment variable. Set `TAHOE_USE_NIRI_SESSION_WRAPPER=true` only when explicitly testing the wrapper path.

Useful environment overrides:

```sh
NIRI_MODE=nested bash scripts/run-tahoe-session.sh
TAHOE_SHELL_LAUNCH_MODE=child bash scripts/run-tahoe-session.sh
TAHOE_SHELL_LAUNCH_MODE=config NIRI_MODE=session bash scripts/run-tahoe-session.sh
NIRI_CONFIG=/path/to/config.kdl bash scripts/run-tahoe-session.sh
TAHOE_CONFIG_DIR=/path/to/tahoe-shell bash scripts/run-tahoe-session.sh
NIRI_BIN=/path/to/niri bash scripts/run-tahoe-session.sh
QUICKSHELL_BIN=/path/to/quickshell bash scripts/run-tahoe-session.sh
TAHOE_POWER_PROFILE=keep bash scripts/run-tahoe-session.sh
TAHOE_POWER_PROFILE=performance bash scripts/run-tahoe-session.sh
TAHOE_RESTORE_POWER_PROFILE=false bash scripts/run-tahoe-session.sh
TAHOE_USE_NIRI_SESSION_WRAPPER=false ~/.local/bin/tahoe-niri-session
```

By default, `run-tahoe-session.sh` uses `~/.config/niri/tahoe/config.kdl` and `~/.config/quickshell/tahoe`, which are both managed by `arch-update.sh`.

To start the deployed login-session launcher directly:

```sh
~/.local/bin/tahoe-niri-session
```

Rollback is local: remove or disable the `spawn-sh-at-startup` line in `~/.config/niri/tahoe/config.kdl`, select the stock `Niri` login session instead of `Tahoe Niri`, or run with `TAHOE_SHELL_LAUNCH_MODE=none` for niri-only debugging.
