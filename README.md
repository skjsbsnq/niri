# Tahoe niri + Quickshell Prototype

This repository is the Windows-side source of truth for the niri + Quickshell Tahoe desktop prototype.

## Layout

- `niri/` - niri source checkout, tracked as a Git submodule.
- `quickshell/` - Quickshell source checkout, tracked as a Git submodule.
- `tahoe-shell/` - project-owned Quickshell QML shell prototype.
- `config/niri/tahoe-phase0.kdl` - project-owned niri Phase 0 config.
- `scripts/` - Arch bare-metal one-shot install plus VM bootstrap, update, and session launch scripts.
- `macOS-26-Tahoe-for-the-Web-main/` - visual reference assets and behavior reference.

## Clone

```sh
git clone --recurse-submodules <repo-url>
cd <repo>
```

If the repo was cloned without submodules:

```sh
git submodule update --init --recursive
```

## Bare-Metal Install

On a real Arch Linux machine set up with `archinstall`'s minimal profile, run the one-shot installer from a TTY as a normal user:

```sh
bash scripts/baremetal-install.sh
```

It clones the repo, installs LightDM plus the GUI apps a minimal install lacks, builds both niri and Quickshell forks, sets up CJK locale/fonts/fcitx5, and offers to launch the session. Install your GPU driver yourself first. See `scripts/README.md` for the full environment-variable reference.

## Hyper-V Arch VM

First setup:

```sh
bash scripts/arch-bootstrap.sh
```

After every Windows push:

```sh
bash scripts/arch-update.sh
```

`arch-update.sh` also runs the Tahoe Glass Phase 7 guardrails before deploy. To run them directly:

```sh
bash scripts/check-tahoe-glass-guardrails.sh
```

Start the Phase 0 session:

```sh
bash scripts/run-tahoe-session.sh
```

Verify the Phase 0 window-ops baseline:

```sh
bash scripts/check-phase0-window-ops.sh
```

Scheme A Phase 0 baseline is:

- default desktop model remains all-floating;
- to reproduce the old overlap issue in a controlled mixed-layout case, open two windows and press `Mod+V` on one of them so you end up with one tiled window and one floating window;
- maximize behavior stays on the current niri actions in Phase 0 (`Mod+F` = `maximize-column`, `Mod+M` = `maximize-window-to-edges`); Phase 0 does not replace this with floating-native maximize, and it does not add default `open-maximized` / `open-maximized-to-edges` rules.
