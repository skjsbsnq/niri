#!/usr/bin/env bash
set -Eeuo pipefail

TAHOE_CONFIG_DIR="${TAHOE_CONFIG_DIR:-"$HOME/.config/quickshell/tahoe"}"
TAHOE_STATE_DIR="${TAHOE_STATE_DIR:-"${XDG_STATE_HOME:-"$HOME/.local/state"}/quickshell/by-shell/tahoe"}"
TAHOE_SETTINGS_FILE="${TAHOE_SETTINGS_FILE:-"$TAHOE_STATE_DIR/desktop-settings.json"}"

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

resolve_quickshell_bin() {
  local qs_bin="${TAHOE_QUICKSHELL_BIN:-}"

  if [[ -n "$qs_bin" ]]; then
    printf '%s\n' "$qs_bin"
    return
  fi

  if [[ -x "$HOME/.local/bin/quickshell" ]]; then
    printf '%s\n' "$HOME/.local/bin/quickshell"
    return
  fi

  printf 'quickshell\n'
}

resolve_icon_theme_setting
exec "$(resolve_quickshell_bin)" -p "$TAHOE_CONFIG_DIR"
