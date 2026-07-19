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
TAHOE_STATE_DIR="${TAHOE_STATE_DIR:-"${XDG_STATE_HOME:-"$HOME/.local/state"}/quickshell/by-shell/tahoe"}"
TAHOE_SETTINGS_FILE="${TAHOE_SETTINGS_FILE:-"$TAHOE_STATE_DIR/desktop-settings.json"}"
TAHOE_USE_NIRI_SESSION_WRAPPER="${TAHOE_USE_NIRI_SESSION_WRAPPER:-auto}"
TAHOE_SESSION_LOG_DIR="${TAHOE_SESSION_LOG_DIR:-"${XDG_STATE_HOME:-"$HOME/.local/state"}/tahoe-niri"}"
TAHOE_SESSION_LOG_FILE="${TAHOE_SESSION_LOG_FILE:-"$TAHOE_SESSION_LOG_DIR/session.log"}"
TAHOE_POWER_PROFILE="${TAHOE_POWER_PROFILE:-auto}"
TAHOE_RESTORE_POWER_PROFILE="${TAHOE_RESTORE_POWER_PROFILE:-true}"

TAHOE_PREVIOUS_POWER_PROFILE=""
TAHOE_POWER_PROFILE_CHANGED=false

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
  log "icon theme: ${QS_ICON_THEME:-system default}"
  log "electron: ELECTRON_OZONE_PLATFORM_HINT=${ELECTRON_OZONE_PLATFORM_HINT:-}"
  log "glx: __GLX_VENDOR_LIBRARY_NAME=${__GLX_VENDOR_LIBRARY_NAME:-}"
  log "runtime: XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-} XDG_SEAT=${XDG_SEAT:-} XDG_VTNR=${XDG_VTNR:-}"
  log "requested power profile: $TAHOE_POWER_PROFILE"
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

activate_graphical_session_target() {
  # xdg-desktop-portal*.service declare `Requisite=graphical-session.target`.
  # That target has RefuseManualStart, so it can't be started by hand, but it
  # CAN be activated indirectly as a dependency. When niri is launched directly
  # (the fork-binary path below), nothing binds graphical-session.target —
  # unlike `niri-session`/`niri.service`, which does — so portals fail with
  # "Dependency failed for Portal service". Start a transient oneshot that
  # Wants the target; systemd activates it as a dependency (allowed despite
  # RefuseManualStart), satisfying the portals' Requisite for the session.
  command -v systemd-run >/dev/null 2>&1 || return 0

  systemd-run --user \
    --unit=tahoe-gsession-activate.service \
    --service-type=oneshot \
    --remain-after-exit \
    --property=Wants=graphical-session.target \
    true >/dev/null 2>&1 \
    || log "could not activate graphical-session.target; portals may fail to start"

  # Surface the Wayland display + session vars to user services launched by
  # systemd (portals, fcitx5, xdg autostart). The shell env already has them;
  # the systemd user manager may not.
  systemctl --user import-environment \
    WAYLAND_DISPLAY DISPLAY XAUTHORITY \
    XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_DESKTOP \
    ELECTRON_OZONE_PLATFORM_HINT __GLX_VENDOR_LIBRARY_NAME QS_ICON_THEME 2>/dev/null || true
}

main() {
  local niri_bin
  local niri_session_bin=""
  local quickshell_bin
  local use_wrapper=false

  # Let Electron choose its default backend. Backend-specific workarounds,
  # including Linux QQ's X11 clipboard fallback, belong in per-app flags.
  export ELECTRON_OZONE_PLATFORM_HINT="${ELECTRON_OZONE_PLATFORM_HINT:-auto}"
  # Keep Xwayland GLX clients on the NVIDIA vendor path. Without this, GLVND can
  # select Mesa llvmpipe for Proton launchers even when Xwayland glamor is on.
  export __GLX_VENDOR_LIBRARY_NAME="${__GLX_VENDOR_LIBRARY_NAME:-nvidia}"
  resolve_icon_theme_setting

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
    run_session_command "$niri_session_bin"
  fi

  niri_bin="$(resolve_niri_bin)"
  log "niri: $niri_bin"
  log "niri session wrapper: disabled"
  activate_graphical_session_target
  run_session_command "$niri_bin" --session --config "$NIRI_CONFIG"
}

main "$@"
