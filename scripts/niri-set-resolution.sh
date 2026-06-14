#!/usr/bin/env bash
set -Eeuo pipefail

# Switch the resolution of the niri output currently in use.
#
# Default target is 1920x1080@60. Override with a positional argument using the
# form WIDTHxHEIGHT or WIDTHxHEIGHT@REFRESH_HZ, e.g.
#
#   bash scripts/niri-set-resolution.sh
#   bash scripts/niri-set-resolution.sh 1920x1080@60
#   bash scripts/niri-set-resolution.sh 1280x800
#   OUTPUT_NAME=Virtual-1 bash scripts/niri-set-resolution.sh 1600x900@60
#
# The change is applied via `niri msg output`, which is a temporary change — it
# is NOT written back to ~/.config/niri/tahoe/config.kdl. To make it permanent,
# add an `output "<name>" { mode 1920x1080.000; }` block to that config file.

log() {
  printf '[niri-set-resolution] %s\n' "$*"
}

die() {
  printf '[niri-set-resolution] ERROR: %s\n' "$*" >&2
  exit 1
}

MODE="${1:-1920x1080@60}"
OUTPUT_NAME="${OUTPUT_NAME:-}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

# niri msg only talks to a running niri instance. jq is used to parse JSON;
# fall back to plain text if it is missing.
require_cmd niri
HAS_JQ=false
if command -v jq >/dev/null 2>&1; then
  HAS_JQ=true
fi

niri_msg() {
  niri msg "$@"
}

resolve_output_name() {
  if [[ -n "$OUTPUT_NAME" ]]; then
    printf '%s\n' "$OUTPUT_NAME"
    return
  fi

  # Prefer the focused output so the script targets the screen the user is
  # actually looking at. focused-output fails when no window is focused, in
  # which case fall back to the first connected output from `outputs`.
  local name=""

  if [[ "$HAS_JQ" == true ]]; then
    name="$(niri_msg focused-output --json 2>/dev/null | jq -r '.name // empty' 2>/dev/null || true)"
  fi

  if [[ -z "$name" ]]; then
    # Fall back to first connected output. `outputs --json` returns an object
    # keyed by output name; pick the first one.
    if [[ "$HAS_JQ" == true ]]; then
      name="$(niri_msg outputs --json 2>/dev/null | jq -r 'to_entries[0].key' 2>/dev/null || true)"
    fi
  fi

  if [[ -z "$name" ]]; then
    die "could not determine output name; set OUTPUT_NAME explicitly or install jq"
  fi

  printf '%s\n' "$name"
}

describe_current_mode() {
  local output_name="$1"

  if [[ "$HAS_JQ" != true ]]; then
    return
  fi

  niri_msg outputs --json 2>/dev/null \
    | jq -r --arg n "$output_name" \
        '.[$n] | "current: \(.logical.width|round)x\(.logical.height|round) @ \((.logical.refresh // 0) / 1000.0|round)Hz  (\(.name // "?"))"' \
    2>/dev/null || true
}

main() {
  local output_name

  output_name="$(resolve_output_name)"

  log "output: $output_name"
  log "target mode: $MODE"
  log "applying (temporary — not written to config.kdl)..."

  if ! niri_msg output "$output_name" mode "$MODE"; then
    die "niri rejected mode '$MODE' on '$output_name'. Check supported modes with: niri msg outputs"
  fi

  log "done. New state:"
  describe_current_mode "$output_name" || true

  if [[ "$HAS_JQ" != true ]]; then
    log "tip: install jq for richer status output. Verify with: niri msg outputs"
  fi
}

main "$@"
