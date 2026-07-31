#!/usr/bin/env bash
# scenario-driver.sh — run one T-30 profiling scenario against a nested session.
#
# Usage:
#   scenario-driver.sh <scenario> <wayland-display>
#
# Scenarios (research-report.md:175):
#   idle         60s of no input (run 3x for power medians)
#   cursor       cursor circle, R=400 logical px, 3 rounds x 10s
#   dock         10s Dock wave sweep across the dock row
#   island       Island expand x10 via quickshell IPC
#   overview     Overview in/out x10 via quickshell IPC
#
# IPC calls target the quickshell instance on the given display (the nested
# session's own instance); the TAHOE config path is fixed to the live profile.
set -Eeuo pipefail

SCENARIO="${1:?scenario required}"
NESTED_DISPLAY="${2:?nested wayland display required (e.g. wayland-2)}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export WAYLAND_DISPLAY="$NESTED_DISPLAY"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

qipc() { quickshell ipc -p "$HOME/.config/quickshell/tahoe" call tahoe "$@"; }

case "$SCENARIO" in
  idle)
    sleep 60
    ;;
  cursor)
    # Move to logical center, then 3 rounds of 10s circle (R=400).
    printf 'a 800 500\n' | "$SCRIPT_DIR/vpointer"
    for r in 1 2 3; do
      printf 'circle 0 0 400 128 10000\n' | "$SCRIPT_DIR/vpointer"
    done
    ;;
  dock)
    # Dock sits at the bottom edge of the nested output. Sweep the row at
    # y = output_height - 60 (logical), 130 steps per pass, 5s per pass.
    H="${NESTED_H:-1000}"
    Y=$((H - 60))
    printf 'a 800 %s\n' "$Y" | "$SCRIPT_DIR/vpointer"
    printf 'line 100 %s 1500 %s 130 5000\n' "$Y" "$Y" | "$SCRIPT_DIR/vpointer"
    printf 'line 1500 %s 100 %s 130 5000\n' "$Y" "$Y" | "$SCRIPT_DIR/vpointer"
    ;;
  island)
    for i in $(seq 1 10); do
      qipc dynamicIslandShowNotification "Profiling" "island $i" || true
      sleep 1.5
    done
    ;;
  overview)
    for i in $(seq 1 10); do
      qipc toggleWindowOverview || true
      sleep 1.2
    done
    ;;
  *)
    echo "unknown scenario: $SCENARIO" >&2
    exit 1
    ;;
esac
