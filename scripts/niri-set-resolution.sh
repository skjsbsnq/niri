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
#
# Requires only `niri` itself; jq is optional and used only for nicer status.

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

require_cmd niri
require_cmd sed
require_cmd grep

# Extract the connector name from the first `Output "..." ({name})` line that
# `niri msg outputs` prints. Returns empty string if the format doesn't match
# (e.g. niri is not reachable or returns "No output is focused.").
extract_output_name() {
  sed -n 's/^Output "[^"]*" (\([^)]*\)).*/\1/p' | head -n 1
}

resolve_output_name() {
  if [[ -n "$OUTPUT_NAME" ]]; then
    printf '%s\n' "$OUTPUT_NAME"
    return
  fi

  local name=""

  # Prefer the focused output. `focused-output` prints "No output is focused."
  # when nothing is focused; the sed pattern yields empty in that case.
  name="$(niri msg focused-output 2>/dev/null | extract_output_name || true)"

  # Fall back to the first listed output.
  if [[ -z "$name" ]]; then
    name="$(niri msg outputs 2>/dev/null | extract_output_name || true)"
  fi

  if [[ -z "$name" ]]; then
    cat >&2 <<'EOF'

Could not auto-detect an output name. Likely causes:
  - niri is not the running compositor in this session
  - the IPC socket is unreachable
  - no output is connected

Workarounds:
  - check IPC:    niri msg version
  - list outputs: niri msg outputs
  - set explicitly: OUTPUT_NAME=Virtual-1 bash scripts/niri-set-resolution.sh
EOF
    die "could not determine output name; set OUTPUT_NAME explicitly"
  fi

  printf '%s\n' "$name"
}

describe_current_mode() {
  local output_name="$1"

  # Show only the matched output block from `niri msg outputs`. Falls back to
  # the full listing if grep fails for any reason.
  niri msg outputs 2>/dev/null \
    | sed -n "/^Output \"[^\"]*\" (${output_name})\$/,/^Output \"[^\"]*\" /p" \
    | head -n 20 || niri msg outputs 2>/dev/null || true
}

main() {
  local output_name

  output_name="$(resolve_output_name)"

  log "output: $output_name"
  log "target mode: $MODE"
  log "applying (temporary — not written to config.kdl)..."

  if ! niri msg output "$output_name" mode "$MODE"; then
    die "niri rejected mode '$MODE' on '$output_name'. Check supported modes with: niri msg outputs"
  fi

  log "done."
  log "current state for '$output_name':"
  describe_current_mode "$output_name" || log "(could not fetch output state)"
}

main "$@"
