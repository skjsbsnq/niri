#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '[tahoe-niri-session] %s\n' "$*"
}

die() {
  printf '[tahoe-niri-session] ERROR: %s\n' "$*" >&2
  exit 1
}

INSTALL_PREFIX="${INSTALL_PREFIX:-"$HOME/.local"}"
NIRI_BIN="${NIRI_BIN:-"$INSTALL_PREFIX/bin/niri"}"
NIRI_CONFIG="${NIRI_CONFIG:-"$HOME/.config/niri/tahoe/config.kdl"}"
QUICKSHELL_BIN="${QUICKSHELL_BIN:-quickshell}"
TAHOE_CONFIG_DIR="${TAHOE_CONFIG_DIR:-"$HOME/.config/quickshell/tahoe"}"

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

  command -v "$QUICKSHELL_BIN" >/dev/null 2>&1 || die "missing required command: $QUICKSHELL_BIN"
  [[ -f "$NIRI_CONFIG" ]] || die "NIRI_CONFIG does not exist: $NIRI_CONFIG"
  [[ -f "$TAHOE_CONFIG_DIR/shell.qml" ]] || die "Tahoe shell entry not found: $TAHOE_CONFIG_DIR/shell.qml"

  niri_bin="$(resolve_niri_bin)"

  export TAHOE_QUICKSHELL_BIN="$QUICKSHELL_BIN"
  export TAHOE_CONFIG_DIR
  log "niri: $niri_bin"
  log "config: $NIRI_CONFIG"
  log "Tahoe shell: $TAHOE_CONFIG_DIR"

  exec "$niri_bin" --session --config "$NIRI_CONFIG"
}

main "$@"
