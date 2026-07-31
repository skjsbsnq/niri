#!/usr/bin/env bash
# power-sample.sh — T-30 power/load baseline sampler.
#
# The research plan asked for turbostat PkgWatt and intel_gpu_top, but this
# host is AMD Ryzen 7745HX (RAPL energy_uj is root-only here) + AMD Raphael
# iGPU (hwmon) + NVIDIA RTX 4070 (nvidia-smi); turbostat/intel_gpu_top are
# Intel-only and not installed. This sampler reads the equivalent accessible
# sources and uses a CPU-busy% proxy when RAPL is not readable:
#   cpu_pct    — whole-machine CPU busy % from /proc/stat deltas
#   core_temp  — k10temp (CPU) temperature, °C
#   igpu_w     — AMD iGPU hwmon power1_input, W
#   dgpu_w     — NVIDIA dGPU power.draw (nvidia-smi), W
#
# Usage: power-sample.sh <seconds> <interval_ms> [label]
# Emits CSV: label,elapsed_s,cpu_pct,core_temp_c,igpu_w,dgpu_w
set -Eeuo pipefail

SECONDS_ARG="${1:?usage: power-sample.sh <seconds> <interval_ms> [label]}"
INTERVAL_MS="${2:?usage: power-sample.sh <seconds> <interval_ms> [label]}"
LABEL="${3:-power}"

AMD_HWMON=""
for h in /sys/class/drm/card1/device/hwmon/hwmon*; do
  [[ -r "$h/name" ]] || continue
  [[ "$(cat "$h/name")" == amdgpu ]] && AMD_HWMON="$h" && break
done

K10TEMP=""
for h in /sys/class/hwmon/hwmon*; do
  [[ -r "$h/name" ]] || continue
  [[ "$(cat "$h/name")" == k10temp ]] && K10TEMP="$h" && break
done

read_igpu() { cat "$AMD_HWMON/power1_input"; }
read_temp() { cat "$K10TEMP/temp1_input"; }
read_dgpu() { nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits 2>/dev/null | tr -d ' '; }

cpu_total0=0; cpu_idle0=0
read -ra cpu0 < <(grep '^cpu ' /proc/stat)
for v in "${cpu0[@]:1}"; do cpu_total0=$((cpu_total0 + v)); done
cpu_idle0=$((cpu0[4] + cpu0[5]))

[[ -n "$AMD_HWMON" ]] && igpu0=$(read_igpu) || igpu0=""
[[ -n "$K10TEMP" ]] && temp0=$(read_temp) || temp0=""
dgpu0=""; dgpu0=$(read_dgpu) || true

start=$(date +%s%3N)
i=0
while :; do
  now=$(date +%s%3N)
  elapsed=$(( (now - start) / 1000 ))
  [[ $elapsed -ge "$SECONDS_ARG" ]] && break
  sleep "$(awk "BEGIN{print $INTERVAL_MS/1000}")"
  i=$((i + 1))

  read -ra cpu1 < <(grep '^cpu ' /proc/stat)
  cpu_total1=0
  for v in "${cpu1[@]:1}"; do cpu_total1=$((cpu_total1 + v)); done
  cpu_idle1=$((cpu1[4] + cpu1[5]))
  dt=$((cpu_total1 - cpu_total0))
  if [[ $dt -gt 0 ]]; then
    cpu_pct=$(awk -v idle=$((cpu_idle1 - cpu_idle0)) -v total="$dt" \
      "BEGIN{printf \"%.1f\", 100.0 * (total - idle) / total}")
  else
    cpu_pct="0.0"
  fi

  [[ -n "$AMD_HWMON" ]] && igpu1=$(read_igpu) || igpu1=""
  [[ -n "$K10TEMP" ]] && temp1=$(read_temp) || temp1=""
  dgpu1=""; dgpu1=$(read_dgpu) || true

  igpu_w=$(awk -v v="${igpu1:-0}" "BEGIN{printf \"%.2f\", v / 1e6}")
  dgpu_w=$(awk -v v="${dgpu1:-0}" "BEGIN{printf \"%.2f\", v}")
  temp_c=$(awk -v v="${temp1:-0}" "BEGIN{printf \"%.1f\", v / 1000.0}")

  printf '%s,%s,%s,%s,%s,%s\n' "$LABEL" "$elapsed" "$cpu_pct" "$temp_c" "$igpu_w" "$dgpu_w"
  cpu_total0=$cpu_total1; cpu_idle0=$cpu_idle1
  [[ -n "$AMD_HWMON" ]] && igpu0=$igpu1
  [[ -n "$K10TEMP" ]] && temp0=$temp1
  dgpu0=$dgpu1
done
