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

echo "=== Recommendation ==="
echo "If niri/ or quickshell/ don't exist or aren't initialized:"
echo "  Run: git submodule update --init --recursive"
echo ""
echo "If they exist but are on old commits:"
echo "  Run: bash scripts/force-quickshell-update.sh"
