#!/usr/bin/env bash
# Bare-metal one-shot installer for the Tahoe niri + Quickshell desktop.
#
# Intended to run on a fresh Arch Linux installed with archinstall's minimal
# profile, logged in as a normal user on a TTY. It clones (or updates) this
# repo, installs the display manager and GUI apps that a minimal install does
# not ship, then drives the existing scripts/arch-bootstrap.sh chain with the
# fork builds enabled so the real machine can validate niri fork features
# (snap preview / stacking / Liquid Glass shader) and Quickshell fork.
#
# This is a thin orchestrator. All build/deploy logic lives in
# arch-bootstrap.sh / arch-update.sh / arch-zh-setup.sh; this script only adds
# the bare-metal-only pieces (display manager + GUI apps) and sets the fork
# build environment variables for the first deploy pass.
set -Eeuo pipefail

log() {
  printf '[baremetal-install] %s\n' "$*"
}

die() {
  printf '[baremetal-install] ERROR: %s\n' "$*" >&2
  exit 1
}

# ----- top-level config (kept here, per roadmap "关键路径和仓库 URL 集中放在脚本顶部") -----

REPO_URL="${REPO_URL:-https://github.com/skjsbsnq/niri}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/niri}"

ALLOW_ROOT_BAREMETAL="${ALLOW_ROOT_BAREMETAL:-false}"
SKIP_SYSTEM_PACKAGES="${SKIP_SYSTEM_PACKAGES:-false}"
SKIP_ZH_SETUP="${SKIP_ZH_SETUP:-false}"
AUTO_LAUNCH_SESSION="${AUTO_LAUNCH_SESSION:-ask}"

# Display manager, matching the Hyper-V VM (lightdm + lightdm-gtk-greeter).
# arch-update.sh already deploys /usr/share/wayland-sessions/tahoe-niri.desktop,
# so once lightdm is enabled the Tahoe Niri entry shows up in the greeter.
DISPLAY_MANAGER_PACKAGES=(
  lightdm
  lightdm-gtk-greeter
)

# GUI apps the niri config and tahoe-shell call directly, plus runtime helpers
# a minimal archinstall does not provide. Matched to the Hyper-V VM baseline.
GUI_APP_PACKAGES=(
  alacritty
  fuzzel
  swaylock
  swaybg
  brightnessctl
  network-manager-applet
  xdg-desktop-portal
  xdg-desktop-portal-gtk
)

# ----- helpers -----

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

is_git_repo() {
  git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

has_uncommitted_changes() {
  [[ -n "$(git -C "$1" status --porcelain)" ]]
}

# ----- steps -----

preflight_checks() {
  log "preflight checks"

  if [[ ! -f /etc/arch-release ]] && ! command -v pacman >/dev/null 2>&1; then
    die "this script targets Arch Linux; /etc/arch-release not found and pacman not available"
  fi

  if [[ "${EUID:-$(id -u)}" -eq 0 && "$ALLOW_ROOT_BAREMETAL" != true ]]; then
    die "run this as the target desktop user, not as root. The script calls sudo only where needed. Set ALLOW_ROOT_BAREMETAL=true to override."
  fi

  require_cmd git
  require_cmd sudo
  command -v pacman >/dev/null 2>&1 || die "pacman not found; this script requires Arch Linux"
}

fetch_code() {
  log "install dir: $INSTALL_DIR"

  if [[ ! -d "$INSTALL_DIR" ]]; then
    log "cloning repo into $INSTALL_DIR"
    git clone --recurse-submodules "$REPO_URL" "$INSTALL_DIR"
    return
  fi

  if ! is_git_repo "$INSTALL_DIR"; then
    die "$INSTALL_DIR exists but is not a git repository; move it aside or pick a different INSTALL_DIR"
  fi

  if has_uncommitted_changes "$INSTALL_DIR"; then
    die "$INSTALL_DIR has uncommitted changes; commit/stash them or move the directory aside before re-running"
  fi

  log "updating existing repo at $INSTALL_DIR"
  git -C "$INSTALL_DIR" fetch --prune
  git -C "$INSTALL_DIR" pull --ff-only

  if [[ -f "$INSTALL_DIR/.gitmodules" ]]; then
    log "syncing submodules"
    git -C "$INSTALL_DIR" submodule sync --recursive
    git -C "$INSTALL_DIR" submodule update --init --recursive
  fi
}

install_system_packages() {
  if [[ "$SKIP_SYSTEM_PACKAGES" == true ]]; then
    log "skipping system package install because SKIP_SYSTEM_PACKAGES=true"
    return
  fi

  log "installing display manager and GUI app packages"
  sudo pacman -Syu --needed \
    "${DISPLAY_MANAGER_PACKAGES[@]}" \
    "${GUI_APP_PACKAGES[@]}"
}

enable_services() {
  log "enabling NetworkManager"
  sudo systemctl enable --now NetworkManager

  # Do not --now lightdm: if the user is already in a graphical session, starting
  # lightdm mid-session would seize the seat. enable is enough; it starts on the
  # next boot, or the user can `sudo systemctl start lightdm` from a TTY.
  log "enabling lightdm (starts on next boot)"
  sudo systemctl enable lightdm
}

run_bootstrap_and_fork_build() {
  log "running arch-bootstrap.sh with fork builds enabled"
  # These are inherited by arch-update.sh inside the bootstrap chain, so a single
  # first deploy pass builds both the niri fork and the Quickshell fork and
  # installs them under ~/.local/bin.
  export BUILD_NIRI_FORK=auto
  export BUILD_QUICKSHELL_FORK=auto
  bash "$INSTALL_DIR/scripts/arch-bootstrap.sh"
}

run_zh_setup() {
  if [[ "$SKIP_ZH_SETUP" == true ]]; then
    log "skipping Chinese locale/font/input-method setup because SKIP_ZH_SETUP=true"
    return
  fi

  log "running arch-zh-setup.sh for CJK locale/fonts/fcitx5"
  bash "$INSTALL_DIR/scripts/arch-zh-setup.sh"
}

print_summary() {
  local repo_commit niri_bin quickshell_bin session_target

  repo_commit="$(git -C "$INSTALL_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
  niri_bin="$HOME/.local/bin/niri"
  quickshell_bin="$HOME/.local/bin/quickshell"
  session_target="/usr/share/wayland-sessions/tahoe-niri.desktop"

  log "summary:"
  log "  repo:     $INSTALL_DIR @ ${repo_commit:0:12}"
  log "  niri:     $niri_bin $([ -x "$niri_bin" ] && echo '(installed)' || echo '(missing - check arch-update.sh output)')"
  log "  shell:    $quickshell_bin $([ -x "$quickshell_bin" ] && echo '(installed)' || echo '(missing - check arch-update.sh output)')"
  log "  session:  $session_target $([ -f "$session_target" ] && echo '(deployed)' || echo '(missing - check arch-update.sh output)')"
  log "  lightdm:  enabled; starts on next boot (or run: sudo systemctl start lightdm)"
  log ""
  log "next steps:"
  log "  - log out / reboot and pick \"Tahoe Niri\" in the lightdm greeter, OR"
  log "  - launch now from this TTY: bash $INSTALL_DIR/scripts/run-tahoe-session.sh"
}

maybe_launch_session() {
  local in_tty=false
  local answer

  # Only offer an immediate launch when we are on a real TTY (no display server
  # yet) and not root; launching niri as root or inside an existing session is
  # not supported.
  if [[ -z "${WAYLAND_DISPLAY:-}" && -z "${DISPLAY:-}" && "${EUID:-$(id -u)}" -ne 0 ]]; then
    in_tty=true
  fi

  case "$AUTO_LAUNCH_SESSION" in
    true)
      [[ "$in_tty" == true ]] || return
      log "AUTO_LAUNCH_SESSION=true; launching Tahoe session"
      exec bash "$INSTALL_DIR/scripts/run-tahoe-session.sh"
      ;;
    false)
      return
      ;;
    ask)
      [[ "$in_tty" == true ]] || return
      printf '[baremetal-install] 立即启动 Tahoe 会话? [y/N] '
      read -r answer
      case "$answer" in
        y|Y|yes|YES)
          log "launching Tahoe session"
          exec bash "$INSTALL_DIR/scripts/run-tahoe-session.sh"
          ;;
        *)
          log "skipping session launch; run the session manually later"
          ;;
      esac
      ;;
    *)
      die "invalid AUTO_LAUNCH_SESSION: $AUTO_LAUNCH_SESSION; expected ask, true, or false"
      ;;
  esac
}

main() {
  preflight_checks
  fetch_code
  install_system_packages
  enable_services
  run_bootstrap_and_fork_build
  run_zh_setup
  print_summary
  maybe_launch_session
}

main "$@"
