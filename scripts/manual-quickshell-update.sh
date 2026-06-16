#!/usr/bin/env bash
# Simple manual update for quickshell - step by step with pauses

set -e

# Disable git pager to avoid 'less' errors
export GIT_PAGER=cat

REPO_DIR="${REPO_DIR:-"$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"}"
QUICKSHELL_DIR="${QUICKSHELL_DIR:-"$REPO_DIR/quickshell"}"

echo "========================================="
echo "Manual Quickshell Update Script"
echo "========================================="
echo ""
echo "This will update and rebuild quickshell step by step."
echo "Press Enter after each step to continue..."
echo ""

read -p "Press Enter to start..."

# Step 1
echo ""
echo "=== Step 1: Check current status ==="
cd "$REPO_DIR"
echo "Main repo:"
git log --oneline -1
echo ""
echo "Quickshell submodule:"
git submodule status quickshell
cd "$QUICKSHELL_DIR"
echo "Quickshell current commit:"
git log --oneline -1
git status
read -p "Press Enter to continue..."

# Step 2
echo ""
echo "=== Step 2: Pull main repo ==="
cd "$REPO_DIR"
git pull --ff-only || echo "Pull failed or already up to date"
read -p "Press Enter to continue..."

# Step 3
echo ""
echo "=== Step 3: Sync and update submodules ==="
git submodule sync --recursive
git submodule update --init --recursive quickshell
echo "After submodule update:"
git submodule status quickshell
read -p "Press Enter to continue..."

# Step 4
echo ""
echo "=== Step 4: Fetch latest from quickshell remote ==="
cd "$QUICKSHELL_DIR"
git fetch --prune
echo "Available commits:"
git log --oneline -5 origin/quickshell-tahoe-desktop
echo ""
echo "Current HEAD:"
git log --oneline -1 HEAD
read -p "Press Enter to continue..."

# Step 5
echo ""
echo "=== Step 5: Reset quickshell to latest origin/quickshell-tahoe-desktop ==="
git checkout quickshell-tahoe-desktop || git checkout -b quickshell-tahoe-desktop origin/quickshell-tahoe-desktop
git reset --hard origin/quickshell-tahoe-desktop
echo "After reset:"
git log --oneline -1
read -p "Press Enter to continue..."

# Step 6
echo ""
echo "=== Step 6: Check if rebuild is needed ==="
BUILD_STAMP="$QUICKSHELL_DIR/build-tahoe/.tahoe-installed-commit"
CURRENT_COMMIT="$(git rev-parse HEAD)"
echo "Current commit: $CURRENT_COMMIT"
if [ -f "$BUILD_STAMP" ]; then
    INSTALLED_COMMIT="$(cat "$BUILD_STAMP")"
    echo "Installed commit: $INSTALLED_COMMIT"
    if [ "$CURRENT_COMMIT" = "$INSTALLED_COMMIT" ]; then
        echo "✓ Build is already current - no rebuild needed!"
        echo "The fix should already be installed."
        exit 0
    else
        echo "✗ Build is outdated - rebuild needed"
    fi
else
    echo "✗ No build stamp found - rebuild needed"
fi
read -p "Press Enter to rebuild quickshell (this will take a few minutes)..."

# Step 7
echo ""
echo "=== Step 7: Rebuild quickshell ==="
cd "$REPO_DIR"
echo "Starting build... (this may take 5-10 minutes)"
FORCE_QUICKSHELL_BUILD=true bash scripts/arch-update.sh

echo ""
echo "========================================="
echo "Done! Restart niri or quickshell to apply changes."
echo "========================================="
