#!/usr/bin/env bash
# Dump ACPI tables + WMI BMOF blobs for mrid6 debugging.
#
# F-03: output dirs are created with mktemp -d (mode 0700) under $TMPDIR,
# never fixed /tmp/mrid6-* names. That closes the TOCTOU window of
# `rm -rf /tmp/fixed && mkdir /tmp/fixed` against a pre-planted symlink,
# and avoids clobbering another user's dump of the same name.

set -euo pipefail

OWNER="${SUDO_USER:-${USER:-$(id -un 2>/dev/null || echo user)}}"

# Private directories; 0700. Do not fall back to a fixed name if mktemp fails.
OUT_ACPI="$(mktemp -d -t mrid6-acpi.XXXXXX)" || {
  printf 'ERROR: mktemp -d failed for ACPI outdir\n' >&2
  exit 1
}
OUT_WMI="$(mktemp -d -t mrid6-wmi.XXXXXX)" || {
  printf 'ERROR: mktemp -d failed for WMI outdir\n' >&2
  rm -rf -- "$OUT_ACPI"
  exit 1
}

# Best-effort ownership for the invoking user when run under sudo. We never
# chown paths outside the two mktemp dirs just created.
if [[ "$(id -u)" -eq 0 && -n "$OWNER" && "$OWNER" != "root" ]]; then
  chown -R "$OWNER":"$OWNER" "$OUT_ACPI" "$OUT_WMI" 2>/dev/null || true
fi

cp /sys/firmware/acpi/tables/DSDT "$OUT_ACPI/" 2>/dev/null || true
cp /sys/firmware/acpi/tables/SSDT* "$OUT_ACPI/" 2>/dev/null || true

for f in /sys/bus/wmi/devices/*/bmof; do
  [ -e "$f" ] || continue
  name=$(basename "$(dirname "$f")")
  # Refuse path components that could escape the outdir.
  case "$name" in
    *..*|*/*|*"\\"*|"") continue ;;
  esac
  cp -L "$f" "$OUT_WMI/${name}.bmof" 2>/dev/null || true
done

if command -v iasl >/dev/null 2>&1; then
  (
    cd "$OUT_ACPI"
    # iasl.log is inside the mktemp dir — no fixed /tmp path.
    iasl -e SSDT* -d DSDT SSDT* >"$OUT_ACPI/iasl.log" 2>&1 || true
  )
fi

# Re-assert ownership after copies (root-created files inside).
if [[ "$(id -u)" -eq 0 && -n "$OWNER" && "$OWNER" != "root" ]]; then
  chown -R "$OWNER":"$OWNER" "$OUT_ACPI" "$OUT_WMI" 2>/dev/null || true
fi

echo "ACPI: $OUT_ACPI"
find "$OUT_ACPI" -maxdepth 1 -type f | sort
echo "WMI BMOF: $OUT_WMI"
find "$OUT_WMI" -maxdepth 1 -type f -printf '%p %s bytes\n' | sort
echo "(dirs created by mktemp -d; delete when finished)"
