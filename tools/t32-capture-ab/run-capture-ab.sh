#!/usr/bin/env bash
# run-capture-ab.sh — T-32 A/B: glass capture frequency (note_fb_effect_capture).
#
# Runs nested tahoe sessions with NIRI_LIFECYCLE_DIAG=1 and drives
# dock-wave / island-expand / overview scenarios; reports fb_capture deltas
# per 5s window (the T-32 acceptance metric).
#
# Usage:
#   run-capture-ab.sh <label> [scenario ...]
#   scenario: dock | island | overview   (default: dock island overview)
#   NIRI_BIN overrides the niri binary.
set -Eeuo pipefail

LABEL="${1:?usage: run-capture-ab.sh <label> [scenario ...]}"
shift || true
SCENARIOS=("$@")
[[ ${#SCENARIOS[@]} -gt 0 ]] || SCENARIOS=(dock island overview)

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
NIRI_BIN="${NIRI_BIN:-"$REPO/niri/target/release/niri"}"
VP="$(cd -- "$SCRIPT_DIR/../t30-profiling" && pwd)/vpointer"
OUTDIR="$REPO/docs/refactor-roadmap-2026-07-27/acceptance/t32-ab-$LABEL"
LOGS="$OUTDIR/logs"
mkdir -p "$LOGS"

log() { printf '[t32-ab] %s\n' "$*" >&2; }

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
  for _ in $(seq 1 90); do
    quickshell list -a 2>/dev/null | grep -q "wayland/$display" && break
    sleep 0.5
  done
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
  export WAYLAND_DISPLAY="$display"
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  local qipc=(quickshell ipc -p "$HOME/.config/quickshell/tahoe" call tahoe)
  case "$scenario" in
    dock)
      printf 'a 800 940\n' | "$VP"
      # Slow sweep: ~1.2px/frame at 60fps — sub-cell band motion, the regime
      # where 8px quantization collapses re-captures (fast sweeps cross cells
      # every frame and show little difference by design).
      for r in 1 2 3; do
        printf 'line 100 940 800 940 300 10000\n' | "$VP"
        printf 'line 800 940 100 940 300 10000\n' | "$VP"
      done
      ;;
    island)
      for i in $(seq 1 6); do
        timeout 10 "${qipc[@]}" dynamicIslandShowNotification "Profiling" "island $i" || true
        sleep 1.5
      done
      ;;
    overview)
      for i in $(seq 1 6); do
        timeout 10 "${qipc[@]}" toggleWindowOverview || true
        sleep 1.2
      done
      ;;
  esac
  sleep 5
  stop_session
}

for s in "${SCENARIOS[@]}"; do
  run_scenario "$s" || true
done

echo "== T-32 glass capture A/B ($LABEL) =="
echo "scenario  fb_capture/5s-sum  windows"
for s in "${SCENARIOS[@]}"; do
  awk -v s="$s" '
    /lifecycle-diag 5s delta:/ {
      for (i=1;i<=NF;i++) {
        if ($i == "fb_capture") { v = $(i+1); fc += v; n++ }
        if ($i == "blur") { v = $(i+1); br += v }
      }
    }
    END { printf "%-9s %-18s %d\n", s, (n ? fc : "n/a"), n }
  ' "$LOGS/session-$s.log" | tee "$OUTDIR/summary-$s.txt"
done
