#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '[arch-bootstrap] %s\n' "$*"
}

die() {
  printf '[arch-bootstrap] ERROR: %s\n' "$*" >&2
  exit 1
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-"$(cd -- "$SCRIPT_DIR/.." && pwd)"}"
SKIP_PACKAGES="${SKIP_PACKAGES:-false}"

PACMAN_PACKAGES=(
  base-devel
  cargo
  clang
  cli11
  cmake
  git
  jemalloc
  libdrm
  libdisplay-info
  libinput
  libpipewire
  libxcb
  libxkbcommon
  mesa
  networkmanager
  niri
  ninja
  pam
  pipewire
  polkit
  power-profiles-daemon
  pkgconf
  qt6-base
  qt6-declarative
  qt6-shadertools
  qt6-svg
  qt6-wayland
  rsync
  seatd
  spirv-tools
  upower
  vulkan-headers
  wayland
  wayland-protocols
  wl-clipboard
  cliphist
)

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

install_packages() {
  if [[ "$SKIP_PACKAGES" == true ]]; then
    log "skipping package install because SKIP_PACKAGES=true"
    return
  fi

  if ! command -v pacman >/dev/null 2>&1; then
    log "pacman not found; skipping Arch package install"
    return
  fi

  require_cmd sudo
  log "installing Arch build/runtime packages"
  sudo pacman -Syu --needed "${PACMAN_PACKAGES[@]}"
}

enable_power_profiles_daemon() {
  command -v systemctl >/dev/null 2>&1 || return
  command -v sudo >/dev/null 2>&1 || return

  if ! systemctl list-unit-files power-profiles-daemon.service >/dev/null 2>&1; then
    return
  fi

  log "enabling power-profiles-daemon"
  sudo systemctl enable --now power-profiles-daemon >/dev/null 2>&1 \
    || log "could not enable power-profiles-daemon; Tahoe can still run, but automatic power budgeting may be unavailable"
}

main() {
  require_cmd git

  if [[ ! -d "$REPO_DIR/.git" && ! -d "$REPO_DIR/niri/.git" ]]; then
    die "expected either REPO_DIR or REPO_DIR/niri to be a git repository"
  fi

  if [[ -f "$REPO_DIR/.gitmodules" ]]; then
    log "initializing submodules"
    git -C "$REPO_DIR" submodule sync --recursive
    git -C "$REPO_DIR" submodule update --init --recursive
  fi

  install_packages
  enable_power_profiles_daemon

  if ! command -v quickshell >/dev/null 2>&1; then
    log "quickshell command not found"
    log "install Quickshell through your chosen Arch/AUR/Nix path before shell validation"
  fi

  log "running arch-update.sh for initial build/deploy"
  bash "$SCRIPT_DIR/arch-update.sh"

  log "bootstrap complete"
}

main "$@"
