#!/usr/bin/env bash
# Verify that the two submodule copies of tahoe-glass-v1.xml match the
# authoritative tree copy at protocols/tahoe-glass-v1.xml (T-02 / M-B).
#
# The protocol is private to the Tahoe stack but is consumed by both the
# niri compositor fork and the quickshell client fork. Keeping three
# byte-identical copies in sync is a manual discipline; this script is the
# gate that makes drift fail loudly instead of silently forking the wire
# format.
#
# Exit codes:
#   0  all three copies present and sha256-identical
#   1  mismatch, missing file, or unreadable
#   2  usage error

set -euo pipefail

log() {
  printf '[protocol-sync] %s\n' "$*"
}

die() {
  printf '[protocol-sync] ERROR: %s\n' "$*" >&2
  exit 2
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-"$(cd -- "$SCRIPT_DIR/.." && pwd)"}"

AUTHORITATIVE="${TAHOE_GLASS_PROTOCOL_AUTHORITATIVE:-"$REPO_DIR/protocols/tahoe-glass-v1.xml"}"
NIRI_COPY="${TAHOE_GLASS_PROTOCOL_NIRI:-"$REPO_DIR/niri/resources/tahoe-glass-v1.xml"}"
QUICKSHELL_COPY="${TAHOE_GLASS_PROTOCOL_QUICKSHELL:-"$REPO_DIR/quickshell/src/wayland/tahoe_glass/tahoe-glass-v1.xml"}"

STRICT_MISSING=true

usage() {
  cat <<'EOF'
Usage: check-protocol-sync.sh [options]

Compare sha256 of protocols/tahoe-glass-v1.xml (authoritative) against the
niri and quickshell submodule copies.

Options:
  --allow-missing    if a submodule checkout is absent, skip it with a
                     warning instead of failing (useful on partial clones)
  -h, --help         show this help

Environment overrides:
  REPO_DIR
  TAHOE_GLASS_PROTOCOL_AUTHORITATIVE
  TAHOE_GLASS_PROTOCOL_NIRI
  TAHOE_GLASS_PROTOCOL_QUICKSHELL

Exit codes: 0 = in sync, 1 = drift/missing, 2 = usage.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --allow-missing) STRICT_MISSING=false; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

# file_sha256 <path> → prints hex digest on stdout, empty on failure
file_sha256() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    return 1
  fi
  # sha256sum (coreutils) is the portable choice on Arch; fall back to
  # shasum (macOS) and openssl so the gate still works off Arch.
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$path" | awk '{ print $1 }'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$path" | awk '{ print $1 }'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$path" | awk '{ print $NF }'
  else
    die "no sha256 tool available (need sha256sum, shasum, or openssl)"
  fi
}

relpath() {
  local path="$1"
  if [[ "$path" == "$REPO_DIR"/* ]]; then
    printf '%s\n' "${path#"$REPO_DIR"/}"
  else
    printf '%s\n' "$path"
  fi
}

log "repo: $REPO_DIR"
log "authoritative: $(relpath "$AUTHORITATIVE")"

if [[ ! -f "$AUTHORITATIVE" ]]; then
  printf 'state: missing-authoritative\n'
  printf 'detail: %s does not exist — create it from a known-good copy before comparing\n' \
    "$(relpath "$AUTHORITATIVE")"
  exit 1
fi

auth_hash="$(file_sha256 "$AUTHORITATIVE")" || die "cannot hash $AUTHORITATIVE"
printf 'authoritative-sha256: %s\n' "$auth_hash"

failures=0
compared=0

check_copy() {
  local label="$1"
  local path="$2"
  local hash

  printf '\n=== %s ===\n' "$label"
  printf 'path: %s\n' "$(relpath "$path")"

  if [[ ! -f "$path" ]]; then
    if $STRICT_MISSING; then
      printf 'state: missing\n'
      printf 'detail: copy is absent; restore it from protocols/tahoe-glass-v1.xml\n'
      failures=$((failures + 1))
    else
      printf 'state: skipped-missing\n'
      printf 'detail: --allow-missing; not compared\n'
    fi
    return 0
  fi

  if ! hash="$(file_sha256 "$path")"; then
    printf 'state: unreadable\n'
    failures=$((failures + 1))
    return 0
  fi

  compared=$((compared + 1))
  printf 'sha256: %s\n' "$hash"
  if [[ "$hash" == "$auth_hash" ]]; then
    printf 'state: match\n'
  else
    printf 'state: DRIFT\n'
    printf 'detail: differs from authoritative copy — do NOT silently pick a winner;\n'
    printf '        diff the two files, decide which side is intentional, then\n'
    printf '        propagate that version to protocols/ AND the other consumer.\n'
    printf 'action: diff -u %s %s\n' \
      "$(relpath "$AUTHORITATIVE")" "$(relpath "$path")"
    failures=$((failures + 1))
  fi
}

check_copy "niri" "$NIRI_COPY"
check_copy "quickshell" "$QUICKSHELL_COPY"

printf '\n=== summary ===\n'
printf 'compared: %s\n' "$compared"
printf 'failures: %s\n' "$failures"

if [[ "$failures" -gt 0 ]]; then
  printf 'result: DRIFT\n'
  exit 1
fi

if [[ "$compared" -eq 0 ]]; then
  # --allow-missing with both submodules absent: nothing verified.
  printf 'result: NOTHING_COMPARED\n'
  exit 1
fi

printf 'result: IN_SYNC\n'
exit 0
