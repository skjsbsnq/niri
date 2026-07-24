#!/usr/bin/env bash
# Install the Tahoe platform-profile helper system-wide so pkexec can set
# /sys/firmware/acpi/platform_profile without a password in an active session.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_HELPER="$SCRIPT_DIR/tahoe-platform-profile"
SRC_POLICY="$SCRIPT_DIR/org.tahoe.platform-profile.policy"
DST_HELPER="${TAHOE_PLATFORM_PROFILE_HELPER_DST:-/usr/local/lib/tahoe/tahoe-platform-profile}"
DST_POLICY="${TAHOE_PLATFORM_PROFILE_POLICY_DST:-/usr/share/polkit-1/actions/org.tahoe.platform-profile.policy}"

if [[ "${EUID}" -ne 0 ]]; then
  exec sudo -- "$0" "$@"
fi

install -d -m 0755 "$(dirname "$DST_HELPER")"
install -m 0755 "$SRC_HELPER" "$DST_HELPER"
install -m 0644 "$SRC_POLICY" "$DST_POLICY"

# Refresh polkit if possible (ignore failures on systems without the service).
if systemctl is-active --quiet polkit.service 2>/dev/null; then
  systemctl kill -s HUP polkit.service 2>/dev/null || true
fi

echo "Installed:"
echo "  helper: $DST_HELPER"
echo "  policy: $DST_POLICY"
echo "Active local sessions can now: pkexec $DST_HELPER set performance"
