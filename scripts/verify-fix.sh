#!/usr/bin/env bash
# Verify the fix is actually compiled in

echo "=== Checking if quickshell fix is compiled ==="
echo ""

# Check installed binary
QUICKSHELL_BIN="$HOME/.local/bin/quickshell"

if [ ! -f "$QUICKSHELL_BIN" ]; then
    echo "❌ Quickshell binary not found at: $QUICKSHELL_BIN"
    exit 1
fi

echo "✓ Binary found: $QUICKSHELL_BIN"
echo "  Size: $(du -h "$QUICKSHELL_BIN" | cut -f1)"
echo "  Modified: $(stat -c %y "$QUICKSHELL_BIN" 2>/dev/null || stat -f %Sm "$QUICKSHELL_BIN" 2>/dev/null)"
echo ""

# Check source code
REPO_DIR="${REPO_DIR:-$HOME/niri}"
SOURCE_FILE="$REPO_DIR/quickshell/src/wayland/tahoe_glass/qml.cpp"

if [ ! -f "$SOURCE_FILE" ]; then
    echo "❌ Source file not found: $SOURCE_FILE"
    exit 1
fi

echo "✓ Source file found"
echo ""

# Check if the fix is in the source
echo "Checking for fix in source code..."
if grep -q "QEvent::Move.*QEvent::Resize" "$SOURCE_FILE"; then
    echo "✓ Fix IS present in source code"
else
    echo "❌ Fix NOT found in source code!"
    echo "   The source may not be updated"
    exit 1
fi
echo ""

# Check git commit
cd "$REPO_DIR/quickshell"
CURRENT_COMMIT=$(git rev-parse HEAD)
EXPECTED_COMMIT="2e3c17611e9246e250a854aa3af1ead6d0f16d19"

echo "Current commit: $CURRENT_COMMIT"
echo "Expected commit: $EXPECTED_COMMIT"

if [ "$CURRENT_COMMIT" = "$EXPECTED_COMMIT" ]; then
    echo "✓ On correct commit"
else
    echo "❌ NOT on correct commit"
    echo "   Run: cd quickshell && git fetch && git reset --hard origin/quickshell-tahoe-desktop"
fi
echo ""

# Check build stamp
BUILD_STAMP="$REPO_DIR/quickshell/build-tahoe/.tahoe-installed-commit"
if [ -f "$BUILD_STAMP" ]; then
    BUILT_COMMIT=$(cat "$BUILD_STAMP")
    echo "Built commit: $BUILT_COMMIT"
    if [ "$BUILT_COMMIT" = "$CURRENT_COMMIT" ]; then
        echo "✓ Binary matches source commit"
    else
        echo "❌ Binary is from a different commit!"
        echo "   You need to rebuild quickshell"
    fi
else
    echo "❌ No build stamp found - quickshell may not be properly installed"
fi
echo ""

echo "=== Summary ==="
if [ "$CURRENT_COMMIT" = "$EXPECTED_COMMIT" ] && [ "$BUILT_COMMIT" = "$CURRENT_COMMIT" ]; then
    echo "✓ Everything looks correct"
    echo ""
    echo "If blur still doesn't update, the issue might be:"
    echo "1. Restart quickshell to load the new binary: pkill quickshell"
    echo "2. The compositor (niri) side needs to handle the updates"
    echo "3. Qt event system not firing Move/Resize events in niri"
else
    echo "❌ Issues found - rebuild needed"
    echo ""
    echo "Run: FORCE_QUICKSHELL_BUILD=true bash ~/niri/scripts/arch-update.sh"
fi
