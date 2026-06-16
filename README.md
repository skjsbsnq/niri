# Tahoe niri + Quickshell Prototype

This repository is the Windows-side source of truth for the niri + Quickshell Tahoe desktop prototype.

## Layout

- `niri/` - niri source checkout, tracked as a Git submodule.
- `quickshell/` - Quickshell source checkout, tracked as a Git submodule.
- `tahoe-shell/` - project-owned Quickshell QML shell prototype.
- `config/niri/tahoe-phase0.kdl` - project-owned niri Phase 0 config.
- `scripts/` - Arch VM bootstrap, update, and session launch scripts.
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
