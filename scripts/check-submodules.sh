#!/usr/bin/env bash
# Check submodule status in VM

export GIT_PAGER=cat

echo "==================================="
echo "Submodule Status Check"
echo "==================================="
echo ""

REPO_DIR="${REPO_DIR:-"$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"}"

cd "$REPO_DIR"

echo "Current directory: $(pwd)"
echo ""

echo "=== .gitmodules content ==="
cat .gitmodules
echo ""

echo "=== git submodule status ==="
git submodule status
echo ""

echo "=== Check if directories exist ==="
for dir in niri quickshell tahoe-shell; do
    if [ -d "$dir" ]; then
        echo "✓ $dir/ exists"
        if [ -d "$dir/.git" ] || [ -f "$dir/.git" ]; then
            echo "  → is a git repository"
            cd "$dir"
            echo "  → current commit: $(git rev-parse HEAD 2>/dev/null || echo 'ERROR')"
            echo "  → branch: $(git branch --show-current 2>/dev/null || echo 'detached HEAD')"
            cd "$REPO_DIR"
        else
            echo "  → NOT a git repository"
        fi
    else
        echo "✗ $dir/ does NOT exist"
    fi
done
echo ""

echo "=== What git submodule update would do ==="
git submodule update --init --recursive --dry-run 2>&1 || echo "(dry-run not supported, showing init status)"
echo ""

echo "=== tahoe-glass protocol sync (T-02) ==="
# Authoritative copy lives at protocols/tahoe-glass-v1.xml. Both submodule
# copies must match it byte-for-byte. This aggregator always prints the
# report and a PROTOCOL_SYNC_EXIT line, and always exits 0 itself — it is
# diagnostic output, not a CI gate. Automation that needs the exit status
# must call scripts/check-protocol-sync.sh directly.
PROTOCOL_SYNC_SCRIPT="${PROTOCOL_SYNC_SCRIPT:-"$REPO_DIR/scripts/check-protocol-sync.sh"}"
PROTOCOL_SYNC_ARGS=()
if [[ "${PROTOCOL_SYNC_ALLOW_MISSING:-false}" == "true" ]]; then
  PROTOCOL_SYNC_ARGS+=(--allow-missing)
fi
if [[ -f "$PROTOCOL_SYNC_SCRIPT" ]]; then
  PROTOCOL_SYNC_STATUS=0
  bash "$PROTOCOL_SYNC_SCRIPT" "${PROTOCOL_SYNC_ARGS[@]}" || PROTOCOL_SYNC_STATUS=$?
  echo "PROTOCOL_SYNC_EXIT=${PROTOCOL_SYNC_STATUS}"
  if [[ "$PROTOCOL_SYNC_STATUS" -ne 0 ]]; then
    echo "(protocol-sync exited $PROTOCOL_SYNC_STATUS — gate on scripts/check-protocol-sync.sh directly if needed)"
  fi
else
  echo "✗ $PROTOCOL_SYNC_SCRIPT missing"
  echo "PROTOCOL_SYNC_EXIT=1"
fi
echo ""

echo "=== Fork lag vs real upstream (T-01) ==="
# report-fork-lag.sh is the weekly divergence check for the niri and
# quickshell forks. This aggregator always prints the report and always
# exits 0 itself — it is diagnostic output, not a CI gate. Automation
# that needs the exit contract (0/1/2) must call report-fork-lag.sh
# directly. FORK_LAG_ENSURE_REMOTES defaults on so a fresh clone gets the
# canonical upstream remote; missing upstream/<branch> refs auto-fetch
# once inside the leaf script unless FORK_LAG_OFFLINE=true.
FORK_LAG_SCRIPT="${FORK_LAG_SCRIPT:-"$REPO_DIR/scripts/report-fork-lag.sh"}"
FORK_LAG_ARGS=()
if [[ "${FORK_LAG_ENSURE_REMOTES:-true}" == "true" ]]; then
  FORK_LAG_ARGS+=(--ensure-remotes)
fi
if [[ "${FORK_LAG_FETCH:-false}" == "true" && "${FORK_LAG_OFFLINE:-false}" == "true" ]]; then
  echo "WARNING: FORK_LAG_FETCH and FORK_LAG_OFFLINE both set; preferring --offline"
  FORK_LAG_ARGS+=(--offline)
elif [[ "${FORK_LAG_FETCH:-false}" == "true" ]]; then
  FORK_LAG_ARGS+=(--fetch)
elif [[ "${FORK_LAG_OFFLINE:-false}" == "true" ]]; then
  FORK_LAG_ARGS+=(--offline)
fi
if [[ "${FORK_LAG_STRICT:-false}" == "true" ]]; then
  FORK_LAG_ARGS+=(--strict)
fi
if [[ -f "$FORK_LAG_SCRIPT" ]]; then
  # Capture status without relying on set -e (this diagnostic script does
  # not enable it). A non-zero lag report must not hide the rest of the
  # submodule status output, and must not become this script's exit code.
  FORK_LAG_STATUS=0
  bash "$FORK_LAG_SCRIPT" "${FORK_LAG_ARGS[@]}" || FORK_LAG_STATUS=$?
  echo "FORK_LAG_EXIT=${FORK_LAG_STATUS}"
  if [[ "$FORK_LAG_STATUS" -ne 0 ]]; then
    echo "(fork-lag report exited $FORK_LAG_STATUS — gate on scripts/report-fork-lag.sh directly if needed)"
  fi
else
  echo "✗ $FORK_LAG_SCRIPT missing"
  echo "FORK_LAG_EXIT=1"
fi
echo ""

echo "=== Recommendation ==="
echo "If niri/ or quickshell/ don't exist or aren't initialized:"
echo "  Run: git submodule update --init --recursive"
echo ""
echo "If they exist but are on old commits:"
echo "  Run: bash scripts/force-quickshell-update.sh"
echo ""
echo "Fork lag (weekly):"
echo "  bash scripts/report-fork-lag.sh --ensure-remotes          # first run / auto-fetch missing refs"
echo "  bash scripts/report-fork-lag.sh --fetch                   # force-refresh upstream tips"
echo "  bash scripts/report-fork-lag.sh --strict                  # CI gate (exit 1 if behind/rewritten)"
echo "  FORK_LAG_FETCH=true bash scripts/check-submodules.sh     # same report inside this aggregator"
echo ""
echo "Protocol sync (T-02):"
echo "  bash scripts/check-protocol-sync.sh                      # must print result: IN_SYNC"
echo "  # after editing protocols/tahoe-glass-v1.xml, copy into both submodules before commit"
echo ""

# Explicit exit 0 so this diagnostic aggregator cannot accidentally inherit a
# non-zero status from a future uncaptured command. Leaf gates
# (check-protocol-sync.sh, report-fork-lag.sh) must be called directly when
# automation needs their exit contracts.
exit 0
