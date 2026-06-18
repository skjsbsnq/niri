#!/usr/bin/env bash
set -euo pipefail

OUT_ACPI=/tmp/mrid6-acpi
OUT_WMI=/tmp/mrid6-wmi
OWNER=${SUDO_USER:-${USER:-wwt}}

rm -rf "$OUT_ACPI" "$OUT_WMI"
mkdir -p "$OUT_ACPI" "$OUT_WMI"

cp /sys/firmware/acpi/tables/DSDT "$OUT_ACPI/" 2>/dev/null || true
cp /sys/firmware/acpi/tables/SSDT* "$OUT_ACPI/" 2>/dev/null || true

for f in /sys/bus/wmi/devices/*/bmof; do
	[ -e "$f" ] || continue
	name=$(basename "$(dirname "$f")")
	cp -L "$f" "$OUT_WMI/${name}.bmof" 2>/dev/null || true
done

if command -v iasl >/dev/null 2>&1; then
	(
		cd "$OUT_ACPI"
		iasl -e SSDT* -d DSDT SSDT* >"$OUT_ACPI/iasl.log" 2>&1 || true
	)
fi

chown -R "$OWNER":"$OWNER" "$OUT_ACPI" "$OUT_WMI" 2>/dev/null || true

echo "ACPI: $OUT_ACPI"
find "$OUT_ACPI" -maxdepth 1 -type f | sort
echo "WMI BMOF: $OUT_WMI"
find "$OUT_WMI" -maxdepth 1 -type f -printf '%p %s bytes\n' | sort
