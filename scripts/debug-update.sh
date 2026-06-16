#!/usr/bin/env bash
# Debug script to check why arch-update.sh doesn't update quickshell

set -x  # Enable debug output

# Disable git pager to avoid 'less' errors
export GIT_PAGER=cat

REPO_DIR="${REPO_DIR:-"$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"}"
QUICKSHELL_DIR="${QUICKSHELL_DIR:-"$REPO_DIR/quickshell"}"

echo "=== Repository Status ==="
echo "REPO_DIR: $REPO_DIR"
echo "QUICKSHELL_DIR: $QUICKSHELL_DIR"
echo ""

echo "=== Main Repo Status ==="
cd "$REPO_DIR"
git status
git log --oneline -3
echo ""

echo "=== Quickshell Submodule Status ==="
git submodule status quickshell
echo ""

echo "=== Quickshell Directory Git Status ==="
cd "$QUICKSHELL_DIR"
pwd
git status
git log --oneline -3
echo ""

echo "=== Quickshell Branch Info ==="
git branch -vv
git remote -v
echo ""

echo "=== Checking if quickshell is a submodule ==="
cd "$REPO_DIR"
if git config --file "$REPO_DIR/.gitmodules" --get-regexp '^submodule\..*\.path$' | grep -q "quickshell"; then
  echo "✓ quickshell IS configured as a submodule"
  git config --file "$REPO_DIR/.gitmodules" --get-regexp 'submodule.quickshell'
else
  echo "✗ quickshell is NOT configured as a submodule"
fi
echo ""

echo "=== Test fetch and show what would be updated ==="
cd "$QUICKSHELL_DIR"
git fetch --prune
echo "Current commit: $(git rev-parse HEAD)"
echo "Remote commit: $(git rev-parse origin/quickshell-tahoe-desktop)"
git log --oneline HEAD..origin/quickshell-tahoe-desktop
echo ""

echo "=== Installed Quickshell Binary ==="
if command -v quickshell >/dev/null 2>&1; then
  which quickshell
  quickshell --version 2>/dev/null || echo "quickshell --version failed"
else
  echo "quickshell command not found"
fi

if [ -f "$HOME/.local/bin/quickshell" ]; then
  echo "Binary exists at: $HOME/.local/bin/quickshell"
  ls -lh "$HOME/.local/bin/quickshell"
else
  echo "No binary at $HOME/.local/bin/quickshell"
fi

if [ -f "$REPO_DIR/quickshell/build-tahoe/.tahoe-installed-commit" ]; then
  echo "Build stamp commit: $(cat "$REPO_DIR/quickshell/build-tahoe/.tahoe-installed-commit")"
else
  echo "No build stamp found"
fi
