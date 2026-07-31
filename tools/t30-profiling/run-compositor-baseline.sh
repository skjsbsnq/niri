#!/usr/bin/env bash
# run-compositor-baseline.sh — T-30 compositor-side baseline capture driver.
#
# For each scenario it starts a fresh nested niri session (tracy-enabled build,
# NIRI_FRAME_TELEMETRY=1, NIRI_LIFECYCLE_DIAG=1), waits for the shell to
# settle, then records a Tracy capture and (for idle runs) a power sample.
# Restarting per scenario gives each capture a fresh Tracy client connection
# (the tracy-client embedded in the niri fork only accepts one server per
# process lifetime) and per-scenario telemetry counters.
#
# Usage:
#   run-compositor-baseline.sh <outdir> [scenario ...]
#   scenarios: A-idle-1 A-idle-2 A-idle-3 A-cursor B-dock C-island D-overview
set -Eeuo pipefail

OUTDIR="${1:?usage: run-compositor-baseline.sh <outdir> [scenario ...]}"
shift || true
SCENARIOS=("$@")
[[ ${#SCENARIOS[@]} -gt 0 ]] || SCENARIOS=(A-idle-1 A-idle-2 A-idle-3 A-cursor B-dock C-island D-overview)

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="${REPO:-"$(cd -- "$SCRIPT_DIR/../.." && pwd)"}"
NIRI_BIN="${NIRI_BIN:-"$REPO/niri/target/release/niri"}"
TRACY_CAPTURE="${TRACY_CAPTURE:-/tmp/tracy-build-0131/tracy-capture}"
CAPTURES_DIR="$OUTDIR/captures"
LOGS_DIR="$OUTDIR/logs"
mkdir -p "$CAPTURES_DIR" "$LOGS_DIR"

log() { printf '[t30-baseline] %s\n' "$*" >&2; }

# The niri tracy client's listener fd is not CLOEXEC and leaks into the
# quickshell -> udevadm-monitor child chain of nested sessions. After the
# owning niri exits, the leftover holder keeps port 8086 bound and the next
# session's tracy client cannot bind. Kill any process still holding the
# LISTEN socket on 8086 (only leaked holders can match: real clients do not
# hold the listener of a dead niri).
free_tracy_port() {
  local ino p fd link round
  for round in 1 2 3 4 5; do
    ino=$(ss -tnle 2>/dev/null | awk '/:8086 / && $1=="LISTEN" { for (i=1;i<=NF;i++) if ($i ~ /^ino:/) { split($i,a,":"); print a[2] } }' | head -1)
    [[ -n "$ino" ]] || return 0
    for p in /proc/[0-9]*; do
      for fd in "$p"/fd/*; do
        link=$(readlink "$fd" 2>/dev/null) || continue
        if [[ "$link" == "socket:[$ino]" ]]; then
          log "killing pid ${p#/proc/} holding leaked tracy listener (ino $ino)"
          kill -TERM "${p#/proc/}" 2>/dev/null || true
        fi
      done
    done
    sleep 1
  done
  log "port 8086 still held after cleanup rounds"
}

# Starts a fresh nested session and waits until it is ready. Prints a single
# state line "display niri_pid ipc_socket" on stdout; all diagnostics go to
# stderr so callers can capture stdout into a state file.
restart_nested() {
  local scenario="$1" niri_pid wayland_sock display=""
  log "stopping previous nested niri"
  pkill -TERM -f "^$NIRI_BIN --config" 2>/dev/null || true
  for _ in $(seq 1 40); do
    pgrep -f "^$NIRI_BIN --config" >/dev/null 2>&1 || break
    sleep 0.5
  done
  if pgrep -f "^$NIRI_BIN --config" >/dev/null 2>&1; then
    log "nested niri did not stop in time"
    return 1
  fi
  sleep 1

  free_tracy_port

  log "starting nested niri for $scenario"
  setsid nohup env NIRI_MODE=nested NIRI_BIN="$NIRI_BIN" \
    NIRI_FRAME_TELEMETRY=1 NIRI_LIFECYCLE_DIAG=1 \
    WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR="/run/user/$(id -u)" \
    TAHOE_POWER_PROFILE=keep \
    bash "$REPO/scripts/run-tahoe-session.sh" \
    >"$LOGS_DIR/session-$scenario.log" 2>&1 &
  disown

  for _ in $(seq 1 90); do
    display=$(grep -o 'listening on Wayland socket: wayland-[0-9]*' \
      "$LOGS_DIR/session-$scenario.log" 2>/dev/null | head -1 | awk '{print $NF}')
    [[ -n "$display" ]] && break
    sleep 0.5
  done
  if [[ -z "$display" ]]; then
    log "nested niri did not report a Wayland socket"
    return 1
  fi

  for _ in $(seq 1 90); do
    quickshell list -a 2>/dev/null | grep -q "wayland/$display" && break
    sleep 0.5
  done
  sleep 5  # let the shell settle past startup animations

  niri_pid=$(pgrep -f "^$NIRI_BIN --config" | head -1)
  wayland_sock=$(grep -o '/run/user/[0-9]*/niri\.[^ ]*\.sock' \
    "$LOGS_DIR/session-$scenario.log" 2>/dev/null | head -1)

  # The tracy client must own the 8086 listener; a leaked fd from a previous
  # session would otherwise leave the capture tool connected to a zombie.
  local lino owned="no" fd link
  lino=$(ss -tnle 2>/dev/null | awk '/:8086 / && $1=="LISTEN" { for (i=1;i<=NF;i++) if ($i ~ /^ino:/) { split($i,a,":"); print a[2] } }' | head -1)
  if [[ -n "$lino" && -n "$niri_pid" ]]; then
    for fd in /proc/$niri_pid/fd/*; do
      link=$(readlink "$fd" 2>/dev/null) || continue
      [[ "$link" == "socket:[$lino]" ]] && owned="yes" && break
    done
  fi
  if [[ "$owned" != "yes" ]]; then
    log "tracy listener on 8086 is not owned by the new niri (ino=$lino); aborting scenario"
    pkill -TERM -f "^$NIRI_BIN --config" 2>/dev/null || true
    return 1
  fi

  log "nested ready: display=$display niri_pid=$niri_pid ipc=$wayland_sock"
  printf '%s %s %s\n' "$display" "$niri_pid" "$wayland_sock"
}

run_scenario() {
  local scenario="$1" display="" niri_pid wayland_sock state_file
  state_file="$LOGS_DIR/state-$scenario.txt"
  if ! restart_nested "$scenario" >"$state_file"; then
    log "restart failed for $scenario; skipping"
    return 1
  fi
  read -r display niri_pid wayland_sock <"$state_file"
  [[ -n "$display" ]] || { log "no nested display for $scenario"; return 1; }

  case "$scenario" in
    A-idle-*)
      local cap_s=68
      "$TRACY_CAPTURE" -o "$CAPTURES_DIR/$scenario.tracy" -f -s "$cap_s" \
        >"$LOGS_DIR/capture-$scenario.log" 2>&1 &
      local cpid=$!
      "$SCRIPT_DIR/power-sample.sh" 60 1000 "$scenario" \
        >"$LOGS_DIR/power-$scenario.csv" &
      local ppid=$!
      wait $cpid || true
      wait $ppid || true
      ;;
    *)
      local cap_s=45 driver_scenario
      "$TRACY_CAPTURE" -o "$CAPTURES_DIR/$scenario.tracy" -f -s "$cap_s" \
        >"$LOGS_DIR/capture-$scenario.log" 2>&1 &
      local cpid=$!
      case "$scenario" in
        A-cursor) driver_scenario=cursor ;;
        B-dock) driver_scenario=dock ;;
        C-island) driver_scenario=island ;;
        D-overview) driver_scenario=overview ;;
      esac
      bash "$SCRIPT_DIR/scenario-driver.sh" "$driver_scenario" "$display" \
        >"$LOGS_DIR/scenario-$scenario.log" 2>&1
      wait $cpid || true
      ;;
  esac
  log "finished $scenario: $(grep -E 'Trace size|Zones' "$LOGS_DIR/capture-$scenario.log" | tr '\n' ' ')"
}

for s in "${SCENARIOS[@]}"; do
  attempt=0; ok=0
  while [[ $attempt -lt 3 && $ok -eq 0 ]]; do
    attempt=$((attempt + 1))
    # A leftover capture from a previous scenario must not race the new
    # session's tracy client (it would consume the first connection).
    pkill -TERM -f '^/tmp/tracy-build-0131/tracy-capture' 2>/dev/null || true
    sleep 1
    run_scenario "$s" || true
    if grep -q 'Saving trace... done!' "$LOGS_DIR/capture-$s.log" 2>/dev/null; then
      ok=1
      log "scenario $s ok on attempt $attempt"
    else
      log "scenario $s failed on attempt $attempt (no saved trace)"
    fi
  done
  [[ $ok -eq 1 ]] || { log "scenario $s FAILED after 3 attempts"; FAILED=1; }
done

log "all scenarios done"
[[ -z "${FAILED:-}" ]] || exit 1
