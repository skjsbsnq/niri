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
NIRI_BIN_DIR="${NIRI_BIN_DIR:-"$INSTALL_PREFIX/bin"}"
NIRI_BIN="${NIRI_BIN:-"$INSTALL_PREFIX/bin/niri"}"
NIRI_SESSION_BIN="${NIRI_SESSION_BIN:-niri-session}"
NIRI_CONFIG="${NIRI_CONFIG:-"$HOME/.config/niri/tahoe/config.kdl"}"
QUICKSHELL_BIN="${QUICKSHELL_BIN:-quickshell}"
TAHOE_CONFIG_DIR="${TAHOE_CONFIG_DIR:-"$HOME/.config/quickshell/tahoe"}"
TAHOE_USE_NIRI_SESSION_WRAPPER="${TAHOE_USE_NIRI_SESSION_WRAPPER:-auto}"
TAHOE_SESSION_LOG_DIR="${TAHOE_SESSION_LOG_DIR:-"${XDG_STATE_HOME:-"$HOME/.local/state"}/tahoe-niri"}"
TAHOE_SESSION_LOG_FILE="${TAHOE_SESSION_LOG_FILE:-"$TAHOE_SESSION_LOG_DIR/session.log"}"

export PATH="$NIRI_BIN_DIR:/usr/local/bin:/usr/bin:${PATH:-}"

init_logging() {
  mkdir -p "$TAHOE_SESSION_LOG_DIR"
  exec >>"$TAHOE_SESSION_LOG_FILE" 2>&1

  log "----- $(date -Is) -----"
  log "user: ${USER:-unknown}"
  log "home: $HOME"
  log "path: $PATH"
  log "display: DISPLAY=${DISPLAY:-} WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}"
  log "session: XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-} XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-} DESKTOP_SESSION=${DESKTOP_SESSION:-}"
  log "runtime: XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-} XDG_SEAT=${XDG_SEAT:-} XDG_VTNR=${XDG_VTNR:-}"
}

resolve_command() {
  local command_name="$1"

  if [[ "$command_name" == */* ]]; then
    [[ -x "$command_name" ]] || return 1
    printf '%s\n' "$command_name"
    return
  fi

  if command -v "$command_name" >/dev/null 2>&1; then
    command -v "$command_name"
    return
  fi

  if [[ -x "/usr/local/bin/$command_name" ]]; then
    printf '/usr/local/bin/%s\n' "$command_name"
    return
  fi

  if [[ -x "/usr/bin/$command_name" ]]; then
    printf '/usr/bin/%s\n' "$command_name"
    return
  fi

  return 1
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

  if [[ -x /usr/bin/niri ]]; then
    printf '/usr/bin/niri\n'
    return
  fi

  die "niri binary not found; run scripts/arch-update.sh first"
}

main() {
  local niri_bin
  local niri_session_bin=""
  local quickshell_bin
  local use_wrapper=false

  init_logging

  quickshell_bin="$(resolve_command "$QUICKSHELL_BIN")" || die "missing required command: $QUICKSHELL_BIN"

  [[ -f "$NIRI_CONFIG" ]] || die "NIRI_CONFIG does not exist: $NIRI_CONFIG"
  [[ -f "$TAHOE_CONFIG_DIR/shell.qml" ]] || die "Tahoe shell entry not found: $TAHOE_CONFIG_DIR/shell.qml"

  case "$TAHOE_USE_NIRI_SESSION_WRAPPER" in
    auto)
      if [[ -x "$NIRI_BIN" ]]; then
        log "custom niri binary detected; using direct compositor launch"
        use_wrapper=false
      elif niri_session_bin="$(resolve_command "$NIRI_SESSION_BIN")"; then
        use_wrapper=true
      fi
      ;;
    true)
      niri_session_bin="$(resolve_command "$NIRI_SESSION_BIN")" || die "missing required command: $NIRI_SESSION_BIN"
      use_wrapper=true
      ;;
    false)
      use_wrapper=false
      ;;
    *)
      die "invalid TAHOE_USE_NIRI_SESSION_WRAPPER: $TAHOE_USE_NIRI_SESSION_WRAPPER; expected auto, true, or false"
      ;;
  esac

  export NIRI_CONFIG
  export TAHOE_QUICKSHELL_BIN="$quickshell_bin"
  export TAHOE_CONFIG_DIR
  export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-niri}"
  export XDG_SESSION_DESKTOP="${XDG_SESSION_DESKTOP:-tahoe-niri}"
  export DESKTOP_SESSION="${DESKTOP_SESSION:-tahoe-niri}"

  log "config: $NIRI_CONFIG"
  log "quickshell: $quickshell_bin"
  log "Tahoe shell: $TAHOE_CONFIG_DIR"

  if [[ "$use_wrapper" == true ]]; then
    log "niri session wrapper: $niri_session_bin"
    exec "$niri_session_bin"
  fi

  niri_bin="$(resolve_niri_bin)"
  log "niri: $niri_bin"
  log "niri session wrapper: disabled"
  exec "$niri_bin" --session --config "$NIRI_CONFIG"
}

main "$@"
