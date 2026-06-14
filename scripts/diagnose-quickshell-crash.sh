#!/usr/bin/env bash
# Diagnose the Quickshell Control Center crash (commit f2887cc).
#
# This script is safe to run with a broken shell. It does three things:
#   1. Captures the exact Quickshell load error (which QML import is fatal).
#   2. Lists every Quickshell QML module actually installed on this system,
#      so we can tell which service backend (Pipewire/Networking/Bluetooth/
#      Mpris) the distro Quickshell package was compiled without.
#   3. Writes the result to scripts/quickshell-crash-report.txt and pushes it
#      to GitHub, so the report can be read from Windows without copy/paste.
#
# It does NOT touch your repo files (no git reset, no deploy). It only writes
# the report file and commits/pushes that one file. Your current (broken)
# desktop state is preserved so the report reflects the real crash.
#
# Usage inside the VM:
#   cd /path/to/repo
#   bash scripts/diagnose-quickshell-crash.sh
#
# After it finishes, the report is at:
#   https://github.com/skjsbsnq/niri/blob/main/scripts/quickshell-crash-report.txt
#
# If you want to recover the desktop afterwards, run the recovery commands
# printed at the end of this script (or restore commit 4f0dd42).

set -Eeuo pipefail

log() { printf '[diagnose] %s\n' "$*"; }
die() { printf '[diagnose] ERROR: %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-"$(cd -- "$SCRIPT_DIR/.." && pwd)"}"
REPORT="$REPO_DIR/scripts/quickshell-crash-report.txt"
QUICKSHELL_BIN="${QUICKSHELL_BIN:-quickshell}"
TAHOE_CONFIG_DIR="${TAHOE_CONFIG_DIR:-"$HOME/.config/quickshell/tahoe"}"

command -v git >/dev/null 2>&1 || die "git not found; install it first: sudo pacman -S git"
command -v "$QUICKSHELL_BIN" >/dev/null 2>&1 || die "quickshell not found at: $QUICKSHELL_BIN"

cd "$REPO_DIR"

# We want a fresh, self-contained report. Truncate.
: > "$REPORT"

{
  echo "Quickshell crash diagnostic report"
  echo "Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo
  echo "Host: $(hostname)"
  echo "User: $(whoami)"
  echo

  echo "===== Repo state ====="
  git rev-parse HEAD 2>/dev/null || echo "(not a git repo at $REPO_DIR)"
  git -C "$REPO_DIR" log --oneline -3 2>/dev/null || true
  git -C "$REPO_DIR" status --short 2>/dev/null || true
  echo

  echo "===== quickshell binary ====="
  command -v "$QUICKSHELL_BIN"
  "$QUICKSHELL_BIN" --version 2>&1 || echo "(--version failed)"
  pacman -Q quickshell-git 2>/dev/null \
    || pacman -Q quickshell 2>/dev/null \
    || pacman -Q quickshell-xdg 2>/dev/null \
    || echo "(quickshell not installed via pacman; maybe AUR/manual build)"
  echo

  echo "===== session type / display ====="
  echo "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-<unset>}"
  echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-<unset>}"
  echo "DISPLAY=${DISPLAY:-<unset>}"
  echo

  echo "===== deployed shell.qml import lines ====="
  if [[ -f "$TAHOE_CONFIG_DIR/shell.qml" ]]; then
    grep -n "^import\|pragma ShellId\|pragma AppId" "$TAHOE_CONFIG_DIR/shell.qml" || true
  else
    echo "(deployed shell.qml not found at $TAHOE_CONFIG_DIR/shell.qml)"
  fi
  echo

  echo "===== deployed Controls.qml import lines ====="
  if [[ -f "$TAHOE_CONFIG_DIR/services/Controls.qml" ]]; then
    grep -n "^import" "$TAHOE_CONFIG_DIR/services/Controls.qml" || true
  else
    echo "(deployed Controls.qml not found)"
  fi
  echo

  echo "===== CRITICAL: live Quickshell load error ====="
  echo "Running: $QUICKSHELL_BIN -p \"$TAHOE_CONFIG_DIR\" (expect it to crash)"
  echo "---- stderr/stdout ----"
  # timeout 15s in case it hangs; do NOT let it crash this script (|| true).
  timeout 15s "$QUICKSHELL_BIN" -p "$TAHOE_CONFIG_DIR" 2>&1 || true
  echo "---- end output ----"
  echo

  echo "===== Installed Quickshell QML modules (the smoking gun) ====="
  echo "Every directory below is a module the distro quickshell can import."
  echo "If 'Pipewire' / 'Networking' / 'Bluetooth' / 'Mpris' are MISSING here,"
  echo "that is exactly why the shell crashes on load."
  echo
  found_any=0
  for dir in \
    /usr/lib/qt/qml/Quickshell \
    /usr/lib/qt6/qml/Quickshell \
    /usr/lib/qt6/qml/Quickshell.* \
    /usr/lib/qt6/qml/Quickshell/.. ; do
    true
  done
  # Find every Quickshell* QML module directory across standard Qt paths.
  for qmldir in \
    /usr/lib/qt/qml/Quickshell*/qmldir \
    /usr/lib/qt6/qml/Quickshell*/qmldir \
    /usr/lib/qt5/qml/Quickshell*/qmldir \
    "$HOME/.local/share/qml/Quickshell"*/qmldir ; do
    [[ -f "$qmldir" ]] || continue
    found_any=1
    echo "MODULE: $(dirname "$qmldir")"
    grep -E '^(module |singleton )' "$qmldir" 2>/dev/null | head -5 || true
    echo
  done
  # Also search by glob in case layout differs.
  find /usr/lib -maxdepth 4 -name 'qmldir' -path '*Quickshell*' 2>/dev/null \
    | while read -r f; do
        echo "FOUND: $f"
        grep -E '^module ' "$f" 2>/dev/null || true
      done
  if [[ "$found_any" == 0 ]]; then
    echo "(no Quickshell qmldir files found under /usr/lib; Quickshell may install elsewhere)"
  fi
  echo

  echo "===== Compiled-in service backends (strings in binary) ====="
  echo "Grepping the quickshell binary for service module names:"
  qs_path="$(command -v "$QUICKSHELL_BIN")"
  for name in Pipewire Networking Bluetooth UPower Mpris Notifications SystemTray; do
    if grep -qa "$name" "$qs_path" 2>/dev/null; then
      echo "  [present]  $name"
    else
      echo "  [MISSING]  $name"
    fi
  done
  echo

  echo "===== open-vm-tools status (for the copy/paste issue) ====="
  pacman -Q open-vm-tools 2>/dev/null || echo "open-vm-tools: NOT installed"
  systemctl is-active vmtoolsd 2>/dev/null || echo "vmtoolsd: not active"
  pgrep -a vmware-user 2>/dev/null || echo "vmware-user: NOT running (this is why copy/paste fails under niri)"
  echo

  echo "===== diagnostic complete ====="
} >> "$REPORT" 2>&1

log "report written to: $REPORT"
echo
echo "----- report preview (first 60 lines) -----"
head -n 60 "$REPORT" 2>/dev/null || true
echo "----- end preview -----"

# Commit and push the single report file. Do not touch anything else.
if git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log "committing and pushing report to GitHub"
  git -C "$REPO_DIR" add "$REPORT"
  git -C "$REPO_DIR" commit -m "Add Quickshell crash diagnostic report" \
    || log "nothing new to commit (report unchanged)"
  git -C "$REPO_DIR" push origin main 2>&1 \
    || die "push failed; check network/credentials, then retry this script"
  log "pushed. Read the report at:"
  log "  https://github.com/skjsbsnq/niri/blob/main/scripts/quickshell-crash-report.txt"
else
  log "$REPO_DIR is not a git repo; skipping commit/push. Copy $REPORT out manually."
fi

cat <<'EOF'

[diagnose] ------------------------------------------------------------
[diagnose] DONE. To recover your desktop NOW (optional), run:
[diagnose]
[diagnose]   cd REPO_DIR && git reset --hard 4f0dd42 && bash scripts/arch-update.sh
[diagnose]
[diagnose] then re-login to niri. (4f0dd42 = last good commit before the
[diagnose] Control Center rewrite f2887cc that is crashing now.)
[diagnose] ------------------------------------------------------------
EOF
