#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '[glass-baseline] %s\n' "$*"
}

die() {
  printf '[glass-baseline] ERROR: %s\n' "$*" >&2
  exit 1
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-"$(cd -- "$SCRIPT_DIR/.." && pwd)"}"
NIRI_DIR="${NIRI_DIR:-"$REPO_DIR/niri"}"
QUICKSHELL_DIR="${QUICKSHELL_DIR:-"$REPO_DIR/quickshell"}"
NIRI_CONFIG_SRC="${NIRI_CONFIG_SRC:-"$REPO_DIR/config/niri/tahoe-phase0.kdl"}"
NIRI_CONFIG_TARGET="${NIRI_CONFIG_TARGET:-"$HOME/.config/niri/tahoe/config.kdl"}"
TAHOE_CONFIG_DIR="${TAHOE_CONFIG_DIR:-"$HOME/.config/quickshell/tahoe"}"
BASELINE_DIR="${BASELINE_DIR:-"$REPO_DIR/tahoe-shell/docs/visual-baselines/2026-06-15-phase0-glass-geometry"}"
REPORT_DIR="${REPORT_DIR:-"$REPO_DIR/tahoe-shell/docs/visual-baselines/runtime"}"
REPORT_PATH="${REPORT_PATH:-"$REPORT_DIR/glass-baseline-$(date '+%Y%m%d-%H%M%S').md"}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

git_value() {
  local dir="$1"
  shift

  if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$dir" "$@" 2>/dev/null || true
  else
    printf '(not a git worktree)'
  fi
}

file_sha256() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    printf '(missing)'
    return
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  else
    printf '(sha256 tool missing)'
  fi
}

append_git_section() {
  local title="$1"
  local dir="$2"

  {
    printf '## %s\n\n' "$title"
    printf -- '- Path: `%s`\n' "$dir"
    printf -- '- HEAD: `%s`\n' "$(git_value "$dir" rev-parse HEAD)"
    printf -- '- Branch: `%s`\n' "$(git_value "$dir" branch --show-current)"
    printf -- '- Last commit: `%s`\n' "$(git_value "$dir" log -1 --pretty='%h %s')"
    printf '\n### Status\n\n'
    printf '```text\n'
    git_value "$dir" status --short --branch
    printf '\n```\n\n'
  } >> "$REPORT_PATH"
}

append_command_block() {
  local title="$1"
  shift

  {
    printf '## %s\n\n' "$title"
    printf 'Command: `%s`\n\n' "$*"
    printf '```text\n'
    "$@" 2>&1 || true
    printf '\n```\n\n'
  } >> "$REPORT_PATH"
}

append_optional_command_block() {
  local title="$1"
  local cmd="$2"
  shift 2

  if command -v "$cmd" >/dev/null 2>&1; then
    append_command_block "$title" "$cmd" "$@"
  else
    {
      printf '## %s\n\n' "$title"
      printf '`%s` not found.\n\n' "$cmd"
    } >> "$REPORT_PATH"
  fi
}

append_baseline_assets() {
  {
    printf '## Baseline screenshot assets\n\n'
    printf -- '- Directory: `%s`\n\n' "$BASELINE_DIR"
    printf '| File | SHA-256 |\n'
    printf '| --- | --- |\n'
  } >> "$REPORT_PATH"

  if [[ ! -d "$BASELINE_DIR" ]]; then
    {
      printf '| `(baseline directory missing)` | `(missing)` |\n'
      printf '\n'
    } >> "$REPORT_PATH"
    return
  fi

  local found=false
  local image
  for image in "$BASELINE_DIR"/*.png; do
    [[ -e "$image" ]] || continue
    found=true
    printf '| `%s` | `%s` |\n' "$(basename "$image")" "$(file_sha256 "$image")" >> "$REPORT_PATH"
  done

  if [[ "$found" == false ]]; then
    printf '| `(no png files found)` | `(missing)` |\n' >> "$REPORT_PATH"
  fi

  printf '\n' >> "$REPORT_PATH"
}

main() {
  require_cmd git
  require_cmd date
  require_cmd mkdir

  mkdir -p "$REPORT_DIR"
  : > "$REPORT_PATH"

  {
    printf '# Tahoe glass Phase 0 runtime baseline\n\n'
    printf -- '- Generated local time: `%s`\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
    printf -- '- Generated UTC: `%s`\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    printf -- '- Host: `%s`\n' "$(hostname 2>/dev/null || printf unknown)"
    printf -- '- User: `%s`\n' "$(whoami 2>/dev/null || printf unknown)"
    printf -- '- Repo: `%s`\n' "$REPO_DIR"
    printf '\n'
    printf 'Reference screenshots are tracked under:\n\n'
    printf -- '- `tahoe-shell/docs/visual-baselines/2026-06-15-phase0-glass-geometry/spotlight-search-halo.png`\n'
    printf -- '- `tahoe-shell/docs/visual-baselines/2026-06-15-phase0-glass-geometry/notification-center-rectangular-backing.png`\n'
    printf -- '- `tahoe-shell/docs/visual-baselines/2026-06-15-phase0-glass-geometry/control-center-rectangular-backing.png`\n'
    printf '\n'
  } >> "$REPORT_PATH"

  append_git_section "Root repo" "$REPO_DIR"
  append_git_section "niri submodule" "$NIRI_DIR"
  append_git_section "Quickshell submodule" "$QUICKSHELL_DIR"
  append_baseline_assets

  {
    printf '## Tahoe config hashes\n\n'
    printf '| File | SHA-256 |\n'
    printf '| --- | --- |\n'
    printf '| `%s` | `%s` |\n' "$NIRI_CONFIG_SRC" "$(file_sha256 "$NIRI_CONFIG_SRC")"
    printf '| `%s` | `%s` |\n' "$NIRI_CONFIG_TARGET" "$(file_sha256 "$NIRI_CONFIG_TARGET")"
    printf '| `%s/shell.qml` | `%s` |\n' "$TAHOE_CONFIG_DIR" "$(file_sha256 "$TAHOE_CONFIG_DIR/shell.qml")"
    printf '\n'
  } >> "$REPORT_PATH"

  {
    printf '## Session environment\n\n'
    printf '```text\n'
    printf 'XDG_SESSION_TYPE=%s\n' "${XDG_SESSION_TYPE:-<unset>}"
    printf 'XDG_CURRENT_DESKTOP=%s\n' "${XDG_CURRENT_DESKTOP:-<unset>}"
    printf 'WAYLAND_DISPLAY=%s\n' "${WAYLAND_DISPLAY:-<unset>}"
    printf 'DISPLAY=%s\n' "${DISPLAY:-<unset>}"
    printf 'NIRI_SOCKET=%s\n' "${NIRI_SOCKET:-<unset>}"
    printf 'TAHOE_CONFIG_DIR=%s\n' "${TAHOE_CONFIG_DIR:-<unset>}"
    printf 'NIRI_CONFIG_TARGET=%s\n' "$NIRI_CONFIG_TARGET"
    printf '```\n\n'
  } >> "$REPORT_PATH"

  append_optional_command_block "niri version" niri --version
  append_optional_command_block "quickshell version" quickshell --version
  append_optional_command_block "niri focused output" niri msg focused-output
  append_optional_command_block "niri outputs" niri msg outputs
  append_optional_command_block "niri outputs JSON" niri msg --json outputs
  append_optional_command_block "pacman niri package" pacman -Q niri
  append_optional_command_block "pacman quickshell packages" pacman -Q quickshell quickshell-git quickshell-xdg

  log "wrote $REPORT_PATH"
}

main "$@"
