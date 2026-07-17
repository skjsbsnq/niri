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
TAHOE_STATE_DIR="${TAHOE_STATE_DIR:-"${XDG_STATE_HOME:-"$HOME/.local/state"}/quickshell/by-shell/tahoe"}"
TAHOE_SETTINGS_FILE="${TAHOE_SETTINGS_FILE:-"$TAHOE_STATE_DIR/desktop-settings.json"}"
NIRI_CONFIG="${NIRI_CONFIG:-"$HOME/.config/niri/tahoe/config.kdl"}"
NIRI_MODE="${NIRI_MODE:-auto}"
TAHOE_SHELL_LAUNCH_MODE="${TAHOE_SHELL_LAUNCH_MODE:-auto}"
TAHOE_POWER_PROFILE="${TAHOE_POWER_PROFILE:-auto}"
TAHOE_RESTORE_POWER_PROFILE="${TAHOE_RESTORE_POWER_PROFILE:-true}"

TAHOE_PREVIOUS_POWER_PROFILE=""
TAHOE_POWER_PROFILE_CHANGED=false

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

json_string_setting() {
  local key="$1"
  local file="$2"

  awk -v needle="\"$key\"" '
    index($0, needle) {
      split($0, parts, "\"")
      if (length(parts) >= 4) {
        print parts[4]
        exit
      }
    }
  ' "$file"
}

sanitize_icon_theme() {
  local value="$1"
  local cleaned

  value="${value//$'\n'/}"
  value="${value//$'\r'/}"
  value="${value//$'\t'/}"
  value="${value//\//}"
  value="${value//\\/}"
  value="${value//:/}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  cleaned="$(printf '%s' "$value" | tr -cd '[:alnum:]. _-')"
  printf '%s\n' "$cleaned"
}

resolve_icon_theme_setting() {
  local mode custom theme

  [[ -n "${QS_ICON_THEME:-}" ]] && return 0
  [[ -r "$TAHOE_SETTINGS_FILE" ]] || return 0

  mode="$(json_string_setting iconThemeMode "$TAHOE_SETTINGS_FILE")"
  custom="$(json_string_setting customIconTheme "$TAHOE_SETTINGS_FILE")"

  case "$mode" in
    papirus)
      theme="Papirus"
      ;;
    papirus-dark)
      theme="Papirus-Dark"
      ;;
    papirus-light)
      theme="Papirus-Light"
      ;;
    custom)
      theme="$custom"
      ;;
    *)
      theme=""
      ;;
  esac

  theme="$(sanitize_icon_theme "$theme")"
  [[ -n "$theme" ]] && export QS_ICON_THEME="$theme"
  return 0
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

has_battery() {
  local supply

  for supply in /sys/class/power_supply/*; do
    [[ -e "$supply/type" ]] || continue
    [[ "$(cat "$supply/type" 2>/dev/null || true)" == Battery ]] && return 0
  done

  return 1
}

is_on_external_power() {
  local supply type online

  for supply in /sys/class/power_supply/*; do
    [[ -e "$supply/type" ]] || continue
    type="$(cat "$supply/type" 2>/dev/null || true)"

    case "$type" in
      Mains|USB|USB_C|USB_PD|Wireless)
        online="$(cat "$supply/online" 2>/dev/null || true)"
        [[ "$online" == 1 ]] && return 0
        ;;
    esac
  done

  # Desktops normally do not expose a battery, so treat them as externally
  # powered.
  if ! has_battery; then
    return 0
  fi

  return 1
}

resolve_power_profile_target() {
  case "$TAHOE_POWER_PROFILE" in
    ""|off|none|keep)
      return 1
      ;;
    auto)
      if is_on_external_power; then
        printf 'balanced\n'
      else
        printf 'power-saver\n'
      fi
      return 0
      ;;
    power-saver|balanced|performance)
      printf '%s\n' "$TAHOE_POWER_PROFILE"
      ;;
    *)
      die "invalid TAHOE_POWER_PROFILE: $TAHOE_POWER_PROFILE; expected auto, performance, balanced, power-saver, or keep"
      ;;
  esac
}

apply_power_profile() {
  local target current

  if ! target="$(resolve_power_profile_target)"; then
    log "power profile: unchanged ($TAHOE_POWER_PROFILE)"
    return
  fi

  if ! command -v powerprofilesctl >/dev/null 2>&1; then
    log "power profile: powerprofilesctl not found; leaving unchanged"
    return
  fi

  current="$(powerprofilesctl get 2>/dev/null || true)"
  if [[ -z "$current" ]]; then
    log "power profile: unavailable; leaving unchanged"
    return
  fi

  TAHOE_PREVIOUS_POWER_PROFILE="$current"
  if [[ "$current" == "$target" ]]; then
    log "power profile: $target"
    return
  fi

  if powerprofilesctl set "$target" >/dev/null 2>&1; then
    TAHOE_POWER_PROFILE_CHANGED=true
    log "power profile: $current -> $target"
  else
    TAHOE_PREVIOUS_POWER_PROFILE=""
    log "power profile: could not switch $current -> $target"
  fi
}

restore_power_profile() {
  if [[ "$TAHOE_RESTORE_POWER_PROFILE" != true || "$TAHOE_POWER_PROFILE_CHANGED" != true || -z "$TAHOE_PREVIOUS_POWER_PROFILE" ]]; then
    return
  fi

  if command -v powerprofilesctl >/dev/null 2>&1 \
    && powerprofilesctl set "$TAHOE_PREVIOUS_POWER_PROFILE" >/dev/null 2>&1; then
    log "power profile: restored $TAHOE_PREVIOUS_POWER_PROFILE"
  else
    log "power profile: could not restore $TAHOE_PREVIOUS_POWER_PROFILE"
  fi
}

run_session_command() {
  local child status

  apply_power_profile

  if [[ "$TAHOE_RESTORE_POWER_PROFILE" != true || "$TAHOE_POWER_PROFILE_CHANGED" != true ]]; then
    exec "$@"
  fi

  set +e
  "$@" &
  child=$!
  trap 'kill -TERM "$child" 2>/dev/null' TERM HUP
  trap 'kill -INT "$child" 2>/dev/null' INT
  wait "$child"
  status=$?
  trap - TERM HUP INT
  restore_power_profile
  exit "$status"
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

  # Nested previews share the user's D-Bus and systemd user manager with the
  # real desktop. Mark them so the main config does not publish the nested
  # WAYLAND_DISPLAY/DISPLAY or replace session-wide agents such as Fcitx.
  if [[ "$resolved_mode" == nested ]]; then
    export TAHOE_NESTED_SESSION=1
  else
    unset TAHOE_NESTED_SESSION
  fi

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
  resolve_icon_theme_setting

  log "repo: $REPO_DIR"
  log "niri: $niri_bin"
  log "mode: $resolved_mode"
  log "shell launch: $shell_launch_mode"
  log "Tahoe shell: $TAHOE_CONFIG_DIR"
  log "icon theme: ${QS_ICON_THEME:-system default}"
  log "glx vendor: ${__GLX_VENDOR_LIBRARY_NAME:-}"
  log "requested power profile: $TAHOE_POWER_PROFILE"

  if [[ "$shell_launch_mode" != none ]]; then
    export TAHOE_QUICKSHELL_BIN="$QUICKSHELL_BIN"
    export TAHOE_CONFIG_DIR
  fi

  if [[ "$shell_launch_mode" == child ]]; then
    export TAHOE_SKIP_QUICKSHELL_AUTOSTART=1
    run_session_command "${niri_args[@]}" -- "${shell_args[@]}"
  fi

  if [[ "$shell_launch_mode" == none ]]; then
    export TAHOE_SKIP_QUICKSHELL_AUTOSTART=1
  fi

  run_session_command "${niri_args[@]}"
}

main "$@"
