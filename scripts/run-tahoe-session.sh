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
  local -a niri_args
  local -a shell_args

  require_cmd "$QUICKSHELL_BIN"

  [[ -d "$TAHOE_CONFIG_DIR" ]] || die "Tahoe shell config directory does not exist: $TAHOE_CONFIG_DIR"
  [[ -f "$TAHOE_CONFIG_DIR/shell.qml" ]] || die "Tahoe shell entry not found: $TAHOE_CONFIG_DIR/shell.qml"

  niri_bin="$(resolve_niri_bin)"
  niri_args=("$niri_bin" "--session")

  if [[ -n "$NIRI_CONFIG" ]]; then
    [[ -f "$NIRI_CONFIG" ]] || die "NIRI_CONFIG does not exist: $NIRI_CONFIG"
    niri_args+=("--config" "$NIRI_CONFIG")
  fi

  shell_args=("$QUICKSHELL_BIN" "-p" "$TAHOE_CONFIG_DIR")

  log "repo: $REPO_DIR"
  log "niri: $niri_bin"
  log "Tahoe shell: $TAHOE_CONFIG_DIR"

  exec "${niri_args[@]}" -- "${shell_args[@]}"
}

main "$@"
