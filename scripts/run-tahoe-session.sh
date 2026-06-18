#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '[run-tahoe-session] %s\n' "$*"
}

die() {
  printf '[run-tahoe-session] ERROR: %s\n' "$*" >&2
  exit 1
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-"$(cd -- "$SCRIPT_DIR/.." && pwd)"}"

INSTALL_PREFIX="${INSTALL_PREFIX:-"$HOME/.local"}"
NIRI_BIN="${NIRI_BIN:-"$INSTALL_PREFIX/bin/niri"}"
QUICKSHELL_BIN="${QUICKSHELL_BIN:-quickshell}"
TAHOE_CONFIG_DIR="${TAHOE_CONFIG_DIR:-"$HOME/.config/quickshell/tahoe"}"
NIRI_CONFIG="${NIRI_CONFIG:-"$HOME/.config/niri/tahoe/config.kdl"}"
NIRI_MODE="${NIRI_MODE:-auto}"
TAHOE_SHELL_LAUNCH_MODE="${TAHOE_SHELL_LAUNCH_MODE:-auto}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

resolve_niri_bin() {
  if [[ -x "$NIRI_BIN" ]]; then
    printf '%s\n' "$NIRI_BIN"
    return
  fi

  if command -v niri >/dev/null 2>&1; then
    command -v niri
    return
  fi

  die "niri binary not found; run scripts/arch-update.sh first"
}

main() {
  local niri_bin
  local resolved_mode
  local shell_launch_mode
  local -a niri_args
  local -a shell_args

  niri_bin="$(resolve_niri_bin)"

  case "$NIRI_MODE" in
    auto)
      if [[ -n "${WAYLAND_DISPLAY:-}" || -n "${DISPLAY:-}" ]]; then
        resolved_mode="nested"
      else
        resolved_mode="session"
      fi
      ;;
    nested|session)
      resolved_mode="$NIRI_MODE"
      ;;
    *)
      die "invalid NIRI_MODE: $NIRI_MODE; expected auto, nested, or session"
      ;;
  esac

  case "$TAHOE_SHELL_LAUNCH_MODE" in
    auto)
      if [[ "$resolved_mode" == nested ]]; then
        shell_launch_mode="child"
      else
        shell_launch_mode="config"
      fi
      ;;
    child|config|none)
      shell_launch_mode="$TAHOE_SHELL_LAUNCH_MODE"
      ;;
    *)
      die "invalid TAHOE_SHELL_LAUNCH_MODE: $TAHOE_SHELL_LAUNCH_MODE; expected auto, child, config, or none"
      ;;
  esac

  if [[ "$shell_launch_mode" != none ]]; then
    require_cmd "$QUICKSHELL_BIN"
    [[ -d "$TAHOE_CONFIG_DIR" ]] || die "Tahoe shell config directory does not exist: $TAHOE_CONFIG_DIR"
    [[ -f "$TAHOE_CONFIG_DIR/shell.qml" ]] || die "Tahoe shell entry not found: $TAHOE_CONFIG_DIR/shell.qml"
  fi

  niri_args=("$niri_bin")
  if [[ "$resolved_mode" == session ]]; then
    niri_args+=("--session")
  fi

  if [[ -n "$NIRI_CONFIG" ]]; then
    [[ -f "$NIRI_CONFIG" ]] || die "NIRI_CONFIG does not exist: $NIRI_CONFIG"
    niri_args+=("--config" "$NIRI_CONFIG")
  fi

  shell_args=("$QUICKSHELL_BIN" "-p" "$TAHOE_CONFIG_DIR")

  export __GLX_VENDOR_LIBRARY_NAME="${__GLX_VENDOR_LIBRARY_NAME:-nvidia}"

  log "repo: $REPO_DIR"
  log "niri: $niri_bin"
  log "mode: $resolved_mode"
  log "shell launch: $shell_launch_mode"
  log "Tahoe shell: $TAHOE_CONFIG_DIR"
  log "glx vendor: ${__GLX_VENDOR_LIBRARY_NAME:-}"

  if [[ "$shell_launch_mode" != none ]]; then
    export TAHOE_QUICKSHELL_BIN="$QUICKSHELL_BIN"
    export TAHOE_CONFIG_DIR
  fi

  if [[ "$shell_launch_mode" == child ]]; then
    export TAHOE_SKIP_QUICKSHELL_AUTOSTART=1
    exec "${niri_args[@]}" -- "${shell_args[@]}"
  fi

  if [[ "$shell_launch_mode" == none ]]; then
    export TAHOE_SKIP_QUICKSHELL_AUTOSTART=1
  fi

  exec "${niri_args[@]}"
}

main "$@"
