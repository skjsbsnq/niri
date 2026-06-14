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

This is the only update command expected during Phase 0 and Phase 1 work. It pulls the latest code, deploys `tahoe-shell/` and `config/niri/tahoe-phase0.kdl` when needed, and prints whether niri or Quickshell should be restarted.

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

## Start Session

```sh
bash scripts/run-tahoe-session.sh
```

Useful environment overrides:

```sh
NIRI_CONFIG=/path/to/config.kdl bash scripts/run-tahoe-session.sh
TAHOE_CONFIG_DIR=/path/to/tahoe-shell bash scripts/run-tahoe-session.sh
NIRI_BIN=/path/to/niri bash scripts/run-tahoe-session.sh
QUICKSHELL_BIN=/path/to/quickshell bash scripts/run-tahoe-session.sh
```

By default, `run-tahoe-session.sh` uses `~/.config/niri/tahoe/config.kdl` and `~/.config/quickshell/tahoe`, which are both managed by `arch-update.sh`.
