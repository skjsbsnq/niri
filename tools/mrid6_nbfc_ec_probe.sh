#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run as root: sudo bash $0" >&2
  exit 1
fi

EC_IO=${EC_IO:-/sys/kernel/debug/ec/ec0/io}
if [[ ! -r "$EC_IO" ]]; then
  echo "Cannot read $EC_IO. Is ec_sys loaded with write_support=1?" >&2
  exit 1
fi

OUT=${OUT:-/tmp/mrid6-nbfc-probe-$(date +%Y%m%d-%H%M%S)}
mkdir -p "$OUT"

ORIGINAL_CONFIG=""
if [[ -r /etc/nbfc/nbfc.json ]]; then
  ORIGINAL_CONFIG=$(sed -n 's/.*"SelectedConfigId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' /etc/nbfc/nbfc.json | head -n1)
fi

restore_original() {
  if [[ -n "$ORIGINAL_CONFIG" ]]; then
    echo
    echo "Restoring original NBFC config: $ORIGINAL_CONFIG"
    nbfc config -a "$ORIGINAL_CONFIG" >/dev/null 2>&1 || true
  fi
}
trap restore_original EXIT

write_config_fasp95() {
  local path=$1
  cat >"$path" <<'JSON'
{
 "LegacyTemperatureThresholdsBehaviour": true,
 "NotebookModel": "MECHREVO Jiaolong Series MRID6 FASP95 probe",
 "Author": "local MRID6 NBFC EC probe",
 "EcPollInterval": 1000,
 "ReadWriteWords": false,
 "CriticalTemperature": 120,
 "FanConfigurations": [
  {
   "ReadRegister": 95,
   "WriteRegister": 95,
   "MinSpeedValue": 0,
   "MaxSpeedValue": 100,
   "IndependentReadMinMaxValues": false,
   "MinSpeedValueRead": 0,
   "MaxSpeedValueRead": 100,
   "ResetRequired": false,
   "FanSpeedResetValue": 0,
   "FanDisplayName": "Fan FASP 0x5f",
   "TemperatureThresholds": [
    { "UpThreshold": 40, "DownThreshold": 0, "FanSpeed": 0.0 },
    { "UpThreshold": 50, "DownThreshold": 41, "FanSpeed": 20.0 },
    { "UpThreshold": 60, "DownThreshold": 51, "FanSpeed": 35.0 },
    { "UpThreshold": 70, "DownThreshold": 61, "FanSpeed": 55.0 },
    { "UpThreshold": 119, "DownThreshold": 71, "FanSpeed": 100.0 }
   ]
  }
 ]
}
JSON
}

write_config_gk62_min0() {
  local path=$1
  cat >"$path" <<'JSON'
{
 "LegacyTemperatureThresholdsBehaviour": true,
 "NotebookModel": "MECHREVO Jiaolong Series MRID6 GK62 min0 probe",
 "Author": "local MRID6 NBFC EC probe",
 "EcPollInterval": 1000,
 "ReadWriteWords": false,
 "CriticalTemperature": 120,
 "FanConfigurations": [
  {
   "ReadRegister": 62,
   "WriteRegister": 62,
   "MinSpeedValue": 0,
   "MaxSpeedValue": 78,
   "IndependentReadMinMaxValues": false,
   "MinSpeedValueRead": 0,
   "MaxSpeedValueRead": 0,
   "ResetRequired": false,
   "FanSpeedResetValue": 0,
   "FanDisplayName": "Fan 0x3e min0",
   "TemperatureThresholds": [
    { "UpThreshold": 40, "DownThreshold": 0, "FanSpeed": 0.0 },
    { "UpThreshold": 45, "DownThreshold": 41, "FanSpeed": 6.5 },
    { "UpThreshold": 50, "DownThreshold": 46, "FanSpeed": 10.0 },
    { "UpThreshold": 60, "DownThreshold": 51, "FanSpeed": 30.0 },
    { "UpThreshold": 65, "DownThreshold": 61, "FanSpeed": 50.0 },
    { "UpThreshold": 119, "DownThreshold": 66, "FanSpeed": 100.0 }
   ]
  }
 ]
}
JSON
}

write_config_gk62_stockrange() {
  local path=$1
  cat >"$path" <<'JSON'
{
 "LegacyTemperatureThresholdsBehaviour": true,
 "NotebookModel": "MECHREVO Jiaolong Series MRID6 GK62 stock-range probe",
 "Author": "local MRID6 NBFC EC probe",
 "EcPollInterval": 1000,
 "ReadWriteWords": false,
 "CriticalTemperature": 120,
 "FanConfigurations": [
  {
   "ReadRegister": 62,
   "WriteRegister": 62,
   "MinSpeedValue": 31,
   "MaxSpeedValue": 78,
   "IndependentReadMinMaxValues": false,
   "MinSpeedValueRead": 0,
   "MaxSpeedValueRead": 0,
   "ResetRequired": false,
   "FanSpeedResetValue": 0,
   "FanDisplayName": "Fan 0x3e stock range",
   "TemperatureThresholds": [
    { "UpThreshold": 40, "DownThreshold": 0, "FanSpeed": 0.0 },
    { "UpThreshold": 45, "DownThreshold": 41, "FanSpeed": 6.5 },
    { "UpThreshold": 50, "DownThreshold": 46, "FanSpeed": 10.0 },
    { "UpThreshold": 60, "DownThreshold": 51, "FanSpeed": 30.0 },
    { "UpThreshold": 65, "DownThreshold": 61, "FanSpeed": 50.0 },
    { "UpThreshold": 119, "DownThreshold": 66, "FanSpeed": 100.0 }
   ]
  }
 ]
}
JSON
}

dump_ec() {
  local name=$1
  dd if="$EC_IO" of="$OUT/$name.bin" bs=256 count=1 status=none
  od -An -tx1 -v "$OUT/$name.bin" >"$OUT/$name.hex"
}

byte_at() {
  local file=$1
  local off=$2
  od -An -tu1 -j "$off" -N 1 "$file" | tr -d ' '
}

hex_at() {
  local file=$1
  local off=$2
  od -An -tx1 -j "$off" -N 1 "$file" | tr -d ' '
}

rpm_pair() {
  local file=$1
  local f1h f1l f2h f2l f1 f2
  f1h=$(byte_at "$file" 0x9b)
  f1l=$(byte_at "$file" 0x9c)
  f2h=$(byte_at "$file" 0x9d)
  f2l=$(byte_at "$file" 0x9e)
  f1=$((f1h * 256 + f1l))
  f2=$((f2h * 256 + f2l))
  printf 'F1=%d F2=%d raw_9b_9e=%s %s %s %s' \
    "$f1" "$f2" \
    "$(hex_at "$file" 0x9b)" "$(hex_at "$file" 0x9c)" \
    "$(hex_at "$file" 0x9d)" "$(hex_at "$file" 0x9e)"
}

diff_ec() {
  local prev=$1
  local curr=$2
  python - "$prev" "$curr" <<'PY'
import sys
prev = open(sys.argv[1], 'rb').read()
curr = open(sys.argv[2], 'rb').read()
changes = []
for i, (a, b) in enumerate(zip(prev, curr)):
    if a != b:
        changes.append(f"0x{i:02x}:{a:02x}->{b:02x}")
print(" ".join(changes) if changes else "(no byte changes)")
PY
}

run_one_config() {
  local label=$1
  local config=$2
  echo
  echo "===== $label ====="
  echo "config: $config"
  nbfc config -a "$config"
  sleep 2
  nbfc status -a | sed -n '1,80p' | tee "$OUT/${label}_status_initial.txt"

  local prev=""
  for speed in 0 30 70 100; do
    echo
    echo "--- $label speed=$speed ---"
    nbfc set -s "$speed"
    sleep 3
    local name="${label}_s${speed}"
    dump_ec "$name"
    nbfc status -a >"$OUT/${name}_status.txt" 2>&1 || true
    printf '%s\n' "$(rpm_pair "$OUT/$name.bin")"
    printf 'key regs: 0x3e=%s 0x5f=%s 0xe2=%s 0xe3=%s 0xe4=%s 0xf0=%s 0xf6=%s 0xf7=%s 0xf8=%s\n' \
      "$(hex_at "$OUT/$name.bin" 0x3e)" "$(hex_at "$OUT/$name.bin" 0x5f)" \
      "$(hex_at "$OUT/$name.bin" 0xe2)" "$(hex_at "$OUT/$name.bin" 0xe3)" \
      "$(hex_at "$OUT/$name.bin" 0xe4)" "$(hex_at "$OUT/$name.bin" 0xf0)" \
      "$(hex_at "$OUT/$name.bin" 0xf6)" "$(hex_at "$OUT/$name.bin" 0xf7)" \
      "$(hex_at "$OUT/$name.bin" 0xf8)"
    if [[ -n "$prev" ]]; then
      printf 'changed from previous speed: '
      diff_ec "$prev" "$OUT/$name.bin"
    fi
    prev="$OUT/$name.bin"
  done
}

FASP="$OUT/mrid6_fasp95.json"
GKMIN="$OUT/mrid6_gk62_min0.json"
GKSTOCK="$OUT/mrid6_gk62_stockrange.json"
write_config_fasp95 "$FASP"
write_config_gk62_min0 "$GKMIN"
write_config_gk62_stockrange "$GKSTOCK"

echo "Output directory: $OUT"
echo "Original NBFC config: ${ORIGINAL_CONFIG:-unknown}"

dump_ec baseline
printf 'baseline %s\n' "$(rpm_pair "$OUT/baseline.bin")"

run_one_config fasp95 "$FASP"
run_one_config gk62_min0 "$GKMIN"
run_one_config gk62_stockrange "$GKSTOCK"

echo
echo "Done. Output directory: $OUT"
