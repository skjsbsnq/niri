#!/usr/bin/env bash
# Force update and rebuild quickshell submodule

set -e  # Exit on error

# Disable git pager to avoid 'less' errors
export GIT_PAGER=cat

REPO_DIR="${REPO_DIR:-"$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"}"
QUICKSHELL_DIR="${QUICKSHELL_DIR:-"$REPO_DIR/quickshell"}"

echo "=== Forcing Quickshell Update and Rebuild ==="
echo ""

cd "$REPO_DIR"

echo "[1/6] Pulling main repository..."
git pull --ff-only

echo ""
echo "[2/6] Syncing submodules..."
git submodule sync --recursive

echo ""
echo "[3/6] Updating quickshell submodule to main repo's recorded commit..."
git submodule update --init --recursive quickshell

echo ""
echo "[4/6] Fetching latest from quickshell remote..."
cd "$QUICKSHELL_DIR"
git fetch --prune

echo ""
echo "[5/6] Checking out quickshell-tahoe-desktop branch and pulling latest..."
git checkout quickshell-tahoe-desktop
git reset --hard origin/quickshell-tahoe-desktop

echo ""
echo "Current quickshell commit: $(git rev-parse HEAD)"
git log --oneline -3

echo ""
echo "[6/6] Triggering rebuild with FORCE_QUICKSHELL_BUILD=true..."
cd "$REPO_DIR"
FORCE_QUICKSHELL_BUILD=true BUILD_QUICKSHELL_FORK=auto bash scripts/arch-update.sh

echo ""
echo "=== Done! ==="
echo "Restart niri or quickshell to use the updated version."
