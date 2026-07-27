#!/usr/bin/env bash
# Diagnose the Quickshell Control Center crash (commit f2887cc).
#
# This script is safe to run with a broken shell. It does three things:
#   1. Captures the exact Quickshell load error (which QML import is fatal).
#   2. Lists every Quickshell QML module actually installed on this system,
#      so we can tell which service backend (Pipewire/Networking/Bluetooth/
#      Mpris) the distro Quickshell package was compiled without.
#   3. Writes a *desensitized* report to scripts/quickshell-crash-report.txt.
#
# It does NOT push anything by default (F-02). Commit/push only happen after
# an explicit interactive confirmation, and even then only the single report
# file is staged. Your current (broken) desktop state is preserved so the
# report reflects the real crash.
#
# Usage inside the VM:
#   cd /path/to/repo
#   bash scripts/diagnose-quickshell-crash.sh
#
# Non-interactive (never commit/push; just write the local report):
#   DIAGNOSE_NO_PUSH=1 bash scripts/diagnose-quickshell-crash.sh
#
# After it finishes, the report is local:
#   scripts/quickshell-crash-report.txt
# Optionally confirm the interactive prompt to commit+push that one file.
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
# DIAGNOSE_NO_PUSH=1 forces local-only (default-safe for CI / non-TTY).
NO_PUSH="${DIAGNOSE_NO_PUSH:-0}"

# redacted_path <path> — collapse $HOME / $REPO_DIR so the report never
# ships a concrete username or absolute machine path.
redacted_path() {
  local p="${1:-}"
  # Longest match first: repo is usually under home.
  if [[ -n "${REPO_DIR:-}" && "$p" == "$REPO_DIR"* ]]; then
    p='$REPO'"${p#"$REPO_DIR"}"
  elif [[ -n "${HOME:-}" && "$p" == "$HOME"* ]]; then
    p='$HOME'"${p#"$HOME"}"
  else
    # Generic /home/<user>/... for paths outside this checkout.
    p="$(printf '%s' "$p" | sed -E 's|/home/[^/]+|/home/<user>|g')"
  fi
  printf '%s' "$p"
}

# redacted_text — scrub multi-line blobs (quickshell stderr can embed
# absolute paths). Pure bash substitution so paths with sed metacharacters
# cannot break the scrubber (F-02 must not fail open by printing raw text
# plus a sed error).
redacted_text() {
  local line u
  u="$(whoami 2>/dev/null || true)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -n "${REPO_DIR:-}" ]]; then
      line="${line//"$REPO_DIR"/\$REPO}"
    fi
    if [[ -n "${HOME:-}" ]]; then
      line="${line//"$HOME"/\$HOME}"
    fi
    # Any remaining /home/<name> prefix (other users, odd layouts).
    if [[ "$line" == */home/* ]]; then
      line="$(printf '%s\n' "$line" | sed -E 's|/home/[^/[:space:]]+|/home/<user>|g')"
    fi
    if [[ -n "$u" && "$line" == *"$u"* ]]; then
      line="${line//"$u"/<user>}"
    fi
    printf '%s\n' "$line"
  done
}

command -v git >/dev/null 2>&1 || die "git not found; install it first: sudo pacman -S git"
command -v "$QUICKSHELL_BIN" >/dev/null 2>&1 || die "quickshell not found at: $QUICKSHELL_BIN"

cd "$REPO_DIR"

# Fresh report file. Refuse to follow a pre-planted symlink at the report
# path (even though it lives in-repo, a dirty worktree could replace it).
# Write via O_NOFOLLOW-equivalent: reject symlinks, then open with clobber
# only on a regular file or create anew.
if [[ -L "$REPORT" ]]; then
  die "refusing to write report through symlink at $REPORT"
fi
if [[ -e "$REPORT" && ! -f "$REPORT" ]]; then
  die "refusing to clobber non-regular report path $REPORT"
fi
# Use a temp file + rename so a racing symlink plant between the checks
# and the write cannot redirect our content (rename over a symlink replaces
# the link entry in the directory, it does not follow it).
_report_tmp="$(mktemp -p "$(dirname -- "$REPORT")" ".quickshell-crash-report.XXXXXX")" \
  || die "mktemp failed for report staging file"
# shellcheck disable=SC2064
trap 'rm -f -- "$_report_tmp" 2>/dev/null || true' EXIT

{
  echo "Quickshell crash diagnostic report"
  echo "Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo
  # F-02: do NOT emit raw hostname / username. A coarse host class is enough
  # to tell "VM vs bare metal" without pinning the machine.
  _virt="$(systemd-detect-virt 2>/dev/null || true)"
  if [[ -z "$_virt" || "$_virt" == "none" ]]; then
    if [[ -d /proc/vz ]]; then
      _virt=container
    elif grep -q hypervisor /proc/cpuinfo 2>/dev/null; then
      _virt=vm
    else
      _virt=bare-metal
    fi
  fi
  echo "Host-class: $_virt"
  unset _virt
  echo "User: <redacted>"
  echo "Repo: \$REPO  (absolute path withheld)"
  echo "Config: $(redacted_path "$TAHOE_CONFIG_DIR")"
  echo

  echo "===== Repo state ====="
  git rev-parse HEAD 2>/dev/null || echo "(not a git repo at \$REPO)"
  git -C "$REPO_DIR" log --oneline -3 2>/dev/null || true
  # status paths can embed usernames if files live under $HOME; scrub.
  git -C "$REPO_DIR" status --short 2>/dev/null | redacted_text || true
  echo

  echo "===== quickshell binary ====="
  redacted_path "$(command -v "$QUICKSHELL_BIN")"
  echo
  "$QUICKSHELL_BIN" --version 2>&1 | redacted_text || echo "(--version failed)"
  pacman -Q quickshell-git 2>/dev/null \
    || pacman -Q quickshell 2>/dev/null \
    || pacman -Q quickshell-xdg 2>/dev/null \
    || echo "(quickshell not installed via pacman; maybe AUR/manual build)"
  echo

  echo "===== session type / display ====="
  # Keep the *names* of the display sockets (needed to debug session wiring)
  # but do not echo $USER-derived socket directories beyond the var itself.
  echo "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-<unset>}"
  echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-<unset>}"
  echo "DISPLAY=${DISPLAY:-<unset>}"
  echo

  echo "===== deployed shell.qml import lines ====="
  if [[ -f "$TAHOE_CONFIG_DIR/shell.qml" ]]; then
    grep -n "^import\|pragma ShellId\|pragma AppId" "$TAHOE_CONFIG_DIR/shell.qml" || true
  else
    echo "(deployed shell.qml not found at $(redacted_path "$TAHOE_CONFIG_DIR/shell.qml"))"
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
  echo "Running: $QUICKSHELL_BIN -p \"\$CONFIG\" (expect it to crash)"
  echo "---- stderr/stdout ----"
  # timeout 15s in case it hangs; do NOT let it crash this script (|| true).
  # Scrub absolute paths out of the crash text before they hit the report.
  timeout 15s "$QUICKSHELL_BIN" -p "$TAHOE_CONFIG_DIR" 2>&1 | redacted_text || true
  echo "---- end output ----"
  echo

  echo "===== Installed Quickshell QML modules (the smoking gun) ====="
  echo "Every directory below is a module the distro quickshell can import."
  echo "If 'Pipewire' / 'Networking' / 'Bluetooth' / 'Mpris' are MISSING here,"
  echo "that is exactly why the shell crashes on load."
  echo
  found_any=0
  # Find every Quickshell* QML module directory across standard Qt paths.
  for qmldir in \
    /usr/lib/qt/qml/Quickshell*/qmldir \
    /usr/lib/qt6/qml/Quickshell*/qmldir \
    /usr/lib/qt5/qml/Quickshell*/qmldir \
    "$HOME/.local/share/qml/Quickshell"*/qmldir ; do
    [[ -f "$qmldir" ]] || continue
    found_any=1
    echo "MODULE: $(redacted_path "$(dirname "$qmldir")")"
    grep -E '^(module |singleton )' "$qmldir" 2>/dev/null | head -5 || true
    echo
  done
  # Also search by glob in case layout differs. System paths only — no $HOME.
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
  # pgrep -a can print full argv with home paths; scrub.
  pgrep -a vmware-user 2>/dev/null | redacted_text \
    || echo "vmware-user: NOT running (this is why copy/paste fails under niri)"
  echo

  echo "===== diagnostic complete ====="
} >> "$_report_tmp" 2>&1

# Atomically publish the staged report into place (replaces a symlink entry
# rather than following it).
mv -f -- "$_report_tmp" "$REPORT"
trap - EXIT
unset _report_tmp

log "report written to: $REPORT"
echo
echo "----- report preview (first 60 lines) -----"
head -n 60 "$REPORT" 2>/dev/null || true
echo "----- end preview -----"

# ── F-02: never auto-push. Interactive confirm only, and only the report. ──
want_publish=false
if [[ "$NO_PUSH" == "1" || "$NO_PUSH" == "true" ]]; then
  log "DIAGNOSE_NO_PUSH set; leaving report local-only at $REPORT"
elif [[ ! -t 0 ]]; then
  log "stdin is not a TTY; refusing to commit/push without interactive confirm."
  log "Re-run from a terminal, or copy $REPORT out manually."
elif git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  cat <<EOF

[diagnose] The report is local only so far:
[diagnose]   $REPORT
[diagnose]
[diagnose] It has been scrubbed of hostname, username, and absolute home/repo
[diagnose] paths, but it still contains package versions, module lists, and
[diagnose] crash text. Publishing the single report commit to origin is OPTIONAL.
[diagnose]
EOF
  # Read from the controlling terminal even if stdout is piped.
  if [[ -r /dev/tty ]]; then
    printf '[diagnose] Commit AND push ONLY this report file to origin HEAD? [y/N] ' >/dev/tty
    read -r reply </dev/tty || reply=
  else
    printf '[diagnose] Commit AND push ONLY this report file to origin HEAD? [y/N] '
    read -r reply || reply=
  fi
  case "${reply:-}" in
    y|Y|yes|YES) want_publish=true ;;
    *) log "skipped publish; report stays local." ;;
  esac
else
  log "\$REPO is not a git repo; skipping commit/push. Copy $REPORT out manually."
fi

if $want_publish; then
  log "staging and pushing ONLY the report file (nothing else)"
  # Snapshot HEAD so a no-op commit cannot accidentally push unrelated
  # local commits that were already sitting on this branch.
  pre_push_head="$(git -C "$REPO_DIR" rev-parse HEAD)"
  git -C "$REPO_DIR" add -- "$REPORT"
  # Guard: refuse if anything other than the report is staged.
  staged="$(git -C "$REPO_DIR" diff --cached --name-only)"
  expected="scripts/quickshell-crash-report.txt"
  if [[ "$staged" != "$expected" ]]; then
    git -C "$REPO_DIR" restore --staged -- "$REPORT" 2>/dev/null || true
    die "refusing to commit: staged set is not exactly '$expected' (got: ${staged//$'\n'/, })"
  fi
  if git -C "$REPO_DIR" commit -m "Add Quickshell crash diagnostic report (desensitized)"; then
    new_head="$(git -C "$REPO_DIR" rev-parse HEAD)"
    if [[ "$new_head" == "$pre_push_head" ]]; then
      log "commit produced no new HEAD; skipping push"
    else
      # git push does NOT accept A..B as a refspec. To ship ONLY the report
      # commit (and never other unpushed local work), require:
      #   1. we are on a named branch (not detached HEAD)
      #   2. origin/<branch> == pre_push_head (no prior unpushed commits)
      #   3. exactly one commit between pre_push_head and HEAD (ours)
      # then `git push origin HEAD:refs/heads/<branch>` is a single-commit ship.
      branch="$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)"
      if [[ -z "$branch" || "$branch" == "HEAD" ]]; then
        die "refusing to push from detached HEAD; report commit is local at $REPORT"
      fi
      remote_ref="refs/remotes/origin/${branch}"
      if ! git -C "$REPO_DIR" rev-parse --verify "$remote_ref" >/dev/null 2>&1; then
        die "no origin/${branch} tracking ref; refusing to create a remote branch from diagnose. Report is local at $REPORT"
      fi
      remote_head="$(git -C "$REPO_DIR" rev-parse "$remote_ref")"
      if [[ "$remote_head" != "$pre_push_head" ]]; then
        die "refusing to push: origin/${branch} != pre-commit HEAD (would also ship other unpushed local commits). Report commit stays local at $REPORT"
      fi
      ahead="$(git -C "$REPO_DIR" rev-list --count "${pre_push_head}..HEAD")"
      if [[ "$ahead" -ne 1 ]]; then
        die "refusing to push: expected exactly 1 new commit on top of origin/${branch}, got ${ahead}. Report is local at $REPORT"
      fi
      git -C "$REPO_DIR" push origin "HEAD:refs/heads/${branch}" 2>&1 \
        || die "push failed; check network/credentials. Report is still local at $REPORT"
      log "pushed report commit $(git -C "$REPO_DIR" rev-parse --short HEAD) to origin/${branch}."
      log "  remote path (if origin is GitHub): <origin>/blob/${branch}/scripts/quickshell-crash-report.txt"
    fi
  else
    log "nothing new to commit (report unchanged); not pushing"
    git -C "$REPO_DIR" restore --staged -- "$REPORT" 2>/dev/null || true
  fi
fi

cat <<'EOF'

[diagnose] ------------------------------------------------------------
[diagnose] DONE. To recover your desktop NOW (optional), run:
[diagnose]
[diagnose]   cd $REPO && git reset --hard 4f0dd42 && bash scripts/arch-update.sh
[diagnose]
[diagnose] then re-login to niri. (4f0dd42 = last good commit before the
[diagnose] Control Center rewrite f2887cc that is crashing now.)
[diagnose] ------------------------------------------------------------
EOF
