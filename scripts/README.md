# Arch VM Scripts

These scripts are intended to be run inside the Hyper-V Arch Linux VM.

If the repository was cloned without `--recurse-submodules`, both `arch-bootstrap.sh` and `arch-update.sh` initialize the registered submodules before they deploy configs or build niri.

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
- Tahoe shell: `~/.config/quickshell/tahoe`
- session launcher: `~/.local/bin/tahoe-niri-session`
- system session launcher: `/usr/local/bin/tahoe-niri-session`
- user Wayland session entry: `~/.local/share/wayland-sessions/tahoe-niri.desktop`
- system Wayland session entry: `/usr/share/wayland-sessions/tahoe-niri.desktop`

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

The script also defaults to `TAHOE_SHELL_LAUNCH_MODE=auto`:

- nested mode uses `child` launch mode, so niri runs Quickshell as the command after `--`.
- session mode uses `config` launch mode, so `~/.config/niri/tahoe/config.kdl` starts Quickshell with `spawn-sh-at-startup`.

In child mode the script exports `TAHOE_SKIP_QUICKSHELL_AUTOSTART=1`, which prevents the config startup hook from creating a second Tahoe shell.

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
TAHOE_USE_NIRI_SESSION_WRAPPER=false ~/.local/bin/tahoe-niri-session
```

By default, `run-tahoe-session.sh` uses `~/.config/niri/tahoe/config.kdl` and `~/.config/quickshell/tahoe`, which are both managed by `arch-update.sh`.

To start the deployed login-session launcher directly:

```sh
~/.local/bin/tahoe-niri-session
```

Rollback is local: remove or disable the `spawn-sh-at-startup` line in `~/.config/niri/tahoe/config.kdl`, select the stock `Niri` login session instead of `Tahoe Niri`, or run with `TAHOE_SHELL_LAUNCH_MODE=none` for niri-only debugging.
