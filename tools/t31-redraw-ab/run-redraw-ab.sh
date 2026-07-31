#!/usr/bin/env bash
# run-redraw-ab.sh — T-31 A/B: queue_redraw_all convergence measurement.
#
# Runs a nested tahoe session (niri + shell) with NIRI_LIFECYCLE_DIAG=1 and
# drives pointer motion (cursor circle / dock-row sweep) with the T-30 vpointer
# tool. The 5s lifecycle-diag delta lines are parsed for redraw_all / redraw.
#
# Usage:
#   run-redraw-ab.sh <label> [scenario ...]
#   scenario: cursor | dock  (default: cursor dock)
#   NIRI_BIN overrides the niri binary (default: ../niri/target/release/niri).
set -Eeuo pipefail

LABEL="${1:?usage: run-redraw-ab.sh <label> [scenario ...]}"
shift || true
SCENARIOS=("$@")
[[ ${#SCENARIOS[@]} -gt 0 ]] || SCENARIOS=(cursor dock)

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
NIRI_BIN="${NIRI_BIN:-"$REPO/niri/target/release/niri"}"
VP="$(cd -- "$SCRIPT_DIR/../t30-profiling" && pwd)/vpointer"
OUTDIR="$REPO/docs/refactor-roadmap-2026-07-27/acceptance/t31-ab-$LABEL"
LOGS="$OUTDIR/logs"
mkdir -p "$LOGS"

log() { printf '[t31-ab] %s\n' "$*" >&2; }

start_session() {
  local scenario="$1" logfile="$LOGS/session-$scenario.log"
  log "starting nested session ($LABEL/$scenario)"
  setsid nohup env NIRI_MODE=nested NIRI_BIN="$NIRI_BIN" \
    NIRI_FRAME_TELEMETRY=1 NIRI_LIFECYCLE_DIAG=1 \
    WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR="/run/user/$(id -u)" \
    TAHOE_POWER_PROFILE=keep \
    bash "$REPO/scripts/run-tahoe-session.sh" >"$logfile" 2>&1 &
  disown
  for _ in $(seq 1 120); do
    grep -q "listening on Wayland socket" "$logfile" 2>/dev/null && break
    sleep 0.5
  done
  local display
  display=$(grep -o 'listening on Wayland socket: wayland-[0-9]*' "$logfile" | head -1 | awk '{print $NF}')
  [[ -n "$display" ]] || { log "session did not start"; return 1; }
  # Wait for the shell (dock) when the dock scenario needs it.
  if [[ "$scenario" == dock ]]; then
    for _ in $(seq 1 90); do
      quickshell list -a 2>/dev/null | grep -q "wayland/$display" && break
      sleep 0.5
    done
  fi
  sleep 5
  echo "$display"
}

stop_session() {
  pkill -TERM -f "^$NIRI_BIN --config" 2>/dev/null || true
  sleep 2
  pkill -KILL -f "^$NIRI_BIN --config" 2>/dev/null || true
}

run_scenario() {
  local scenario="$1"
  local display
  display=$(start_session "$scenario") || return 1
  local driver
  case "$scenario" in
    cursor)
      printf 'a 800 500\n' | "$VP"
      printf 'circle 0 0 400 128 10000\n' | "$VP"
      printf 'circle 0 0 400 128 10000\n' | "$VP"
      printf 'circle 0 0 400 128 10000\n' | "$VP"
      ;;
    dock)
      printf 'a 800 940\n' | "$VP"
      printf 'line 100 940 1500 940 130 5000\n' | "$VP"
      printf 'line 1500 940 100 940 130 5000\n' | "$VP"
      printf 'line 100 940 1500 940 130 5000\n' | "$VP"
      ;;
  esac
  sleep 5
  stop_session
}

for s in "${SCENARIOS[@]}"; do
  run_scenario "$s" || true
done

# Aggregate 5s delta lines.
echo "== T-31 redraw A/B ($LABEL) =="
echo "scenario  redraw_all/5s  redraw/5s"
for s in "${SCENARIOS[@]}"; do
  awk -v s="$s" '
    /lifecycle-diag 5s delta:/ {
      for (i=1;i<=NF;i++) {
        if ($i == "redraw_all") { ra += $(i+1); }
        if ($i == "redraw") { rr += $(i+1); }
      }
      n++
    }
    END { printf "%-9s %-14s %s\n", s, (n ? ra : "n/a"), (n ? rr : "n/a") }
  ' "$LOGS/session-$s.log" | tee "$OUTDIR/summary-$s.txt"
done
