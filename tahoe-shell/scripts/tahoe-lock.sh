#!/usr/bin/env bash
set -Eeuo pipefail

TAHOE_CONFIG_DIR="${TAHOE_CONFIG_DIR:-"$HOME/.config/quickshell/tahoe"}"
LOCK_SOURCE="${1:-shortcut}"

resolve_quickshell_bin() {
  local qs_bin="${TAHOE_QUICKSHELL_BIN:-}"

  if [[ -n "$qs_bin" ]]; then
    if [[ "$qs_bin" == */* ]]; then
      [[ -x "$qs_bin" ]] || return 1
      printf '%s\n' "$qs_bin"
      return
    fi

    command -v "$qs_bin"
    return
  fi

  if [[ -x "$HOME/.local/bin/quickshell" ]]; then
    printf '%s\n' "$HOME/.local/bin/quickshell"
    return
  fi

  command -v quickshell
}

call_tahoe_lock() {
  local qs_bin

  qs_bin="$(resolve_quickshell_bin)" || return 1

  "$qs_bin" ipc -p "$TAHOE_CONFIG_DIR" call tahoe lockFrom "$LOCK_SOURCE" >/dev/null 2>&1 \
    || "$qs_bin" ipc -p "$TAHOE_CONFIG_DIR" call tahoe lock >/dev/null 2>&1
}

call_loginctl_lock() {
  command -v loginctl >/dev/null 2>&1 || return 1

  if [[ -n "${XDG_SESSION_ID:-}" ]]; then
    loginctl lock-session "$XDG_SESSION_ID" >/dev/null 2>&1
  else
    loginctl lock-session >/dev/null 2>&1
  fi
}

call_swaylock_fallback() {
  command -v swaylock >/dev/null 2>&1 || return 1
  exec swaylock
}

if call_tahoe_lock; then
  exit 0
fi

if call_loginctl_lock; then
  exit 0
fi

# Emergency fallback only. The Tahoe IPC path above is the normal lock path.
if call_swaylock_fallback; then
  exit 0
fi

printf '[tahoe-lock] no Tahoe lock IPC, loginctl lock, or swaylock fallback available\n' >&2
exit 1
